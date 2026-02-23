import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

class DocxService {
  static const _wNS =
      'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

  /// Fills a .docx template and writes the result to [outputPath].
  ///
  /// [templateBytes] — raw bytes of the template .docx
  /// [replacements]  — map of {{placeholder}} → replacement text
  /// [bioNotes]      — list of biography bullet strings for {{bio_notes}}
  static Future<void> fillTemplate({
    required Uint8List templateBytes,
    required String outputPath,
    required Map<String, String> replacements,
    required List<String> bioNotes,
  }) async {
    final archive = ZipDecoder().decodeBytes(templateBytes);

    // Check whether a "ListBullet" style is defined in the template
    final stylesFile = _findFile(archive, 'word/styles.xml');
    final hasListBullet = stylesFile != null &&
        utf8.decode(_fileBytes(stylesFile)).contains('ListBullet');

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
          replacements,
          bioNotes: file.name == 'word/document.xml' ? bioNotes : null,
          hasListBullet: hasListBullet,
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

  static ArchiveFile? _findFile(Archive archive, String name) {
    for (final f in archive) {
      if (f.name == name) return f;
    }
    return null;
  }

  static Uint8List _fileBytes(ArchiveFile file) {
    final c = file.content;
    if (c is Uint8List) return c;
    if (c is List<int>) return Uint8List.fromList(c);
    throw Exception('Unexpected archive file content type: ${c.runtimeType}');
  }

  // ── XML processing ────────────────────────────────────────────────────────

  static String _processXml(
    String xmlStr,
    Map<String, String> replacements, {
    List<String>? bioNotes,
    required bool hasListBullet,
  }) {
    final doc = XmlDocument.parse(xmlStr);
    _processElement(doc.rootElement, replacements);
    if (bioNotes != null) {
      _insertBioNotes(doc, bioNotes, hasListBullet);
    }
    return doc.toXmlString();
  }

  /// Recursively walks the element tree. When a `w:p` is found, applies
  /// placeholder replacement and stops recursing (matching Python behaviour).
  static void _processElement(
      XmlElement el, Map<String, String> replacements) {
    if (el.name.local == 'p') {
      _replaceInParagraph(el, replacements);
      return; // do not recurse into paragraph children
    }
    for (final child in el.childElements.toList()) {
      _processElement(child, replacements);
    }
  }

  /// Mirrors Python's replace_in_paragraph():
  /// joins all w:t text within w:r runs, applies replacements,
  /// puts the result in the first w:t and clears the rest.
  static void _replaceInParagraph(
      XmlElement paragraph, Map<String, String> replacements) {
    final runs = paragraph.childElements
        .where((e) => e.name.local == 'r')
        .toList();
    if (runs.isEmpty) return;

    final textEls = runs
        .expand((r) => r.childElements.where((e) => e.name.local == 't'))
        .toList();
    if (textEls.isEmpty) return;

    final fullText = textEls.map((t) => t.innerText).join();
    var newText = fullText;
    for (final entry in replacements.entries) {
      newText = newText.replaceAll(entry.key, entry.value);
    }
    if (newText == fullText) return;

    // Write new text into the first w:t element
    final first = textEls.first;
    first.children
      ..clear()
      ..add(XmlText(newText));

    // Ensure xml:space="preserve" so Word keeps leading/trailing spaces
    final hasPreserve =
        first.attributes.any((a) => a.name.local == 'space');
    if (!hasPreserve) {
      first.attributes
          .add(XmlAttribute(XmlName('space', 'xml'), 'preserve'));
    }

    // Clear remaining text elements
    for (final t in textEls.skip(1)) {
      t.children.clear();
    }
  }

  // ── Bio notes insertion ───────────────────────────────────────────────────

  /// Mirrors Python's insert_bio_notes():
  /// finds the {{bio_notes}} paragraph, removes it, and inserts
  /// a bullet paragraph for each biography string.
  static void _insertBioNotes(
      XmlDocument doc, List<String> bioNotes, bool hasListBullet) {
    XmlElement? bioP;
    for (final p in doc.findAllElements('p', namespace: _wNS)) {
      final text = p
          .findAllElements('t', namespace: _wNS)
          .map((t) => t.innerText)
          .join();
      if (text.contains('{{bio_notes}}')) {
        bioP = p;
        break;
      }
    }
    if (bioP == null) return;

    final parent = bioP.parent;
    if (parent == null) return;
    final idx = parent.children.indexOf(bioP);
    parent.children.removeAt(idx);

    if (bioNotes.isEmpty) return;

    for (int i = 0; i < bioNotes.length; i++) {
      final newP = _buildBulletParagraph(bioNotes[i], hasListBullet);
      parent.children.insert(idx + i, newP);
    }
  }

  /// Builds a w:p element containing one run of text.
  /// Uses the ListBullet style when available, otherwise prepends "• ".
  static XmlElement _buildBulletParagraph(String text, bool hasListBullet) {
    final displayText = hasListBullet ? text : '• $text';
    final escaped = _escapeXml(displayText);

    final styleBlock = hasListBullet
        ? '<w:pPr><w:pStyle w:val="ListBullet"/></w:pPr>'
        : '';

    // Parse in a temporary document that carries the w: namespace declaration
    final fragment = XmlDocument.parse(
      '<?xml version="1.0"?>'
      '<root xmlns:w="$_wNS" xml:space="preserve">'
      '<w:p>$styleBlock'
      '<w:r><w:t xml:space="preserve">$escaped</w:t></w:r>'
      '</w:p>'
      '</root>',
    );

    // Detach the w:p element from the temporary document before returning
    return fragment.rootElement.childElements.first.copy();
  }

  static String _escapeXml(String text) => text
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
}
