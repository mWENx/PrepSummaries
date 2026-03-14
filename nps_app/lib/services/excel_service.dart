import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:excel/excel.dart';
import 'package:xml/xml.dart';

/// A single contact report entry extracted from the Excel data.
class ContactEntry {
  final String headline; // Contact Report: Description
  final String date; // Contact Report Date (formatted)
  final String body; // Contact Report: Contact Report Body
  final String author; // Contact Report Author
  final String purpose; // Contact Report: Purpose
  final String method; // Contact Report: Contact Method

  const ContactEntry({
    required this.headline,
    required this.date,
    required this.body,
    required this.author,
    required this.purpose,
    required this.method,
  });
}

class DonorData {
  final String donorName;
  final String donorFirstName;
  final String primaryEmployer;
  final String donorJobTitle;
  final String donorAffiliation;

  /// Mail-merge field name → replacement value.
  /// Keys match the MERGEFIELD names in the FY26 template.
  final Map<String, String> mergeFields;

  /// Structured contact report entries (newest first).
  final List<ContactEntry> contacts;

  const DonorData({
    required this.donorName,
    required this.donorFirstName,
    required this.primaryEmployer,
    required this.donorJobTitle,
    required this.donorAffiliation,
    required this.mergeFields,
    required this.contacts,
  });
}

class ExcelService {
  /// Reads [filePath] and finds the row whose "Constituent: First and Last
  /// Name" column matches [targetName] (case-insensitive).  Collects all rows
  /// with the same Donor ID as the matching row to build the contacts block.
  static DonorData extractDonorData(
      String filePath, {required String targetName}) {
    var bytes = File(filePath).readAsBytesSync();
    bytes = fixNumFmts(bytes);
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
    const authorCol =
        'Contact Report: Contact Report Author (User): Full Name';
    const purposeCol = 'Contact Report: Purpose';
    const methodCol = 'Contact Report: Contact Method';

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

    // Build structured contact entries
    final contacts = <ContactEntry>[];
    for (final row in contactRows) {
      final desc = getCol(row, descCol);
      final date = getDateCol(row, dateCol);
      final body = getCol(row, bodyCol);
      final author = getCol(row, authorCol);
      final purpose = getCol(row, purposeCol);
      final method = getCol(row, methodCol);
      if (desc.isEmpty && body.isEmpty && date.isEmpty) continue;
      contacts.add(ContactEntry(
        headline: desc.isNotEmpty ? '$desc — $date' : date,
        date: date,
        body: body,
        author: author,
        purpose: purpose,
        method: method,
      ));
    }

    // ── Extract donor metadata ───────────────────────────────────────────
    final donorName = getCol(first, 'Constituent: First and Last Name');
    final donorFirstName = getCol(first, 'Constituent: First Name (No Trustee)');
    final donorAffiliation =
        getCol(first, 'Constituent: Directory Suffix - NU School & Year');
    final primaryEmployer =
        getCol(first, 'Constituent: Primary Employer: Account Name');
    final donorJobTitle = getCol(first, 'Constituent: Job Title');

    // ── Build merge field map ────────────────────────────────────────────
    // Keys match the MERGEFIELD names in FY26_New_Briefing_Template_MailMerge.docx
    final mergeFields = <String, String>{
      'Donor_Name': donorName,
      'All_Degrees': donorAffiliation,
      'Primary_Employer_Name': primaryEmployer,
      'Primary_Employment_Job_Title': donorJobTitle,
      'Preferred_City':
          getCol(first, 'Constituent: Preferred Address City'),
      'Preferred_State':
          getCol(first, 'Constituent: Preferred Address State'),
      'Primary_Relationship_Manager_Name':
          getCol(first, 'Contact Report: Contact Report Author (User): Full Name'),
      'University_Overall_Rating':
          getCol(first, 'University Overall Rating'),
      'Lifetime_New_Gifts__Comm_Credit':
          getMoneyCol(first, 'Lifetime New Gifts & Comm. Credit'),
      'McCormick_Lifetime_New_Gifts__Comm_Cre':
          getMoneyCol(first, 'McCormick Lifetime New Gifts & Comm. Credit'),
      'McCormick_Last_Gift_or_Pledge_Amount':
          getMoneyCol(first, 'McCormick Last Gift or Pledge Amount'),
      'McCormick_Last_Gift_or_Pledge_Informatio':
          _formatGiftInfo(
            getCol(first, 'McCormick Last Gift or Pledge Information'),
          ),
      'McCormick_Last_Gift_or_Pledge_Date':
          getDateCol(first, 'McCormick Last Gift or Pledge Date'),
    };

    return DonorData(
      donorName: donorName,
      donorFirstName: donorFirstName,
      primaryEmployer: primaryEmployer,
      donorJobTitle: donorJobTitle,
      donorAffiliation: donorAffiliation,
      mergeFields: mergeFields,
      contacts: contacts,
    );
  }

  // ── numFmt preprocessing ─────────────────────────────────────────────────
  //
  // Some Excel files place <numFmt> entries with numFmtId < 164 inside the
  // custom numFmts block.  IDs 0-163 are reserved for built-in formats, so
  // the excel package asserts/throws when it encounters them there.
  //
  // Fix: remap every offending ID to a safe custom range (200+) and update
  // every <xf> element that references the old ID.

  /// Fixes Excel files with numFmtId < 164 in the custom numFmts block.
  /// Public so the Excel viewer can also use it.
  static Uint8List fixNumFmts(Uint8List bytes) {
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

      if (remap.isEmpty) return bytes;

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
      return bytes;
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

  /// Reformats the raw gift info string from
  /// "GN3051336 - Funded - Outright Gift - McCormick School Dean's Fund - McCmick Schl of Engg & App Sci"
  /// into "for Outright Gift to McCormick School Dean's Fund".
  /// The dollar amount is in a separate merge field, so it's excluded here.
  static String _formatGiftInfo(String rawInfo) {
    if (rawInfo.isEmpty) return '';
    // Split on " - " to get: [Gift ID, Status, Gift Type, Fund Name, School/Unit]
    final parts = rawInfo.split(' - ');
    if (parts.length >= 4) {
      final giftType = parts[2].trim(); // e.g. "Outright Gift"
      final fundName = parts[3].trim(); // e.g. "McCormick School Dean's Fund"
      return 'for $giftType to $fundName';
    }
    // Fallback: return raw if we can't parse
    return rawInfo;
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
