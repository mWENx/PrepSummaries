import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// One donor's data for the event briefing.
class EventDonorEntry {
  final Map<String, String> mergeFields;
  final List<String> bioNotes;
  const EventDonorEntry({
    required this.mergeFields,
    required this.bioNotes,
  });
}

class EventDocxService {
  static const _wNS =
      'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

  /// Fills the event briefing template for [donors] and writes a single
  /// .docx to [outputPath].  Each donor reuses the first-block template
  /// (paragraphs 0..NEXT-1) with a page break between donors.
  static Future<void> fillEventTemplate({
    required Uint8List templateBytes,
    required String outputPath,
    required List<EventDonorEntry> donors,
  }) async {
    if (donors.isEmpty) return;

    final archive = ZipDecoder().decodeBytes(templateBytes);

    final otherFiles = <ArchiveFile>[];
    String? templateDocXml;

    for (final file in archive) {
      if (!file.isFile) continue;
      if (file.name == 'word/document.xml') {
        templateDocXml = utf8.decode(_fileBytes(file));
      } else {
        otherFiles.add(file);
      }
    }

    if (templateDocXml == null) {
      throw Exception('word/document.xml not found in template.');
    }

    // ── Extract the single-donor block (paragraphs 0..NEXT-1) ────────────
    final singleBlock = _extractSingleDonorBlock(templateDocXml);

    // ── Build combined body XML ───────────────────────────────────────────
    final bodySections = <String>[];
    for (int i = 0; i < donors.length; i++) {
      final donorXml =
          _fillDonorBlock(singleBlock, donors[i].mergeFields, donors[i].bioNotes);
      bodySections.add(donorXml);
    }

    // ── Assemble final document preserving original namespaces ────────────
    final sectPrXml = _extractSectPr(templateDocXml);
    final docOpenTag = _extractDocOpenTag(templateDocXml);
    final pageBreak =
        '<w:p xmlns:w="$_wNS"><w:r><w:br w:type="page"/></w:r></w:p>';

    final bodyContent = bodySections.join('\n$pageBreak\n');
    final finalXml = '$docOpenTag\n<w:body>\n$bodyContent\n$sectPrXml\n</w:body>\n</w:document>';

    final newArchive = Archive();
    for (final file in otherFiles) {
      newArchive.addFile(file);
    }
    final docBytes = utf8.encode(finalXml);
    newArchive
        .addFile(ArchiveFile('word/document.xml', docBytes.length, docBytes));

    final outputBytes = ZipEncoder().encode(newArchive)!;
    await File(outputPath).writeAsBytes(outputBytes);
  }

  // ── Single-donor block extraction ─────────────────────────────────────────
  //
  // The template is a mail-merge document with 20 repeated donor blocks.
  // The first block is paragraphs 0..N where N is the index just before the
  // first paragraph containing a NEXT/NEXT RECORD field instruction.
  // We capture those paragraphs as raw XML strings and use them as the
  // template for every generated donor.

  static List<String> _extractSingleDonorBlock(String docXml) {
    final doc = XmlDocument.parse(docXml);
    final body = doc.findAllElements('body', namespace: _wNS).firstOrNull;
    if (body == null) return [];

    final paragraphs = body.childElements
        .where((e) => e.name.local == 'p')
        .toList();

    final block = <String>[];
    for (final para in paragraphs) {
      // Stop at the NEXT record paragraph
      final instrTexts = para
          .findAllElements('instrText', namespace: _wNS)
          .map((e) => e.innerText.trim().toUpperCase())
          .toList();
      if (instrTexts.any((t) => t == 'NEXT' || t.startsWith('NEXT '))) break;

      block.add(para.toXmlString());
    }
    return block;
  }

  // ── Fill a donor block ────────────────────────────────────────────────────
  //
  // Parse ALL paragraphs together so cross-paragraph merge fields
  // (where begin is in one paragraph and separate/end in the next) are found.

  static String _fillDonorBlock(
    List<String> blockParas,
    Map<String, String> mergeFields,
    List<String> bioNotes,
  ) {
    // Wrap all paragraphs in a single XML root so we can do cross-paragraph
    // merge field replacement in one pass.
    final allParasXml = blockParas.join('\n');
    final doc = XmlDocument.parse(
      '<?xml version="1.0"?>'
      '<w:body xmlns:w="$_wNS"'
      ' xmlns:w14="http://schemas.microsoft.com/office/word/2010/wordml"'
      ' xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'
      ' xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"'
      ' xmlns:mc="http://schemas.openxmlformats.org/markup-compatibility/2006">'
      '$allParasXml'
      '</w:body>',
    );

    // Cross-paragraph merge field replacement (handles fields that span paragraphs)
    _replaceCrossParagraphMergeFields(doc.rootElement, mergeFields);

    // Now handle the bio ListParagraph — find and replace it with bullets
    _replaceBioFieldInBlock(doc.rootElement, bioNotes);

    // Serialize each paragraph back
    final filled = <String>[];
    for (final child in doc.rootElement.childElements) {
      filled.add(child.toXmlString());
    }
    return filled.join('\n');
  }

  // ── Cross-paragraph merge field replacement ────────────────────────────────

  static void _replaceCrossParagraphMergeFields(
      XmlElement root, Map<String, String> mergeFields) {
    final allRuns = root.findAllElements('r', namespace: _wNS).toList();
    if (allRuns.isEmpty) return;

    int i = 0;
    while (i < allRuns.length) {
      final run = allRuns[i];
      if (_getFldChar(run) != 'begin') {
        i++;
        continue;
      }

      String? fieldName;
      XmlElement? separateRun;
      XmlElement? displayRun;
      int? endIdx;

      for (int j = i + 1; j < allRuns.length; j++) {
        final r = allRuns[j];
        if (fieldName == null) {
          final instrText = _getInstrText(r);
          if (instrText != null) {
            final match =
                RegExp(r'MERGEFIELD\s+"?([^\s"\\]+)"?').firstMatch(instrText);
            if (match != null) fieldName = match.group(1);
          }
        }
        final fc = _getFldChar(r);
        if (fc == 'separate') {
          separateRun = r;
        } else if (fc == 'end') {
          endIdx = j;
          if (separateRun != null) {
            final sepIdx = allRuns.indexOf(separateRun);
            if (sepIdx + 1 < j) displayRun = allRuns[sepIdx + 1];
          }
          break;
        }
      }

      if (endIdx == null || fieldName == null) {
        i++;
        continue;
      }

      final value = mergeFields[fieldName];
      if (value != null && displayRun != null) {
        for (final t in displayRun.findAllElements('t', namespace: _wNS)) {
          t.children..clear()..add(XmlText(value));
          if (!t.attributes.any((a) => a.name.local == 'space')) {
            t.attributes
                .add(XmlAttribute(XmlName('space', 'xml'), 'preserve'));
          }
        }
      }
      i = endIdx + 1;
    }
  }

  // ── Bio paragraph builders ────────────────────────────────────────────────

  /// Returns an empty paragraph with the same pPr as the bio template paragraph.
  static String _emptyListParagraph(String templateParaXml) {
    final doc = XmlDocument.parse(
        '<?xml version="1.0"?><root xmlns:w="$_wNS">$templateParaXml</root>');
    final para = doc.rootElement.childElements.first;
    // Remove all runs, keep pPr
    final toRemove = para.childElements
        .where((e) => e.name.local == 'r')
        .toList();
    for (final r in toRemove) {
      para.children.remove(r);
    }
    return para.toXmlString();
  }

  /// Builds a bullet paragraph reusing the pPr and rPr from the bio template.
  static String _buildBulletParagraph(String templateParaXml, String text) {
    final doc = XmlDocument.parse(
        '<?xml version="1.0"?><root xmlns:w="$_wNS"'
        ' xmlns:w14="http://schemas.microsoft.com/office/word/2010/wordml">'
        '$templateParaXml</root>');
    final templatePara = doc.rootElement.childElements.first;

    // Extract pPr
    String pPrXml = '';
    for (final child in templatePara.childElements) {
      if (child.name.local == 'pPr') {
        pPrXml = child.toXmlString();
        break;
      }
    }

    // Extract rPr from the first run that has one
    String rPrXml = '';
    for (final run in templatePara.childElements.where((e) => e.name.local == 'r')) {
      for (final child in run.childElements) {
        if (child.name.local == 'rPr') {
          rPrXml = child.toXmlString();
          break;
        }
      }
      if (rPrXml.isNotEmpty) break;
    }

    final escaped = _escapeXml(text);
    return '<w:p xmlns:w="$_wNS">'
        '$pPrXml'
        '<w:r>$rPrXml<w:t xml:space="preserve">$escaped</w:t></w:r>'
        '</w:p>';
  }

  // ── Bio replacement on block root ────────────────────────────────────────

  /// Finds the Biographical_Information ListParagraph within [root], captures
  /// its formatting, removes it, and inserts one bullet paragraph per bio note.
  static void _replaceBioFieldInBlock(
      XmlElement root, List<String> bioNotes) {
    XmlElement? bioPara;
    for (final para
        in root.childElements.where((e) => e.name.local == 'p')) {
      final instrTexts = para
          .findAllElements('instrText', namespace: _wNS)
          .map((e) => e.innerText.trim())
          .toList();
      if (instrTexts.any((t) => t.contains('Biographical_Information'))) {
        bioPara = para;
        break;
      }
    }
    if (bioPara == null) return;

    final templateXml = bioPara.toXmlString();
    final insertIdx = root.children.indexOf(bioPara);
    root.children.remove(bioPara);

    final insertions = <XmlNode>[];
    if (bioNotes.isEmpty) {
      final emptyXml = _emptyListParagraph(templateXml);
      final emptyDoc = XmlDocument.parse(
          '<?xml version="1.0"?><root xmlns:w="$_wNS">$emptyXml</root>');
      insertions.add(emptyDoc.rootElement.childElements.first.copy());
    } else {
      for (final note in bioNotes) {
        final bulletXml = _buildBulletParagraph(templateXml, note);
        final bulletDoc = XmlDocument.parse(
            '<?xml version="1.0"?><root xmlns:w="$_wNS"'
            ' xmlns:w14="http://schemas.microsoft.com/office/word/2010/wordml">'
            '$bulletXml</root>');
        insertions.add(bulletDoc.rootElement.childElements.first.copy());
      }
    }

    for (int i = insertions.length - 1; i >= 0; i--) {
      root.children.insert(insertIdx, insertions[i]);
    }
  }

  // ── Document structure helpers ────────────────────────────────────────────

  static String _extractDocOpenTag(String docXml) {
    final match = RegExp(r'<w:document[^>]+>').firstMatch(docXml);
    return match?.group(0) ?? '<w:document xmlns:w="$_wNS">';
  }

  static String _extractSectPr(String docXml) {
    final match =
        RegExp(r'<w:sectPr.*?</w:sectPr>', multiLine: true, dotAll: true)
            .allMatches(docXml)
            .lastOrNull;
    return match?.group(0) ?? '';
  }

  // ── XML helpers ────────────────────────────────────────────────────────────

  static String? _getFldChar(XmlElement run) {
    for (final child in run.childElements) {
      if (child.name.local == 'fldChar') {
        return child.getAttribute('fldCharType', namespace: _wNS) ??
            child.getAttribute('fldCharType');
      }
    }
    return null;
  }

  static String? _getInstrText(XmlElement run) {
    for (final child in run.childElements) {
      if (child.name.local == 'instrText') return child.innerText;
    }
    return null;
  }

  static Uint8List _fileBytes(ArchiveFile file) {
    final c = file.content;
    if (c is Uint8List) return c;
    if (c is List<int>) return Uint8List.fromList(c);
    throw Exception('Unexpected content type: ${c.runtimeType}');
  }

  static String _escapeXml(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
