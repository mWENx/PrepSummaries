import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'excel_service.dart';

class DocxService {
  static const _wNS =
      'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

  /// Fills the FY26 mail-merge template and writes the result to [outputPath].
  ///
  /// [templateBytes]  — raw bytes of the .docx template
  /// [mergeFields]    — MERGEFIELD name → replacement value
  /// [bioNotes]       — biography bullet strings (replace "Sample" bullets)
  /// [contacts]       — structured contact report entries
  /// [donorFirstName] — first name for the Preferred_Mail_Name text replacement
  static Future<void> fillTemplate({
    required Uint8List templateBytes,
    required String outputPath,
    required Map<String, String> mergeFields,
    required List<String> bioNotes,
    required List<ContactEntry> contacts,
    required String donorFirstName,
  }) async {
    final archive = ZipDecoder().decodeBytes(templateBytes);
    final newArchive = Archive();

    for (final file in archive) {
      if (!file.isFile) {
        newArchive.addFile(file);
        continue;
      }

      if (_isWordXml(file.name)) {
        final xmlStr = utf8.decode(_fileBytes(file));
        final modified = _processXml(
          xmlStr,
          mergeFields,
          bioNotes: file.name == 'word/document.xml' ? bioNotes : null,
          contacts: file.name == 'word/document.xml' ? contacts : null,
          donorFirstName: donorFirstName,
        );
        final modifiedBytes = utf8.encode(modified);
        newArchive.addFile(
            ArchiveFile(file.name, modifiedBytes.length, modifiedBytes));
      } else {
        newArchive.addFile(file);
      }
    }

    final outputBytes = ZipEncoder().encode(newArchive)!;
    await File(outputPath).writeAsBytes(outputBytes);
  }

  // ── Internal helpers ──────────────────────────────────────────────────────

  static bool _isWordXml(String name) =>
      name == 'word/document.xml' ||
      name.startsWith('word/header') ||
      name.startsWith('word/footer');

  static Uint8List _fileBytes(ArchiveFile file) {
    final c = file.content;
    if (c is Uint8List) return c;
    if (c is List<int>) return Uint8List.fromList(c);
    throw Exception('Unexpected archive file content type: ${c.runtimeType}');
  }

  // ── XML processing ────────────────────────────────────────────────────────

  static String _processXml(
    String xmlStr,
    Map<String, String> mergeFields, {
    List<String>? bioNotes,
    List<ContactEntry>? contacts,
    required String donorFirstName,
  }) {
    final doc = XmlDocument.parse(xmlStr);

    // 1. Replace MERGEFIELD complex fields with their values
    _replaceMergeFields(doc, mergeFields);

    // 2. Replace «Preferred_Mail_Name» in static text (not a merge field)
    if (donorFirstName.isNotEmpty) {
      _replaceStaticText(
          doc, '\u00abPreferred_Mail_Name\u00bb', donorFirstName);
    }

    // 3. Replace "Sample" bio note bullets with real bio notes
    if (bioNotes != null) {
      _replaceBioNotes(doc, bioNotes);
    }

    // 4. Replace contact report placeholders with actual entries
    if (contacts != null) {
      _replaceContacts(doc, contacts);
    }

    return doc.toXmlString();
  }

  // ── MERGEFIELD replacement ────────────────────────────────────────────────
  //
  // Word complex merge fields follow this pattern within a <w:p>:
  //   <w:r>...<w:fldChar w:fldCharType="begin"/>...</w:r>
  //   <w:r>...<w:instrText> MERGEFIELD FieldName </w:instrText>...</w:r>
  //   <w:r>...<w:fldChar w:fldCharType="separate"/>...</w:r>
  //   <w:r>...<w:t>«FieldName»</w:t>...</w:r>   ← display run
  //   <w:r>...<w:fldChar w:fldCharType="end"/>...</w:r>
  //
  // Strategy: find each fldChar begin..end sequence, extract the field name
  // from instrText, look it up in mergeFields, then replace the entire
  // sequence with a single run containing the value (keeping the display
  // run's formatting).

  static void _replaceMergeFields(
      XmlDocument doc, Map<String, String> mergeFields) {
    // Process each paragraph that contains merge fields
    for (final p in doc.findAllElements('p', namespace: _wNS).toList()) {
      _replaceMergeFieldsInParagraph(p, mergeFields);
    }
  }

  static void _replaceMergeFieldsInParagraph(
      XmlElement paragraph, Map<String, String> mergeFields) {
    final runs = paragraph.childElements
        .where((e) => e.name.local == 'r')
        .toList();
    if (runs.isEmpty) return;

    // Find fldChar begin/separate/end sequences
    // We walk through runs collecting field sequences
    int i = 0;
    while (i < runs.length) {
      final run = runs[i];
      final fldChar = _getFldChar(run);

      if (fldChar != 'begin') {
        i++;
        continue;
      }

      // Found a begin — collect runs until end
      final beginIdx = i;
      String? fieldName;
      int? separateIdx;
      XmlElement? displayRun; // the run with the display text after separate
      int? endIdx;

      for (int j = beginIdx + 1; j < runs.length; j++) {
        final r = runs[j];

        // Check for instrText
        if (fieldName == null) {
          final instrText = _getInstrText(r);
          if (instrText != null) {
            final match =
                RegExp(r'MERGEFIELD\s+"?(\S+?)"?\s').firstMatch(instrText);
            if (match != null) {
              fieldName = match.group(1);
            }
          }
        }

        final fc = _getFldChar(r);
        if (fc == 'separate') {
          separateIdx = j;
        } else if (fc == 'end') {
          endIdx = j;
          // The display run is typically the run after separate
          if (separateIdx != null && separateIdx + 1 < j) {
            displayRun = runs[separateIdx + 1];
          }
          break;
        }
      }

      if (endIdx == null || fieldName == null) {
        i++;
        continue;
      }

      // Look up the value
      final value = mergeFields[fieldName];
      if (value == null) {
        // Field not in our map — skip
        i = endIdx + 1;
        continue;
      }

      // Build a replacement run: copy formatting from display run or begin run
      final sourceRun = displayRun ?? runs[beginIdx];
      final newRun = _buildReplacementRun(sourceRun, value);

      // Remove all runs from begin to end (inclusive) and insert newRun
      final parent = paragraph;
      final childList = parent.children.toList();
      final firstChild = runs[beginIdx];
      final lastChild = runs[endIdx];
      final firstPos = childList.indexOf(firstChild);
      final lastPos = childList.indexOf(lastChild);

      if (firstPos >= 0 && lastPos >= 0) {
        // Remove from last to first to keep indices valid
        for (int k = lastPos; k >= firstPos; k--) {
          parent.children.removeAt(k);
        }
        parent.children.insert(firstPos, newRun);
      }

      // Rebuild runs list after modification
      return _replaceMergeFieldsInParagraph(paragraph, mergeFields);
    }
  }

  static String? _getFldChar(XmlElement run) {
    for (final child in run.childElements) {
      if (child.name.local == 'fldChar') {
        return child.getAttribute('fldCharType',
            namespace: _wNS) ??
            child.getAttribute('fldCharType');
      }
    }
    return null;
  }

  static String? _getInstrText(XmlElement run) {
    for (final child in run.childElements) {
      if (child.name.local == 'instrText') {
        return child.innerText;
      }
    }
    return null;
  }

  /// Builds a new w:r element with the same rPr as [sourceRun] but with
  /// [text] as the content.
  static XmlElement _buildReplacementRun(XmlElement sourceRun, String text) {
    // Extract rPr from source run
    String rPrXml = '';
    for (final child in sourceRun.childElements) {
      if (child.name.local == 'rPr') {
        rPrXml = child.toXmlString();
        break;
      }
    }

    final escaped = _escapeXml(text);
    final fragment = XmlDocument.parse(
      '<?xml version="1.0"?>'
      '<root xmlns:w="$_wNS" xml:space="preserve">'
      '<w:r>$rPrXml<w:t xml:space="preserve">$escaped</w:t></w:r>'
      '</root>',
    );
    return fragment.rootElement.childElements.first.copy();
  }

  // ── Static text replacement ───────────────────────────────────────────────
  //
  // For text like «Preferred_Mail_Name» that is embedded in a regular run
  // (not a MERGEFIELD), we do simple text replacement across runs.

  static void _replaceStaticText(
      XmlDocument doc, String find, String replace) {
    for (final p in doc.findAllElements('p', namespace: _wNS).toList()) {
      final runs = p.childElements
          .where((e) => e.name.local == 'r')
          .toList();
      if (runs.isEmpty) continue;

      final textEls = runs
          .expand((r) => r.childElements.where((e) => e.name.local == 't'))
          .toList();
      if (textEls.isEmpty) continue;

      final fullText = textEls.map((t) => t.innerText).join();
      if (!fullText.contains(find)) continue;

      final newText = fullText.replaceAll(find, replace);

      // Write into first text element, clear the rest
      final first = textEls.first;
      first.children
        ..clear()
        ..add(XmlText(newText));
      final hasPreserve =
          first.attributes.any((a) => a.name.local == 'space');
      if (!hasPreserve) {
        first.attributes
            .add(XmlAttribute(XmlName('space', 'xml'), 'preserve'));
      }
      for (final t in textEls.skip(1)) {
        t.children.clear();
      }
    }
  }

  // ── Bio notes replacement ─────────────────────────────────────────────────
  //
  // The template has "Sample" bullets under BIOGRAPHICAL NOTES using
  // ListParagraph style. We find and replace them with the AI-generated notes.

  static void _replaceBioNotes(XmlDocument doc, List<String> bioNotes) {
    // Find all paragraphs with ListParagraph style containing "Sample"
    final sampleParagraphs = <XmlElement>[];
    for (final p in doc.findAllElements('p', namespace: _wNS).toList()) {
      final style = _getParagraphStyle(p);
      if (style != 'ListParagraph') continue;
      final text = _getParagraphText(p);
      if (text.trim() == 'Sample') {
        sampleParagraphs.add(p);
      }
    }

    if (sampleParagraphs.isEmpty) return;

    // Capture the first Sample paragraph's full pPr XML so we can
    // replicate its numbering (w:numPr), spacing, and font properties.
    final firstSample = sampleParagraphs.first;
    String? samplePprXml;
    String? sampleRprXml;
    for (final child in firstSample.childElements) {
      if (child.name.local == 'pPr') {
        samplePprXml = child.toXmlString();
        // Also grab the rPr nested inside pPr (paragraph-level run props)
        break;
      }
    }
    // Grab the run-level rPr from the first run
    for (final child in firstSample.childElements) {
      if (child.name.local == 'r') {
        for (final rc in child.childElements) {
          if (rc.name.local == 'rPr') {
            sampleRprXml = rc.toXmlString();
            break;
          }
        }
        break;
      }
    }

    final parent = firstSample.parent;
    if (parent == null) return;
    final insertIdx = parent.children.indexOf(firstSample);

    // Remove all Sample paragraphs
    for (final p in sampleParagraphs) {
      p.parent?.children.remove(p);
    }

    if (bioNotes.isEmpty) return;

    // Insert bio note paragraphs at the position of the first removed Sample
    final adjustedIdx = insertIdx.clamp(0, parent.children.length);
    for (int i = 0; i < bioNotes.length; i++) {
      final newP = _buildListParagraph(
          bioNotes[i], samplePprXml, sampleRprXml);
      parent.children.insert(adjustedIdx + i, newP);
    }
  }

  /// Builds a w:p that replicates the template's bullet formatting.
  /// Uses the captured pPr (with numPr for bullet, spacing, fonts) and
  /// rPr (run-level font/size) from the original "Sample" paragraphs.
  static XmlElement _buildListParagraph(
      String text, String? pPrXml, String? rPrXml) {
    final escaped = _escapeXml(text);
    // Fall back to a basic ListParagraph if we couldn't capture the original
    final pPr = pPrXml ?? '<w:pPr><w:pStyle w:val="ListParagraph"/></w:pPr>';
    final rPr = rPrXml ?? '';
    final fragment = XmlDocument.parse(
      '<?xml version="1.0"?>'
      '<root xmlns:w="$_wNS" xml:space="preserve">'
      '<w:p>$pPr'
      '<w:r>$rPr<w:t xml:space="preserve">$escaped</w:t></w:r>'
      '</w:p>'
      '</root>',
    );
    return fragment.rootElement.childElements.first.copy();
  }

  // ── Contact reports replacement ───────────────────────────────────────────
  //
  // The template has placeholder paragraphs:
  //   <<Contact Report Headline>>    (SectionHeading style)
  //   <<<Contact report text>>       (Normal style)
  // These appear twice. We replace them with actual contact entries.

  static void _replaceContacts(
      XmlDocument doc, List<ContactEntry> contacts) {
    // Find all placeholder paragraphs for contacts
    final headlinePlaceholders = <XmlElement>[];
    final textPlaceholders = <XmlElement>[];

    for (final p in doc.findAllElements('p', namespace: _wNS).toList()) {
      final text = _getParagraphText(p);
      if (text.contains('Contact Report Headline')) {
        headlinePlaceholders.add(p);
      } else if (text.contains('Contact report text')) {
        textPlaceholders.add(p);
      }
    }

    if (headlinePlaceholders.isEmpty && textPlaceholders.isEmpty) return;

    // Find the insertion point — use the first headline placeholder
    final firstPlaceholder = headlinePlaceholders.isNotEmpty
        ? headlinePlaceholders.first
        : textPlaceholders.first;
    final parent = firstPlaceholder.parent;
    if (parent == null) return;
    final insertIdx = parent.children.indexOf(firstPlaceholder);

    // Capture run-level rPr from body placeholder for consistent font/size
    String? bodyRprXml;
    if (textPlaceholders.isNotEmpty) {
      for (final r in textPlaceholders.first.childElements
          .where((e) => e.name.local == 'r')) {
        for (final child in r.childElements) {
          if (child.name.local == 'rPr') {
            bodyRprXml = child.toXmlString();
            break;
          }
        }
        if (bodyRprXml != null) break;
      }
    }
    // Capture pPr from body placeholder for spacing/line height
    String? bodyPprInner;
    if (textPlaceholders.isNotEmpty) {
      final pPr = textPlaceholders.first.childElements
          .where((e) => e.name.local == 'pPr')
          .firstOrNull;
      if (pPr != null) {
        // Get inner XML (children) but strip any pStyle to avoid SectionHeading
        final innerBuf = StringBuffer();
        for (final child in pPr.childElements) {
          if (child.name.local != 'pStyle') {
            innerBuf.write(child.toXmlString());
          }
        }
        bodyPprInner = innerBuf.toString();
      }
    }

    // Remove all placeholder paragraphs
    for (final p in headlinePlaceholders) {
      p.parent?.children.remove(p);
    }
    for (final p in textPlaceholders) {
      p.parent?.children.remove(p);
    }

    if (contacts.isEmpty) return;

    // Insert real contact entries
    final adjustedIdx = insertIdx.clamp(0, parent.children.length);
    int offset = 0;
    for (final contact in contacts) {
      // Headline paragraph — normal body font, underlined
      final headlineP =
          _buildContactHeadline(contact.headline, bodyPprInner, bodyRprXml);
      parent.children.insert(adjustedIdx + offset, headlineP);
      offset++;

      // Body paragraph
      if (contact.body.isNotEmpty) {
        final bodyP = _buildContactBody(contact.body, bodyPprInner, bodyRprXml);
        parent.children.insert(adjustedIdx + offset, bodyP);
        offset++;
      }
    }
  }

  /// Builds a contact headline paragraph — same body font but underlined.
  static XmlElement _buildContactHeadline(
      String text, String? pPrInner, String? rPrXml) {
    final escaped = _escapeXml(text);
    // Add spacing-before for visual separation between contacts
    final pPr = '<w:pPr><w:spacing w:before="240"/>${pPrInner ?? ''}</w:pPr>';
    // Take body rPr and inject underline
    String rPr;
    if (rPrXml != null) {
      // Insert <w:u w:val="single"/> inside the existing <w:rPr>
      rPr = rPrXml.replaceFirst('</w:rPr>', '<w:u w:val="single"/></w:rPr>');
    } else {
      rPr = '<w:rPr><w:rFonts w:ascii="Akkurat Pro" w:hAnsi="Akkurat Pro"/>'
          '<w:sz w:val="20"/><w:szCs w:val="20"/>'
          '<w:u w:val="single"/></w:rPr>';
    }
    final fragment = XmlDocument.parse(
      '<?xml version="1.0"?>'
      '<root xmlns:w="$_wNS" xml:space="preserve">'
      '<w:p>$pPr'
      '<w:r>$rPr<w:t xml:space="preserve">$escaped</w:t></w:r>'
      '</w:p>'
      '</root>',
    );
    return fragment.rootElement.childElements.first.copy();
  }

  /// Builds a contact body paragraph with the template's body font/size.
  static XmlElement _buildContactBody(
      String text, String? pPrInner, String? rPrXml) {
    final escaped = _escapeXml(text);
    final pPr = pPrInner != null ? '<w:pPr>$pPrInner</w:pPr>' : '';
    final rPr = rPrXml ??
        '<w:rPr><w:rFonts w:ascii="Akkurat Pro" w:hAnsi="Akkurat Pro"/>'
            '<w:sz w:val="20"/><w:szCs w:val="20"/></w:rPr>';
    final fragment = XmlDocument.parse(
      '<?xml version="1.0"?>'
      '<root xmlns:w="$_wNS" xml:space="preserve">'
      '<w:p>$pPr'
      '<w:r>$rPr<w:t xml:space="preserve">$escaped</w:t></w:r>'
      '</w:p>'
      '</root>',
    );
    return fragment.rootElement.childElements.first.copy();
  }

  // ── Paragraph helpers ─────────────────────────────────────────────────────

  static String _getParagraphStyle(XmlElement p) {
    for (final child in p.childElements) {
      if (child.name.local == 'pPr') {
        for (final prop in child.childElements) {
          if (prop.name.local == 'pStyle') {
            return prop.getAttribute('val', namespace: _wNS) ??
                prop.getAttribute('val') ??
                '';
          }
        }
      }
    }
    return '';
  }

  static String _getParagraphText(XmlElement p) {
    return p
        .findAllElements('t', namespace: _wNS)
        .map((t) => t.innerText)
        .join();
  }

  static String _escapeXml(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  // ── Create a .docx from markdown-style text ────────────────────────────

  /// Creates a standalone .docx from simple markdown content.
  /// Supports: # headings, **bold**, > blockquotes, - bullets, --- breaks.
  static Future<void> createFromMarkdown({
    required String markdownContent,
    required String outputPath,
  }) async {
    final paragraphs = <String>[];

    for (final line in markdownContent.split('\n')) {
      final trimmed = line.trimRight();

      if (trimmed.isEmpty) {
        paragraphs.add(_mdParagraph('', null));
        continue;
      }

      if (trimmed == '---') {
        paragraphs.add(_mdHr());
        continue;
      }

      if (trimmed.startsWith('### ')) {
        paragraphs.add(_mdHeading(trimmed.substring(4), 22, false));
      } else if (trimmed.startsWith('## ')) {
        paragraphs.add(_mdHeading(trimmed.substring(3), 24, true));
      } else if (trimmed.startsWith('# ')) {
        paragraphs.add(_mdHeading(trimmed.substring(2), 28, true));
      } else if (trimmed.startsWith('> ')) {
        paragraphs.add(_mdBlockquote(trimmed.substring(2)));
      } else if (trimmed.startsWith('- ')) {
        paragraphs.add(_mdBullet(trimmed.substring(2)));
      } else {
        paragraphs.add(_mdParagraph(trimmed, null));
      }
    }

    final bodyContent = paragraphs.join('\n');
    final documentXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="$_wNS"
            xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
  <w:body>
$bodyContent
    <w:sectPr>
      <w:pgSz w:w="12240" w:h="15840"/>
      <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"
               w:header="720" w:footer="720" w:gutter="0"/>
    </w:sectPr>
  </w:body>
</w:document>''';

    const contentTypes = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
  <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
  <Default Extension="xml" ContentType="application/xml"/>
  <Override PartName="/word/document.xml"
            ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
  <Override PartName="/word/numbering.xml"
            ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>
</Types>''';

    const rels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>''';

    const docRels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
  <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/numbering" Target="numbering.xml"/>
</Relationships>''';

    const numberingXml = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:numbering xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
  <w:abstractNum w:abstractNumId="0">
    <w:lvl w:ilvl="0">
      <w:start w:val="1"/>
      <w:numFmt w:val="bullet"/>
      <w:lvlText w:val="\u2022"/>
      <w:lvlJc w:val="left"/>
      <w:pPr><w:ind w:left="720" w:hanging="360"/></w:pPr>
    </w:lvl>
  </w:abstractNum>
  <w:num w:numId="1">
    <w:abstractNumId w:val="0"/>
  </w:num>
</w:numbering>''';

    final archive = Archive();

    void addFile(String name, String content) {
      final bytes = utf8.encode(content);
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
    }

    addFile('[Content_Types].xml', contentTypes);
    addFile('_rels/.rels', rels);
    addFile('word/_rels/document.xml.rels', docRels);
    addFile('word/document.xml', documentXml);
    addFile('word/numbering.xml', numberingXml);

    final outputBytes = ZipEncoder().encode(archive)!;
    await File(outputPath).writeAsBytes(outputBytes);
  }

  // ── Markdown → Word XML helpers ────────────────────────────────────────

  static String _mdRuns(String text, {String? rPrExtra}) {
    final buf = StringBuffer();
    final parts = text.split('**');
    for (int i = 0; i < parts.length; i++) {
      final part = parts[i];
      if (part.isEmpty) continue;
      final isBold = i % 2 == 1;
      final escaped = _escapeXml(part);
      final rPr = StringBuffer();
      if (isBold || (rPrExtra != null && rPrExtra.isNotEmpty)) {
        rPr.write('<w:rPr>');
        if (isBold) rPr.write('<w:b/><w:bCs/>');
        if (rPrExtra != null) rPr.write(rPrExtra);
        rPr.write('</w:rPr>');
      }
      buf.write(
          '<w:r>$rPr<w:t xml:space="preserve">$escaped</w:t></w:r>');
    }
    return buf.toString();
  }

  static String _mdParagraph(String text, String? pPr) {
    final pPrXml = pPr != null ? '<w:pPr>$pPr</w:pPr>' : '';
    return '    <w:p>$pPrXml${_mdRuns(text)}</w:p>';
  }

  static String _mdHeading(String text, int sizeHalfPt, bool bold) {
    final rPr = '<w:sz w:val="$sizeHalfPt"/><w:szCs w:val="$sizeHalfPt"/>';
    final pPr = '<w:pPr><w:spacing w:before="240" w:after="80"/></w:pPr>';
    final bPr = bold ? '<w:b/><w:bCs/>' : '';
    return '    <w:p>$pPr${_mdRuns(text, rPrExtra: '$bPr$rPr')}</w:p>';
  }

  static String _mdBlockquote(String text) {
    final pPr =
        '<w:ind w:left="480"/><w:pBdr><w:left w:val="single" w:sz="4" w:space="8" w:color="999999"/></w:pBdr>';
    final rPr = '<w:color w:val="555555"/><w:sz w:val="20"/><w:szCs w:val="20"/>';
    return '    <w:p><w:pPr>$pPr</w:pPr>${_mdRuns(text, rPrExtra: rPr)}</w:p>';
  }

  static String _mdBullet(String text) {
    const pPr =
        '<w:pStyle w:val="ListParagraph"/><w:numPr><w:ilvl w:val="0"/><w:numId w:val="1"/></w:numPr>';
    return '    <w:p><w:pPr>$pPr</w:pPr>${_mdRuns(text)}</w:p>';
  }

  static String _mdHr() {
    return '    <w:p>'
        '<w:pPr><w:pBdr><w:bottom w:val="single" w:sz="4" w:space="1" w:color="CCCCCC"/></w:pBdr></w:pPr>'
        '</w:p>';
  }
}
