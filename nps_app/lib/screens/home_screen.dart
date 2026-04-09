import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../services/llm_provider.dart';
import '../services/prefs_service.dart';
import '../services/generator_service.dart';
import 'excel_viewer_screen.dart';
import 'event_briefing_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _excelPath;
  String? _lastSavedExcelPath;
  String? _linkedInPath;
  String? _lastSavedLinkedInPath;
  String? _outputDir;
  final _nameController = TextEditingController();
  final _additionalNotesController = TextEditingController();

  // ── Remembered picker directories ──────────────────────────────────────
  String? _lastExcelDir;
  String? _lastLinkedInDir;
  String? _lastOutputDir;

  // ── LLM provider state ──────────────────────────────────────────────────
  LlmProvider _selectedProvider = LlmProvider.openai;
  final Map<LlmProvider, String> _selectedModels = {
    for (final p in LlmProvider.values) p: p.defaultModel,
  };

  final _apiKeyControllers = {
    for (final p in LlmProvider.values) p: TextEditingController(),
  };

  bool _isGenerating = false;
  String _statusMessage = '';

  TextEditingController get _activeKeyController =>
      _apiKeyControllers[_selectedProvider]!;

  @override
  void initState() {
    super.initState();
    for (final c in _apiKeyControllers.values) {
      c.addListener(() => setState(() {}));
    }
    _loadPrefs();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _additionalNotesController.dispose();
    for (final c in _apiKeyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final excelPath = await PrefsService.getLastExcelPath();
    final linkedInPath = await PrefsService.getLastLinkedInPath();
    final provider = await PrefsService.getSelectedProvider();

    final excelDir = await PrefsService.getLastDir(PrefsService.keyExcelDir);
    final linkedInDir =
        await PrefsService.getLastDir(PrefsService.keyLinkedInDir);
    final outputDir = await PrefsService.getLastDir(PrefsService.keyOutputDir);

    for (final p in LlmProvider.values) {
      final key = await PrefsService.getApiKey(p);
      if (key != null) _apiKeyControllers[p]!.text = key;
      final savedModel = await PrefsService.getSelectedModel(p);
      if (savedModel != null &&
          p.models.any((m) => m.id == savedModel)) {
        _selectedModels[p] = savedModel;
      }
    }

    if (!mounted) return;
    setState(() {
      if (excelPath != null && File(excelPath).existsSync()) {
        _lastSavedExcelPath = excelPath;
      }
      if (linkedInPath != null && File(linkedInPath).existsSync()) {
        _lastSavedLinkedInPath = linkedInPath;
      }
      _lastExcelDir = excelDir;
      _lastLinkedInDir = linkedInDir;
      _lastOutputDir = outputDir;
      _selectedProvider = provider;
    });
  }

  // ── File pickers ──────────────────────────────────────────────────────────

  Future<void> _pickExcelFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      dialogTitle: 'Select Excel File',
      initialDirectory: _lastExcelDir,
    );
    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      final ext = p.extension(path).toLowerCase();
      if (ext != '.xlsx' && ext != '.xls') {
        _showSnack('Please select an Excel file (.xlsx or .xls).');
        return;
      }
      final dir = p.dirname(path);
      await PrefsService.saveLastExcelPath(path);
      await PrefsService.saveLastDir(PrefsService.keyExcelDir, dir);
      setState(() {
        _excelPath = path;
        _lastSavedExcelPath = path;
        _lastExcelDir = dir;
      });
    }
  }

  Future<void> _useLastExcelFile() async {
    if (_lastSavedExcelPath == null) return;
    try {
      File(_lastSavedExcelPath!).openSync().closeSync();
      setState(() => _excelPath = _lastSavedExcelPath);
    } on FileSystemException {
      _showSnack(
        'Cannot access the previous file — macOS sandbox requires re-selecting it.',
        duration: 5,
      );
      await PrefsService.clearLastExcelPath();
      setState(() => _lastSavedExcelPath = null);
    }
  }

  Future<void> _pickLinkedInFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      dialogTitle: 'Select LinkedIn Profile PDF',
      initialDirectory: _lastLinkedInDir,
    );
    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      final ext = p.extension(path).toLowerCase();
      if (ext != '.pdf') {
        _showSnack('Please select a PDF file.');
        return;
      }
      final dir = p.dirname(path);
      await PrefsService.saveLastLinkedInPath(path);
      await PrefsService.saveLastDir(PrefsService.keyLinkedInDir, dir);
      setState(() {
        _linkedInPath = path;
        _lastSavedLinkedInPath = path;
        _lastLinkedInDir = dir;
      });
    }
  }

  Future<void> _useLastLinkedInFile() async {
    if (_lastSavedLinkedInPath == null) return;
    try {
      File(_lastSavedLinkedInPath!).openSync().closeSync();
      setState(() => _linkedInPath = _lastSavedLinkedInPath);
    } on FileSystemException {
      _showSnack(
        'Cannot access the previous file — macOS sandbox requires re-selecting it.',
        duration: 5,
      );
      await PrefsService.clearLastLinkedInPath();
      setState(() => _lastSavedLinkedInPath = null);
    }
  }

  Future<void> _pickOutputDirectory() async {
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Output Folder',
      initialDirectory: _lastOutputDir,
    );
    if (dir != null) {
      await PrefsService.saveLastDir(PrefsService.keyOutputDir, dir);
      setState(() {
        _outputDir = dir;
        _lastOutputDir = dir;
      });
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

  // ── AI provider menu ───────────────────────────────────────────────────────

  void _showProviderMenu() {
    final cs = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final activeKey = _apiKeyControllers[_selectedProvider]!;
          final currentKeyIsSet = activeKey.text.isNotEmpty;

          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.smart_toy_outlined, color: cs.primary),
                const SizedBox(width: 8),
                const Text('AI Provider & API Key'),
              ],
            ),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<LlmProvider>(
                    segments: [
                      for (final provider in LlmProvider.values)
                        ButtonSegment(
                          value: provider,
                          label: Text(provider.displayName),
                        ),
                    ],
                    selected: {_selectedProvider},
                    onSelectionChanged: _isGenerating
                        ? null
                        : (sel) {
                            _switchProvider(sel.first);
                            setDialogState(() {});
                          },
                    showSelectedIcon: false,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedModels[_selectedProvider],
                    decoration: const InputDecoration(
                      labelText: 'Model',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: _selectedProvider.models
                        .map((m) => DropdownMenuItem(
                              value: m.id,
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(m.displayName),
                                  Text(
                                    m.costLabel,
                                    style: Theme.of(ctx)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: cs.onSurfaceVariant,
                                        ),
                                  ),
                                ],
                              ),
                            ))
                        .toList(),
                    onChanged: _isGenerating
                        ? null
                        : (val) {
                            if (val != null) {
                              setState(() =>
                                  _selectedModels[_selectedProvider] = val);
                              setDialogState(() {});
                              PrefsService.saveSelectedModel(
                                  _selectedProvider, val);
                            }
                          },
                  ),
                  const SizedBox(height: 16),
                  _ApiKeyField(
                    provider: _selectedProvider,
                    controller: _apiKeyControllers[_selectedProvider]!,
                    onSaved: () => setDialogState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        currentKeyIsSet
                            ? Icons.check_circle
                            : Icons.warning_amber_rounded,
                        size: 16,
                        color: currentKeyIsSet ? Colors.green : cs.error,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        currentKeyIsSet
                            ? '${_selectedProvider.displayName} API key is configured'
                            : 'API key required',
                        style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                              color: currentKeyIsSet
                                  ? cs.onSurfaceVariant
                                  : cs.error,
                            ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Done'),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Provider switching ──────────────────────────────────────────────────

  Future<void> _switchProvider(LlmProvider provider) async {
    setState(() => _selectedProvider = provider);
    await PrefsService.saveSelectedProvider(provider);
  }

  // ── Generate ──────────────────────────────────────────────────────────────

  Future<void> _generate() async {
    final name = _nameController.text.trim();
    final apiKey = _activeKeyController.text.trim();

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
          'Please add your ${_selectedProvider.displayName} API key (tap the provider button in the top bar).');
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
        apiKey: apiKey,
        targetName: name,
        provider: _selectedProvider,
        linkedInPdfPath: _linkedInPath,
        model: _selectedModels[_selectedProvider],
        additionalNotes: _additionalNotesController.text.trim().isEmpty
            ? null
            : _additionalNotesController.text.trim(),
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
        _lastSavedExcelPath = null;
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
    final hasKey = _activeKeyController.text.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('NPS Briefing Generator'),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        actions: [
          // ── Event Briefing button ──────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: ActionChip(
              avatar: Icon(Icons.event_note_outlined,
                  size: 18, color: cs.onPrimary),
              label: Text('Event Briefing',
                  style: TextStyle(color: cs.onPrimary, fontSize: 13)),
              backgroundColor: cs.primary,
              side: BorderSide(color: cs.onPrimary.withValues(alpha: 0.4)),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const EventBriefingScreen()),
              ),
            ),
          ),
          // ── Provider + API key button ──────────────────────────────
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ActionChip(
              avatar: Badge(
                isLabelVisible: hasKey,
                backgroundColor: Colors.greenAccent.shade400,
                smallSize: 8,
                child: Icon(Icons.smart_toy_outlined,
                    size: 18, color: cs.onPrimary),
              ),
              label: Text(
                _selectedProvider.displayName,
                style: TextStyle(color: cs.onPrimary, fontSize: 13),
              ),
              backgroundColor: cs.primary,
              side: BorderSide(color: cs.onPrimary.withValues(alpha: 0.4)),
              onPressed: _showProviderMenu,
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 700),
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              // ── Section 1: Input Files (Excel + LinkedIn side by side) ──
              _SectionCard(
                title: 'Input Files',
                icon: Icons.source_outlined,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Excel column ──
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Donor Data (Excel)',
                              style: theme.textTheme.labelLarge),
                          const SizedBox(height: 8),
                          if (_excelPath != null)
                            _FileChip(
                              path: _excelPath!,
                              icon: Icons.table_chart_outlined,
                              onAction: _viewExcel,
                              actionLabel: 'View',
                              actionIcon: Icons.visibility_outlined,
                              onClear: () =>
                                  setState(() => _excelPath = null),
                            )
                          else
                            _emptyBox(cs, 'No file selected'),
                          const SizedBox(height: 8),
                          FilledButton.icon(
                            onPressed:
                                _isGenerating ? null : _pickExcelFile,
                            icon: const Icon(Icons.upload_file, size: 18),
                            label: const Text('Upload Excel'),
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                          if (_lastSavedExcelPath != null &&
                              _lastSavedExcelPath != _excelPath) ...[
                            const SizedBox(height: 6),
                            OutlinedButton.icon(
                              onPressed: _isGenerating
                                  ? null
                                  : _useLastExcelFile,
                              icon: const Icon(Icons.history, size: 16),
                              label: Text(
                                  'Last: ${p.basename(_lastSavedExcelPath!)}',
                                  overflow: TextOverflow.ellipsis),
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                textStyle: const TextStyle(inherit: false, fontSize: 12),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // ── LinkedIn column ──
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('LinkedIn PDF (optional)',
                              style: theme.textTheme.labelLarge),
                          const SizedBox(height: 8),
                          if (_linkedInPath != null)
                            _FileChip(
                              path: _linkedInPath!,
                              icon: Icons.picture_as_pdf_outlined,
                              onClear: () =>
                                  setState(() => _linkedInPath = null),
                            )
                          else
                            _emptyBox(cs, 'No PDF uploaded'),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed:
                                _isGenerating ? null : _pickLinkedInFile,
                            icon: const Icon(Icons.upload_file, size: 18),
                            label: const Text('Upload PDF'),
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                          if (_lastSavedLinkedInPath != null &&
                              _lastSavedLinkedInPath !=
                                  _linkedInPath) ...[
                            const SizedBox(height: 6),
                            OutlinedButton.icon(
                              onPressed: _isGenerating
                                  ? null
                                  : _useLastLinkedInFile,
                              icon: const Icon(Icons.history, size: 16),
                              label: Text(
                                  'Last: ${p.basename(_lastSavedLinkedInPath!)}',
                                  overflow: TextOverflow.ellipsis),
                              style: OutlinedButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                textStyle: const TextStyle(inherit: false, fontSize: 12),
                              ),
                            ),
                          ],
                          const SizedBox(height: 6),
                          Text(
                            'Save their LinkedIn profile as PDF from your browser.',
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: cs.outline),
                          ),
                        ],
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
                          color:
                              cs.primaryContainer.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: cs.primary.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.folder,
                                color: cs.primary, size: 20),
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
                                  : () =>
                                      setState(() => _outputDir = null),
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
              const SizedBox(height: 16),

              // ── Section 4: Additional Notes ────────────────────────
              _SectionCard(
                title: 'Additional Notes (optional)',
                icon: Icons.note_add_outlined,
                child: TextField(
                  controller: _additionalNotesController,
                  enabled: !_isGenerating,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    hintText:
                        'Enter any additional notes to include at the end of the briefing document…',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
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
                        child:
                            CircularProgressIndicator(strokeWidth: 2),
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

class _ApiKeyField extends StatefulWidget {
  final LlmProvider provider;
  final TextEditingController controller;
  final VoidCallback onSaved;

  const _ApiKeyField({
    required this.provider,
    required this.controller,
    required this.onSaved,
  });

  @override
  State<_ApiKeyField> createState() => _ApiKeyFieldState();
}

class _ApiKeyFieldState extends State<_ApiKeyField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: _obscured,
      decoration: InputDecoration(
        hintText: widget.provider.keyHint,
        labelText: '${widget.provider.displayName} API Key',
        prefixIcon: const Icon(Icons.vpn_key_outlined, size: 20),
        suffixIcon: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(_obscured
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined),
              onPressed: () => setState(() => _obscured = !_obscured),
            ),
            IconButton(
              icon: const Icon(Icons.save_outlined),
              tooltip: 'Save key',
              onPressed: () async {
                await PrefsService.saveApiKey(
                    widget.provider, widget.controller.text.trim());
                widget.onSaved();
              },
            ),
          ],
        ),
        helperText: 'Stored locally on this device only.',
        isDense: true,
      ),
    );
  }
}

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
  final IconData icon;
  final VoidCallback? onAction;
  final String? actionLabel;
  final IconData? actionIcon;
  final VoidCallback onClear;

  const _FileChip({
    required this.path,
    this.icon = Icons.description_outlined,
    this.onAction,
    this.actionLabel,
    this.actionIcon,
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
          Icon(icon, color: cs.primary, size: 20),
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
          if (onAction != null && actionLabel != null)
            TextButton.icon(
              onPressed: onAction,
              icon: Icon(actionIcon ?? Icons.open_in_new, size: 16),
              label: Text(actionLabel!),
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
