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

    // Use the first Sample paragraph's position and style as template
    final firstSample = sampleParagraphs.first;
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
      final newP = _buildListParagraph(bioNotes[i]);
      parent.children.insert(adjustedIdx + i, newP);
    }
  }

  /// Builds a w:p with ListParagraph style and the given text.
  static XmlElement _buildListParagraph(String text) {
    final escaped = _escapeXml(text);
    final fragment = XmlDocument.parse(
      '<?xml version="1.0"?>'
      '<root xmlns:w="$_wNS" xml:space="preserve">'
      '<w:p>'
      '<w:pPr><w:pStyle w:val="ListParagraph"/></w:pPr>'
      '<w:r><w:t xml:space="preserve">$escaped</w:t></w:r>'
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

    // Extract the SectionHeading style pPr from the first headline placeholder
    // so we can replicate it for real contact headlines
    String? headlineStyleXml;
    if (headlinePlaceholders.isNotEmpty) {
      final pPr = headlinePlaceholders.first.childElements
          .where((e) => e.name.local == 'pPr')
          .firstOrNull;
      if (pPr != null) {
        headlineStyleXml = pPr.toXmlString();
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
      // Headline paragraph
      final headlineP =
          _buildContactHeadline(contact.headline, headlineStyleXml);
      parent.children.insert(adjustedIdx + offset, headlineP);
      offset++;

      // Body paragraph
      if (contact.body.isNotEmpty) {
        final bodyP = _buildContactBody(contact.body);
        parent.children.insert(adjustedIdx + offset, bodyP);
        offset++;
      }
    }
  }

  static XmlElement _buildContactHeadline(
      String text, String? pPrXml) {
    final escaped = _escapeXml(text);
    final styleBlock =
        pPrXml ?? '<w:pPr><w:pStyle w:val="SectionHeading"/></w:pPr>';
    final fragment = XmlDocument.parse(
      '<?xml version="1.0"?>'
      '<root xmlns:w="$_wNS" xml:space="preserve">'
      '<w:p>$styleBlock'
      '<w:r><w:t xml:space="preserve">$escaped</w:t></w:r>'
      '</w:p>'
      '</root>',
    );
    return fragment.rootElement.childElements.first.copy();
  }

  static XmlElement _buildContactBody(String text) {
    final escaped = _escapeXml(text);
    final fragment = XmlDocument.parse(
      '<?xml version="1.0"?>'
      '<root xmlns:w="$_wNS" xml:space="preserve">'
      '<w:p>'
      '<w:r><w:t xml:space="preserve">$escaped</w:t></w:r>'
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
}
