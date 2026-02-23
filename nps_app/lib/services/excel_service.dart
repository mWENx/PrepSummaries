import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:xml/xml.dart';

class DonorData {
  final String donorName;
  final String primaryEmployer;
  final String donorJobTitle;
  final String donorAffiliation;
  final Map<String, String> replacements;

  const DonorData({
    required this.donorName,
    required this.primaryEmployer,
    required this.donorJobTitle,
    required this.donorAffiliation,
    required this.replacements,
  });
}

class ExcelService {
  /// Reads [filePath] and finds the row whose "Constituent: First and Last
  /// Name" column matches [targetName] (case-insensitive).  Collects all rows
  /// with the same Donor ID as the matching row to build the contacts block.
  static DonorData extractDonorData(
      String filePath, {required String targetName}) {
    var bytes = File(filePath).readAsBytesSync();
    bytes = _fixNumFmts(bytes); // fix malformed numFmtId values before parsing
    return _extract(bytes, targetName: targetName);
  }

  static DonorData _extract(Uint8List bytes, {required String targetName}) {
    final excel = Excel.decodeBytes(bytes);
    final sheetName = excel.tables.keys.first;
    final sheet = excel.tables[sheetName]!;

    if (sheet.rows.length < 2) {
      throw Exception('Excel file has no data rows.');
    }

    // Build header → column-index map
    final headers = <String, int>{};
    for (int i = 0; i < sheet.rows[0].length; i++) {
      final cell = sheet.rows[0][i];
      if (cell?.value != null) headers[_cellStr(cell)] = i;
    }

    // ── Find the target row by name ──────────────────────────────────────
    final nameColIdx = headers['Constituent: First and Last Name'];
    if (nameColIdx == null) {
      throw Exception(
          'Column "Constituent: First and Last Name" not found in the Excel file.');
    }

    final lowerTarget = targetName.trim().toLowerCase();
    int targetRowIdx = -1;

    // 1) exact match (case-insensitive)
    for (int i = 1; i < sheet.rows.length; i++) {
      final row = sheet.rows[i];
      final name = nameColIdx < row.length ? _cellStr(row[nameColIdx]) : '';
      if (name.toLowerCase() == lowerTarget) {
        targetRowIdx = i;
        break;
      }
    }

    // 2) substring fallback
    if (targetRowIdx == -1) {
      for (int i = 1; i < sheet.rows.length; i++) {
        final row = sheet.rows[i];
        final name = nameColIdx < row.length ? _cellStr(row[nameColIdx]) : '';
        if (name.toLowerCase().contains(lowerTarget) ||
            lowerTarget.contains(name.toLowerCase())) {
          targetRowIdx = i;
          break;
        }
      }
    }

    if (targetRowIdx == -1) {
      throw Exception(
          'No donor named "$targetName" found in the Excel file.\n'
          'Check the spelling or the "Constituent: First and Last Name" column.');
    }

    final first = sheet.rows[targetRowIdx];

    // ── Helper closures ──────────────────────────────────────────────────
    String getCol(List<Data?> row, String colName) {
      final idx = headers[colName];
      if (idx == null || idx >= row.length) return '';
      return _cellStr(row[idx]);
    }

    String getDateCol(List<Data?> row, String colName) {
      final idx = headers[colName];
      if (idx == null || idx >= row.length) return '';
      return _cellDate(row[idx]);
    }

    String getMoneyCol(List<Data?> row, String colName) {
      final idx = headers[colName];
      if (idx == null || idx >= row.length) return '';
      return _cellMoney(row[idx]);
    }

    // ── Collect contact rows (all rows with the same Donor ID) ───────────
    const donorIdCol = 'Constituent: Donor ID';
    const dateCol = 'Contact Report Date';
    const descCol = 'Contact Report: Description';
    const bodyCol = 'Contact Report: Contact Report Body';

    final donorId = getCol(first, donorIdCol);
    final contactRows = <List<Data?>>[];
    for (int i = 1; i < sheet.rows.length; i++) {
      final row = sheet.rows[i];
      if (donorId.isEmpty || getCol(row, donorIdCol) == donorId) {
        contactRows.add(row);
      }
    }

    // Sort by date descending
    final dateIdx = headers[dateCol];
    if (dateIdx != null) {
      contactRows.sort((a, b) {
        final da = _cellDateValue(dateIdx < a.length ? a[dateIdx] : null);
        final db = _cellDateValue(dateIdx < b.length ? b[dateIdx] : null);
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return db.compareTo(da);
      });
    }

    // Build contact entry strings
    final entries = <String>[];
    for (final row in contactRows) {
      final desc = getCol(row, descCol);
      final date = getDateCol(row, dateCol);
      final body = getCol(row, bodyCol);
      if (desc.isEmpty && body.isEmpty && date.isEmpty) continue;
      var line1 = '$desc on $date'.trim();
      if (line1 == 'on') line1 = '';
      final entry =
          body.isNotEmpty ? '$line1\n$body'.trim() : line1.trim();
      if (entry.isNotEmpty) entries.add(entry);
    }

    var firstDesc = '';
    var firstDate = '';
    var recentContacts = '';

    if (contactRows.isNotEmpty) {
      final mostRecent = contactRows.first;
      firstDesc = getCol(mostRecent, descCol);
      firstDate = getDateCol(mostRecent, dateCol);
      final mostRecentBody = getCol(mostRecent, bodyCol);
      final rest = entries.skip(1).toList();
      recentContacts = mostRecentBody;
      if (rest.isNotEmpty) {
        recentContacts =
            '$recentContacts\n\n${rest.join('\n\n')}'.trim();
      }
    }

    final donorName = getCol(first, 'Constituent: First and Last Name');
    final donorAffiliation =
        getCol(first, 'Constituent: Directory Suffix - NU School & Year');
    final primaryEmployer =
        getCol(first, 'Constituent: Primary Employer: Account Name');
    final donorJobTitle = getCol(first, 'Constituent: Job Title');

    final replacements = {
      '{{meeting_type}}': getCol(first, 'Contact Report: Contact Method'),
      '{{donor_name}}': donorName,
      '{{staff_name}}': getCol(
          first, 'Contact Report: Contact Report Author (User): Full Name'),
      '{{meeting_platform}}': 'Zoom Link',
      '{{meeting_date}}': getDateCol(first, 'Contact Report Date'),
      '{{donor_affiliation}}': donorAffiliation,
      '{{primary_employer}}': primaryEmployer,
      '{{donor_job_title}}': donorJobTitle,
      '{{lifetime_giving}}':
          getMoneyCol(first, 'Constituent: Lifetime Fundraising'),
      '{{recent_gift_amount}}':
          getMoneyCol(first, 'Constituent: Amount of Most Recent Gift'),
      '{{recent_gift_date}}':
          getDateCol(first, 'Constituent: Date of Most Recent Gift'),
      '{{contact_report_description}}': firstDesc,
      '{{contact_report_date}}': firstDate,
      '{{recent_contacts}}': recentContacts,
    };

    return DonorData(
      donorName: donorName,
      primaryEmployer: primaryEmployer,
      donorJobTitle: donorJobTitle,
      donorAffiliation: donorAffiliation,
      replacements: replacements,
    );
  }

  // ── numFmt preprocessing ─────────────────────────────────────────────────
  //
  // Some Excel files place <numFmt> entries with numFmtId < 164 inside the
  // custom numFmts block.  IDs 0-163 are reserved for built-in formats, so
  // the excel package asserts/throws when it encounters them there.
  //
  // Fix: remap every offending ID to a safe custom range (200+) and update
  // every <xf> element that references the old ID.  Deleting the entries
  // instead would leave dangling xf references and cause a different crash.

  static Uint8List _fixNumFmts(Uint8List bytes) {
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      ArchiveFile? stylesFile;
      for (final f in archive) {
        if (f.isFile && f.name == 'xl/styles.xml') {
          stylesFile = f;
          break;
        }
      }
      if (stylesFile == null) return bytes;

      final raw = stylesFile.content;
      final stylesBytes =
          raw is Uint8List ? raw : Uint8List.fromList(raw as List<int>);
      final stylesXml = utf8.decode(stylesBytes);

      final doc = XmlDocument.parse(stylesXml);

      // Build old-id → new-id remap for every numFmt with id < 164
      int nextId = 200;
      final remap = <String, String>{};
      for (final el in doc.findAllElements('numFmt').toList()) {
        final idStr = el.getAttribute('numFmtId') ?? '';
        final id = int.tryParse(idStr) ?? 164;
        if (id < 164) {
          final newIdStr = (nextId++).toString();
          remap[idStr] = newIdStr;
          el.setAttribute('numFmtId', newIdStr);
        }
      }

      if (remap.isEmpty) return bytes; // nothing to fix

      // Update every <xf> that still references the old IDs
      for (final xf in doc.findAllElements('xf').toList()) {
        final ref = xf.getAttribute('numFmtId') ?? '';
        if (remap.containsKey(ref)) {
          xf.setAttribute('numFmtId', remap[ref]!);
        }
      }

      final fixedBytes = utf8.encode(doc.toXmlString());
      final newArchive = Archive();
      for (final f in archive) {
        if (f.isFile && f.name == 'xl/styles.xml') {
          newArchive.addFile(
              ArchiveFile('xl/styles.xml', fixedBytes.length, fixedBytes));
        } else {
          newArchive.addFile(f);
        }
      }
      return Uint8List.fromList(ZipEncoder().encode(newArchive)!);
    } catch (_) {
      return bytes; // preprocessing failed — return original bytes
    }
  }

  // ── Cell value helpers ────────────────────────────────────────────────────

  static String _cellStr(Data? cell) {
    if (cell == null || cell.value == null) return '';
    final v = cell.value!;
    if (v is TextCellValue) return v.value.toString().trim();
    if (v is IntCellValue) return v.value.toString();
    if (v is DoubleCellValue) return v.value.toString();
    if (v is BoolCellValue) return v.value.toString();
    if (v is DateCellValue) return _fmtDate(v.year, v.month, v.day);
    if (v is DateTimeCellValue) return _fmtDate(v.year, v.month, v.day);
    return v.toString().trim();
  }

  static String _cellDate(Data? cell) {
    if (cell == null || cell.value == null) return '';
    final v = cell.value!;
    if (v is DateCellValue) return _fmtDate(v.year, v.month, v.day);
    if (v is DateTimeCellValue) return _fmtDate(v.year, v.month, v.day);
    final s = _cellStr(cell);
    if (s.isEmpty) return '';
    try {
      final dt = DateTime.parse(s);
      return _fmtDate(dt.year, dt.month, dt.day);
    } catch (_) {}
    return s;
  }

  static DateTime? _cellDateValue(Data? cell) {
    if (cell == null || cell.value == null) return null;
    final v = cell.value!;
    if (v is DateCellValue) return DateTime(v.year, v.month, v.day);
    if (v is DateTimeCellValue) {
      return DateTime(
          v.year, v.month, v.day, v.hour, v.minute, v.second);
    }
    return null;
  }

  static String _cellMoney(Data? cell) {
    if (cell == null || cell.value == null) return '';
    double? amount;
    final v = cell.value!;
    if (v is DoubleCellValue) amount = v.value;
    if (v is IntCellValue) amount = v.value.toDouble();
    if (amount == null) {
      final s = _cellStr(cell).replaceAll(r'$', '').replaceAll(',', '');
      amount = double.tryParse(s);
    }
    if (amount == null) return _cellStr(cell);
    return _fmtMoney(amount);
  }

  static String _fmtDate(int year, int month, int day) =>
      '${month.toString().padLeft(2, '0')}/'
      '${day.toString().padLeft(2, '0')}/$year';

  static String _fmtMoney(double amount) {
    final negative = amount < 0;
    final str = amount.abs().toStringAsFixed(2);
    final parts = str.split('.');
    final intPart = parts[0];
    final decPart = parts[1];
    final buf = StringBuffer();
    for (int i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buf.write(',');
      buf.write(intPart[i]);
    }
    return '${negative ? '-' : ''}\$${buf.toString()}.$decPart';
  }
}
