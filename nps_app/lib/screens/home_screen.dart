import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../services/prefs_service.dart';
import 'excel_viewer_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _excelPath;
  String? _lastSavedPath;
  String? _outputDir;
  final _nameController = TextEditingController();
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _loadLastPath();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadLastPath() async {
    final path = await PrefsService.getLastExcelPath();
    if (path != null && File(path).existsSync()) {
      setState(() => _lastSavedPath = path);
    }
  }

  Future<void> _pickExcelFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xlsx', 'xls'],
      dialogTitle: 'Select Excel File',
    );
    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      await PrefsService.saveLastExcelPath(path);
      setState(() {
        _excelPath = path;
        _lastSavedPath = path;
      });
    }
  }

  void _useLastFile() {
    setState(() => _excelPath = _lastSavedPath);
  }

  Future<void> _pickOutputDirectory() async {
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Output Folder',
    );
    if (dir != null) {
      setState(() => _outputDir = dir);
    }
  }

  void _viewExcel() {
    if (_excelPath == null) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ExcelViewerScreen(filePath: _excelPath!),
      ),
    );
  }

  Future<void> _generate() async {
    final name = _nameController.text.trim();
    if (_excelPath == null) {
      _showSnack('Please select an Excel file first.');
      return;
    }
    if (name.isEmpty) {
      _showSnack("Please enter the target's full name.");
      return;
    }
    if (_outputDir == null) {
      _showSnack('Please select an output folder.');
      return;
    }

    setState(() => _isGenerating = true);

    // TODO: Replace this block with your actual file generation logic.
    await Future.delayed(const Duration(seconds: 1));
    // Example placeholder output:
    final outputPath = p.join(_outputDir!, '$name - output.xlsx');
    // await generateFile(inputPath: _excelPath!, targetName: name, outputPath: outputPath);

    setState(() => _isGenerating = false);

    if (!mounted) return;
    _showSnack('File ready at: $outputPath', duration: 4);
  }

  void _showSnack(String msg, {int duration = 3}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: Duration(seconds: duration),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('NPS File Processor'),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              // ── Section 1: Excel File ──────────────────────────────
              _SectionCard(
                title: 'Input Excel File',
                icon: Icons.table_chart_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Active file display
                    if (_excelPath != null)
                      _FileChip(
                        path: _excelPath!,
                        onView: _viewExcel,
                        onClear: () => setState(() => _excelPath = null),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 16),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'No file selected',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _pickExcelFile,
                            icon: const Icon(Icons.upload_file),
                            label: const Text('Upload Excel'),
                          ),
                        ),
                        if (_lastSavedPath != null &&
                            _lastSavedPath != _excelPath) ...[
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _useLastFile,
                              icon: const Icon(Icons.history),
                              label: const Text('Use Last File'),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (_lastSavedPath != null && _lastSavedPath != _excelPath)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Last: ${p.basename(_lastSavedPath!)}',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: cs.outline),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Section 2: Target Name ─────────────────────────────
              _SectionCard(
                title: "Target's Full Name",
                icon: Icons.person_outline,
                child: TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    hintText: 'Enter full name',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                  textCapitalization: TextCapitalization.words,
                ),
              ),
              const SizedBox(height: 16),

              // ── Section 3: Output Directory ────────────────────────
              _SectionCard(
                title: 'Output Folder',
                icon: Icons.folder_open_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_outputDir != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 16),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: cs.primary.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.folder, color: cs.primary, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                _outputDir!,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: cs.onSurface),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () => setState(() => _outputDir = null),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 16),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'No folder selected',
                          style: TextStyle(color: cs.onSurfaceVariant),
                        ),
                      ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _pickOutputDirectory,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Browse Folder'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // ── Generate Button ────────────────────────────────────
              FilledButton.icon(
                onPressed: _isGenerating ? null : _generate,
                icon: _isGenerating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.play_arrow_rounded),
                label: Text(_isGenerating ? 'Generating...' : 'Generate File'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 16),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Helper widgets ──────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(title, style: theme.textTheme.titleMedium),
              ],
            ),
            const Divider(height: 20),
            child,
          ],
        ),
      ),
    );
  }
}

class _FileChip extends StatelessWidget {
  final String path;
  final VoidCallback onView;
  final VoidCallback onClear;

  const _FileChip({
    required this.path,
    required this.onView,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: cs.primary.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.description_outlined, color: cs.primary, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              p.basename(path),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: cs.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: onView,
            icon: const Icon(Icons.visibility_outlined, size: 16),
            label: const Text('View'),
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            onPressed: onClear,
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }
}
