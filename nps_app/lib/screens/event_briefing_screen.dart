import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../services/excel_service.dart';
import '../services/event_generator_service.dart';
import '../services/llm_provider.dart';
import '../services/prefs_service.dart';

class EventBriefingScreen extends StatefulWidget {
  const EventBriefingScreen({super.key});

  @override
  State<EventBriefingScreen> createState() => _EventBriefingScreenState();
}

class _EventBriefingScreenState extends State<EventBriefingScreen> {
  String? _excelPath;
  String? _outputDir;
  List<String> _allDonors = [];
  final List<String> _selectedDonors = [];
  bool _loadingDonors = false;

  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  LlmProvider _selectedProvider = LlmProvider.openai;
  final Map<LlmProvider, String> _selectedModels = {
    for (final pv in LlmProvider.values) pv: pv.defaultModel,
  };
  final _apiKeyControllers = {
    for (final pv in LlmProvider.values) pv: TextEditingController(),
  };

  bool _isGenerating = false;
  String _statusMessage = '';

  TextEditingController get _activeKeyController =>
      _apiKeyControllers[_selectedProvider]!;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    for (final c in _apiKeyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadPrefs() async {
    final provider = await PrefsService.getSelectedProvider();
    final excelPath = await PrefsService.getLastExcelPath();
    for (final pv in LlmProvider.values) {
      final key = await PrefsService.getApiKey(pv);
      if (key != null) _apiKeyControllers[pv]!.text = key;
      final savedModel = await PrefsService.getSelectedModel(pv);
      if (savedModel != null && pv.models.any((m) => m.id == savedModel)) {
        _selectedModels[pv] = savedModel;
      }
    }
    if (!mounted) return;
    setState(() {
      _selectedProvider = provider;
      if (excelPath != null && File(excelPath).existsSync()) {
        _excelPath = excelPath;
        _loadDonors(excelPath);
      }
    });
  }

  Future<void> _pickExcelFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      dialogTitle: 'Select Donor Data Excel File',
    );
    if (result == null || result.files.single.path == null) return;
    final path = result.files.single.path!;
    final ext = p.extension(path).toLowerCase();
    if (ext != '.xlsx' && ext != '.xls') {
      _showSnack('Please select an Excel file (.xlsx or .xls).');
      return;
    }
    await PrefsService.saveLastExcelPath(path);
    setState(() {
      _excelPath = path;
      _allDonors = [];
      _selectedDonors.clear();
    });
    _loadDonors(path);
  }

  void _loadDonors(String path) {
    setState(() => _loadingDonors = true);
    Future(() {
      try {
        return ExcelService.getAllDonorNames(path);
      } catch (_) {
        return <String>[];
      }
    }).then((names) {
      if (!mounted) return;
      setState(() {
        _allDonors = names;
        _loadingDonors = false;
      });
    });
  }

  Future<void> _pickOutputDirectory() async {
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Select Output Folder',
    );
    if (dir != null) {
      await PrefsService.saveLastDir(PrefsService.keyOutputDir, dir);
      setState(() => _outputDir = dir);
    }
  }

  void _addDonor(String name) {
    if (name.isEmpty) return;
    if (_selectedDonors.contains(name)) return;
    setState(() {
      _selectedDonors.add(name);
      _searchController.clear();
    });
    _searchFocusNode.requestFocus();
  }

  void _removeDonor(String name) {
    setState(() => _selectedDonors.remove(name));
  }

  Future<void> _generate() async {
    if (_excelPath == null) {
      _showSnack('Please select an Excel file first.');
      return;
    }
    if (_selectedDonors.isEmpty) {
      _showSnack('Please add at least one donor.');
      return;
    }
    if (_outputDir == null) {
      _showSnack('Please select an output folder.');
      return;
    }
    final apiKey = _activeKeyController.text.trim();
    if (apiKey.isEmpty) {
      _showSnack(
          'Please enter your ${_selectedProvider.displayName} API key.');
      return;
    }

    setState(() {
      _isGenerating = true;
      _statusMessage = 'Starting…';
    });

    String? outputPath;
    try {
      await for (final status in EventGeneratorService.generate(
        excelPath: _excelPath!,
        outputDir: _outputDir!,
        selectedDonors: List.from(_selectedDonors),
        apiKey: apiKey,
        provider: _selectedProvider,
        model: _selectedModels[_selectedProvider],
      )) {
        if (!mounted) return;
        outputPath = status;
        setState(() => _statusMessage = status);
      }
      if (!mounted) return;
      _showSnack(
        'Saved: ${outputPath != null ? p.basename(outputPath) : 'event briefing'}',
        duration: 6,
      );
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
          content: Text(msg), duration: Duration(seconds: duration)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasKey = _activeKeyController.text.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Event Briefing Generator'),
        backgroundColor: cs.primary,
        foregroundColor: cs.onPrimary,
        actions: [
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
              // ── Excel File ────────────────────────────────────────
              _SectionCard(
                title: 'Donor Data (Excel)',
                icon: Icons.source_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_excelPath != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 10, horizontal: 14),
                        decoration: BoxDecoration(
                          color: cs.primaryContainer.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: cs.primary.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.table_chart_outlined,
                                color: cs.primary, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                p.basename(_excelPath!),
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: cs.onSurface,
                                    fontWeight: FontWeight.w500),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: _isGenerating
                                  ? null
                                  : () => setState(() {
                                        _excelPath = null;
                                        _allDonors = [];
                                        _selectedDonors.clear();
                                      }),
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
                        child: Text('No file selected',
                            style: TextStyle(color: cs.onSurfaceVariant)),
                      ),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _isGenerating ? null : _pickExcelFile,
                      icon: const Icon(Icons.upload_file, size: 18),
                      label: const Text('Upload Excel'),
                      style: FilledButton.styleFrom(
                          visualDensity: VisualDensity.compact),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Donor Selection ───────────────────────────────────
              _SectionCard(
                title: 'Select Donors',
                icon: Icons.group_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Autocomplete search field
                    _DonorAutocomplete(
                      allDonors: _allDonors,
                      selectedDonors: _selectedDonors,
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      enabled: !_isGenerating,
                      loading: _loadingDonors,
                      onSelected: _addDonor,
                    ),

                    // Selected donors as chips
                    if (_selectedDonors.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _selectedDonors
                            .map((name) => Chip(
                                  label: Text(name,
                                      style: theme.textTheme.bodySmall),
                                  deleteIcon:
                                      const Icon(Icons.close, size: 16),
                                  onDeleted: _isGenerating
                                      ? null
                                      : () => _removeDonor(name),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ))
                            .toList(),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_selectedDonors.length} donor${_selectedDonors.length == 1 ? '' : 's'} selected',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Output Folder ─────────────────────────────────────
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
                      Container(
                        padding: const EdgeInsets.symmetric(
                            vertical: 12, horizontal: 16),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('No folder selected',
                            style:
                                TextStyle(color: cs.onSurfaceVariant)),
                      ),
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

              // ── Generate Button ───────────────────────────────────
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
                label: Text(_isGenerating
                    ? 'Generating…'
                    : 'Generate Event Briefing'),
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
                            setState(() => _selectedProvider = sel.first);
                            setDialogState(() {});
                          },
                    showSelectedIcon: false,
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
                            ? '${_selectedProvider.displayName} key configured'
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
}

// ── Autocomplete donor search ───────────────────────────────────────────────

class _DonorAutocomplete extends StatelessWidget {
  final List<String> allDonors;
  final List<String> selectedDonors;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool enabled;
  final bool loading;
  final ValueChanged<String> onSelected;

  const _DonorAutocomplete({
    required this.allDonors,
    required this.selectedDonors,
    required this.controller,
    required this.focusNode,
    required this.enabled,
    required this.loading,
    required this.onSelected,
  });

  List<String> _getSuggestions(String query) {
    if (query.isEmpty) return [];
    final lower = query.toLowerCase();
    return allDonors
        .where((name) =>
            name.toLowerCase().contains(lower) &&
            !selectedDonors.contains(name))
        .take(8)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      optionsBuilder: (textEditingValue) {
        return _getSuggestions(textEditingValue.text);
      },
      onSelected: onSelected,
      fieldViewBuilder: (ctx, textController, focusNode, onFieldSubmitted) {
        // Sync our external controller with Autocomplete's internal one
        textController.addListener(() {
          if (controller.text != textController.text) {
            controller.text = textController.text;
          }
        });
        return TextField(
          controller: textController,
          focusNode: focusNode,
          enabled: enabled,
          decoration: InputDecoration(
            hintText: loading
                ? 'Loading donors…'
                : allDonors.isEmpty
                    ? 'Upload Excel to search donors'
                    : 'Type a donor name to search…',
            prefixIcon: loading
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : const Icon(Icons.search, size: 20),
            suffixIcon: ListenableBuilder(
              listenable: textController,
              builder: (_, __) => textController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        textController.clear();
                        controller.clear();
                      },
                    )
                  : const SizedBox.shrink(),
            ),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onSubmitted: (val) {
            // If text exactly matches a donor name, add it
            final exact = allDonors.firstWhere(
              (n) => n.toLowerCase() == val.toLowerCase(),
              orElse: () => '',
            );
            if (exact.isNotEmpty) {
              onSelected(exact);
              textController.clear();
            } else if (val.isNotEmpty) {
              // Add whatever was typed even if not in list
              onSelected(val);
              textController.clear();
            }
          },
        );
      },
      optionsViewBuilder: (ctx, onSelected, options) {
        final theme = Theme.of(ctx);
        final cs = theme.colorScheme;
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 620, maxHeight: 280),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (ctx, idx) {
                  final name = options.elementAt(idx);
                  return InkWell(
                    onTap: () => onSelected(name),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          vertical: 10, horizontal: 16),
                      child: Row(
                        children: [
                          Icon(Icons.person_outline,
                              size: 16, color: cs.primary),
                          const SizedBox(width: 10),
                          Text(name, style: theme.textTheme.bodyMedium),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Reusable widgets ────────────────────────────────────────────────────────

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
        isDense: true,
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  const _SectionCard(
      {required this.title, required this.icon, required this.child});
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
