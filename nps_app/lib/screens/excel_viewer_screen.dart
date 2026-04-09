import 'dart:io';
import 'package:excel/excel.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../services/excel_service.dart';

class ExcelViewerScreen extends StatefulWidget {
  final String filePath;

  const ExcelViewerScreen({super.key, required this.filePath});

  @override
  State<ExcelViewerScreen> createState() => _ExcelViewerScreenState();
}

class _ExcelViewerScreenState extends State<ExcelViewerScreen>
    with SingleTickerProviderStateMixin {
  late Excel _excel;
  late TabController _tabController;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadExcel();
  }

  Future<void> _loadExcel() async {
    try {
      final bytes = ExcelService.fixNumFmts(
          await File(widget.filePath).readAsBytes());
      final excel = Excel.decodeBytes(bytes);
      setState(() {
        _excel = excel;
        _tabController = TabController(
          length: excel.sheets.length,
          vsync: this,
        );
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to read Excel file: $e';
        _loading = false;
      });
    }
  }

  @override
  void dispose() {
    if (!_loading && _error == null) _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          p.basename(widget.filePath),
          overflow: TextOverflow.ellipsis,
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        bottom: (!_loading && _error == null && _excel.sheets.isNotEmpty)
            ? TabBar(
                controller: _tabController,
                isScrollable: true,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                indicatorColor: Colors.white,
                tabs: _excel.sheets.keys
                    .map((name) => Tab(text: name))
                    .toList(),
              )
            : null,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(_error!, style: const TextStyle(color: Colors.red)),
        ),
      );
    }
    if (_excel.sheets.isEmpty) {
      return const Center(child: Text('No sheets found in this file.'));
    }
    return TabBarView(
      controller: _tabController,
      children: _excel.sheets.entries.map((entry) {
        return _SheetView(sheet: entry.value);
      }).toList(),
    );
  }
}

class _SheetView extends StatelessWidget {
  final Sheet sheet;

  const _SheetView({required this.sheet});

  @override
  Widget build(BuildContext context) {
    final rows = sheet.rows;
    if (rows.isEmpty) {
      return const Center(child: Text('This sheet is empty.'));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(
            Theme.of(context).colorScheme.primaryContainer,
          ),
          border: TableBorder.all(
            color: Theme.of(context).dividerColor,
            width: 0.5,
          ),
          columns: List.generate(
            rows.first.length,
            (i) => DataColumn(
              label: Text(
                _cellValue(rows.first[i]),
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          rows: rows.skip(1).map((row) {
            return DataRow(
              cells: row.map((cell) {
                return DataCell(Text(_cellValue(cell)));
              }).toList(),
            );
          }).toList(),
        ),
      ),
    );
  }

  String _cellValue(Data? cell) {
    if (cell == null || cell.value == null) return '';
    return cell.value.toString();
  }
}
