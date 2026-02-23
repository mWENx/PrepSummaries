import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../services/prefs_service.dart';
import '../services/generator_service.dart';
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
  final _apiKeyController = TextEditingController();

  bool _isGenerating = false;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    _apiKeyController.addListener(() => setState(() {})); // keeps badge in sync
    _loadPrefs();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _apiKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final path = await PrefsService.getLastExcelPath();
    final key = await PrefsService.getApiKey();
    if (!mounted) return;
    setState(() {
      if (path != null && File(path).existsSync()) _lastSavedPath = path;
      if (key != null) _apiKeyController.text = key;
    });
  }

  // ── File pickers ──────────────────────────────────────────────────────────

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

  /// Tries to use the saved path, but detects sandbox permission loss and
  /// prompts the user to re-pick if we can no longer access the file.
  Future<void> _useLastFile() async {
    if (_lastSavedPath == null) return;
    try {
      // Quick open-and-close to verify we still have read permission
      File(_lastSavedPath!).openSync().closeSync();
      setState(() => _excelPath = _lastSavedPath);
    } on FileSystemException {
      _showSnack(
        'Cannot access the previous file — macOS sandbox requires re-selecting it.',
        duration: 5,
      );
      await PrefsService.clearLastExcelPath();
      setState(() => _lastSavedPath = null);
    }
  }

  Future<void> _pickOutputDirectory() async {
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Output Folder',
    );
    if (dir != null) setState(() => _outputDir = dir);
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

  // ── API key dialog ────────────────────────────────────────────────────────

  void _showApiKeyDialog() {
    bool obscured = true;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.vpn_key_outlined,
                  color: Theme.of(ctx).colorScheme.primary),
              const SizedBox(width: 8),
              const Text('OpenAI API Key'),
            ],
          ),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _apiKeyController,
                  obscureText: obscured,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'sk-…',
                    suffixIcon: IconButton(
                      icon: Icon(obscured
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined),
                      onPressed: () =>
                          setDialogState(() => obscured = !obscured),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Icons.lock_outline,
                        size: 14,
                        color: Theme.of(ctx).colorScheme.outline),
                    const SizedBox(width: 4),
                    Text(
                      'Stored locally on this device only.',
                      style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                            color: Theme.of(ctx).colorScheme.outline,
                          ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                await PrefsService.saveApiKey(
                    _apiKeyController.text.trim());
                if (ctx.mounted) Navigator.of(ctx).pop();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Generate ──────────────────────────────────────────────────────────────

  Future<void> _generate() async {
    final name = _nameController.text.trim();
    final apiKey = _apiKeyController.text.trim();

    if (_excelPath == null) {
      _showSnack('Please select an Excel file first.');
      return;
    }
    if (name.isEmpty) {
      _showSnack("Please enter the donor's full name.");
      return;
    }
    if (_outputDir == null) {
      _showSnack('Please select an output folder.');
      return;
    }
    if (apiKey.isEmpty) {
      _showSnack(
          'Please add your OpenAI API key (tap the key icon in the top bar).');
      return;
    }

    setState(() {
      _isGenerating = true;
      _statusMessage = 'Starting…';
    });

    String? outputPath;
    try {
      await for (final status in GeneratorService.generate(
        excelPath: _excelPath!,
        outputDir: _outputDir!,
        openAiApiKey: apiKey,
        targetName: name,
      )) {
        if (!mounted) return;
        outputPath = status;
        setState(() => _statusMessage = status);
      }
      if (!mounted) return;
      _showSnack(
        'Saved: ${outputPath != null ? p.basename(outputPath) : 'briefing document'}',
        duration: 6,
      );
    } on FileSystemException {
      if (!mounted) return;
      _showSnack(
        'Cannot read the Excel file — macOS sandbox requires re-selecting it.',
        duration: 6,
      );
      setState(() {
        _excelPath = null;
        _lastSavedPath = null;
      });
      await PrefsService.clearLastExcelPath();
    } catch (e) {
      if (!mounted) return;
      _showSnack('Error: $e', duration: 8);
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  void _showSnack(String msg, {int duration = 3}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        duration: Duration(seconds: duration),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final keyIsSet = _apiKeyController.text.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('NPS Briefing Generator'),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Tooltip(
              message: keyIsSet ? 'API key is set' : 'Set OpenAI API key',
              child: IconButton(
                onPressed: _showApiKeyDialog,
                icon: Badge(
                  isLabelVisible: keyIsSet,
                  backgroundColor: Colors.greenAccent.shade400,
                  smallSize: 8,
                  child: const Icon(Icons.vpn_key_outlined),
                ),
              ),
            ),
          ),
        ],
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
                    if (_excelPath != null)
                      _FileChip(
                        path: _excelPath!,
                        onView: _viewExcel,
                        onClear: () => setState(() => _excelPath = null),
                      )
                    else
                      _emptyBox(cs, 'No file selected'),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _isGenerating ? null : _pickExcelFile,
                            icon: const Icon(Icons.upload_file),
                            label: const Text('Upload Excel'),
                          ),
                        ),
                        if (_lastSavedPath != null &&
                            _lastSavedPath != _excelPath) ...[
                          const SizedBox(width: 10),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed:
                                  _isGenerating ? null : _useLastFile,
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

              // ── Section 2: Donor Name ──────────────────────────────
              _SectionCard(
                title: "Donor's Full Name",
                icon: Icons.person_outline,
                child: TextField(
                  controller: _nameController,
                  enabled: !_isGenerating,
                  decoration: const InputDecoration(
                    hintText: 'e.g. Jane Smith',
                    prefixIcon: Icon(Icons.badge_outlined),
                    helperText:
                        'Must match the name in the Excel file exactly (or close enough).',
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
                          border: Border.all(
                              color: cs.primary.withValues(alpha: 0.3)),
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
                              onPressed: _isGenerating
                                  ? null
                                  : () => setState(() => _outputDir = null),
                              visualDensity: VisualDensity.compact,
                            ),
                          ],
                        ),
                      )
                    else
                      _emptyBox(cs, 'No folder selected'),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed:
                          _isGenerating ? null : _pickOutputDirectory,
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
                label: Text(
                    _isGenerating ? 'Generating…' : 'Generate Briefing'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  textStyle: const TextStyle(fontSize: 16),
                ),
              ),

              // ── Status ────────────────────────────────────────────
              if (_isGenerating && _statusMessage.isNotEmpty) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.symmetric(
                      vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _statusMessage,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _emptyBox(ColorScheme cs, String label) => Container(
        padding:
            const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label, style: TextStyle(color: cs.onSurfaceVariant)),
      );
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
