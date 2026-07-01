import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/chat_provider.dart';
import '../../services/model_cache_service.dart';
import '../../services/ollama_service.dart';
import '../../services/server_manager.dart';
import '../app_theme.dart';

class SettingsDialog extends ConsumerStatefulWidget {
  const SettingsDialog({super.key});

  @override
  ConsumerState<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends ConsumerState<SettingsDialog>
    with SingleTickerProviderStateMixin {
  late BackendType _backendType;
  late TextEditingController _ollamaUrlCtrl;
  late TextEditingController _mlxUrlCtrl;

  // Tanlangan model: backend modelidan yoki lokal cache
  String? _selectedModel; // null = hech narsa tanlanmagan
  bool _useLocalModel = false;

  // Ulanish testi
  bool _testing = false;
  String? _testResult;
  bool? _testSuccess;
  List<String> _serverModels = [];

  bool _restarting = false;

  // Lokal modellar
  List<ModelEntry> _localModels = [];
  bool _loadingLocalModels = false;
  bool _addingModel = false;
  CopyProgress? _copyProgress;
  String? _copyStatusText;

  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    final s = ref.read(settingsProvider);
    _backendType = s.backendType;
    _ollamaUrlCtrl = TextEditingController(text: s.ollamaUrl);
    _mlxUrlCtrl = TextEditingController(text: s.mlxUrl);
    _selectedModel = s.model;
    _serverModels = List.from(s.availableModels);
    _useLocalModel = s.useLocalModel;
    _tabCtrl = TabController(length: 2, vsync: this,
        initialIndex: s.useLocalModel ? 1 : 0);
    _tabCtrl.addListener(() {
      setState(() => _useLocalModel = _tabCtrl.index == 1);
    });
    _loadLocalModels();
  }

  @override
  void dispose() {
    _ollamaUrlCtrl.dispose();
    _mlxUrlCtrl.dispose();
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLocalModels() async {
    setState(() => _loadingLocalModels = true);
    final models = await ModelCacheService().listModels();
    if (mounted) {
      setState(() {
        _localModels = models;
        _loadingLocalModels = false;
      });
    }
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _testResult = null;
      _testSuccess = null;
    });
    final url = _backendType == BackendType.ollama
        ? _ollamaUrlCtrl.text.trim()
        : _mlxUrlCtrl.text.trim();
    try {
      final result = await OllamaService().testBackend(type: _backendType, url: url);
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testSuccess = result.running;
        _serverModels = result.models;
        if (result.running) {
          _testResult = 'Ulandi ✓  ${result.models.length} model topildi';
          if (result.models.isNotEmpty && !_useLocalModel) {
            _selectedModel ??= result.models.first;
          }
        } else {
          _testResult = 'Ulanib bo\'lmadi — server ishlamayapti';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testing = false;
        _testSuccess = false;
        _testResult = 'Xato: $e';
      });
    }
  }

  // Config yo'q bo'lsa HuggingFace model ID so'raydigan dialog
  Future<String?> _askHfModelId(String sourcePath) async {
    final ctrl = TextEditingController();
    final modelName = sourcePath.split('/').last;

    // Umumiy modellar uchun avtomatik taklif
    final suggestions = {
      'qwen25-coder-14b': 'Qwen/Qwen2.5-Coder-14B-Instruct',
      'qwen25-coder-7b': 'Qwen/Qwen2.5-Coder-7B-Instruct',
      'qwen25-coder-3b': 'Qwen/Qwen2.5-Coder-3B-Instruct',
      'deepseek-coder-v2-lite': 'deepseek-ai/DeepSeek-Coder-V2-Lite-Instruct',
      'deepseek-coder': 'deepseek-ai/deepseek-coder-6.7b-instruct',
      'llama': 'meta-llama/Llama-3.2-3B-Instruct',
      'mistral': 'mistralai/Mistral-7B-Instruct-v0.3',
      'gemma': 'google/gemma-2-2b-it',
    };

    // Model nomiga mos taklif topamiz
    final lower = modelName.toLowerCase().replaceAll('-', '').replaceAll('_', '');
    String? suggested;
    for (final e in suggestions.entries) {
      if (lower.contains(e.key.replaceAll('-', ''))) {
        suggested = e.value;
        break;
      }
    }
    if (suggested != null) ctrl.text = suggested;

    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Text('Yordamchi fayllar kerak',
            style: TextStyle(color: AppColors.textBright, fontSize: 15)),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                text: TextSpan(
                  style: const TextStyle(color: AppColors.textDim, fontSize: 13, height: 1.5),
                  children: [
                    const TextSpan(text: '«'),
                    TextSpan(
                      text: modelName,
                      style: const TextStyle(color: AppColors.text, fontFamily: 'monospace'),
                    ),
                    const TextSpan(
                      text: '» papkasida config.json topilmadi.\n\n'
                          'HuggingFace model ID kiriting — yordamchi fayllar (config, tokenizer) '
                          'avtomatik yuklanadi (faqat MB, weights emas):',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                autofocus: true,
                style: const TextStyle(
                    color: AppColors.textBright, fontSize: 13, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText: 'Qwen/Qwen2.5-Coder-14B-Instruct',
                  hintStyle: const TextStyle(color: AppColors.textDim, fontSize: 12),
                  prefixIcon: const Icon(Icons.cloud_download_outlined,
                      size: 15, color: AppColors.textDim),
                  filled: true,
                  fillColor: AppColors.bg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: const BorderSide(color: AppColors.accent),
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              if (suggested != null) ...[
                const SizedBox(height: 6),
                Text(
                  '✓ Avtomatik aniqlandi',
                  style: const TextStyle(fontSize: 11, color: AppColors.green),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('ID siz davom etish',
                style: TextStyle(color: AppColors.textDim, fontSize: 12)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
            child: const Text('Yuklab olish va nusxa ko\'chirish',
                style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Future<void> _addLocalModel() async {
    setState(() => _addingModel = true);
    try {
      final path = await FilePicker.platform.getDirectoryPath(
        dialogTitle: 'Model papkasini tanlang',
      );
      if (path == null) return;

      // Config fayllar bor-yo'qligini tekshiramiz
      String? hfModelId;
      final hasConfig = ModelCacheService().hasConfig(path);
      if (!hasConfig && mounted) {
        // Config yo'q — HuggingFace model ID so'raymiz
        hfModelId = await _askHfModelId(path);
        if (!mounted) return;
      }

      String statusText = 'Tayyorlanmoqda…';
      setState(() => _copyStatusText = statusText);

      final entry = await ModelCacheService().addModel(
        path,
        hfModelId: hfModelId,
        onProgress: (prog) {
          if (mounted) setState(() => _copyProgress = prog);
        },
        onStatus: (s) {
          if (mounted) setState(() => _copyStatusText = s);
        },
      );

      if (mounted) {
        setState(() {
          _copyProgress = null;
          _copyStatusText = null;
          _selectedModel = entry.cachedPath;
        });
        await _loadLocalModels();
      }
    } finally {
      if (mounted) {
        setState(() {
          _addingModel = false;
          _copyProgress = null;
          _copyStatusText = null;
        });
      }
    }
  }

  Future<void> _removeLocalModel(ModelEntry e) async {
    await ModelCacheService().removeModel(e.name);
    if (_selectedModel == e.cachedPath) setState(() => _selectedModel = null);
    await _loadLocalModels();
  }

  Future<void> _reset() async {
    if (_restarting) return;

    final model = _selectedModel ?? '';
    final backendLabel = _backendType == BackendType.ollama ? 'Ollama' : 'MLX-LM';

    setState(() {
      _restarting = true;
      _testResult = null;
      _testSuccess = null;
    });

    // Server restart
    final mgr = ServerManager();
    bool success = false;

    if (_backendType == BackendType.mlx) {
      // Model yo'li: lokal model cachedPath yoki server model ID
      final modelPath = model.isNotEmpty ? model : 'Wizcoderr/qwen3-14b-flutter-fused';
      success = await mgr.restartMlx(
        modelPath: modelPath,
        mlxUrl: _mlxUrlCtrl.text.trim(),
      );
    } else {
      success = await mgr.restartOllama(
        ollamaUrl: _ollamaUrlCtrl.text.trim(),
      );
    }

    if (!mounted) return;

    setState(() {
      _restarting = false;
      _testSuccess = success;
      _testResult = success
          ? '$backendLabel muvaffaqiyatli restart bo\'ldi ✓'
          : 'Restart xato: ${mgr.lastError ?? "server javob bermadi"}';
    });

    // Provayderga ham yangi holat berish
    if (success && mounted) {
      final models = await OllamaService().listModels();
      if (mounted) {
        setState(() => _serverModels = models);
        ref.read(settingsProvider.notifier).applySettingsDirect(
          backendType: _backendType,
          ollamaUrl: _ollamaUrlCtrl.text.trim(),
          mlxUrl: _mlxUrlCtrl.text.trim(),
          model: model,
          alreadyConnected: true,
          detectedModels: models,
          useLocalModel: _useLocalModel,
        );
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: success ? AppColors.green : AppColors.red,
      content: Text(
        success
            ? '$backendLabel qayta ishga tushdi'
            : 'Restart muvaffaqiyatsiz: ${mgr.lastError}',
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
      duration: const Duration(seconds: 3),
    ));
  }

  void _save() {
    final model = _selectedModel ?? '';
    if (model.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        backgroundColor: AppColors.red,
        content: Text('Model tanlanmagan!', style: TextStyle(color: Colors.white)),
      ));
      return;
    }

    // Bo'sh yoki yaroqsiz URL saqlanib qolmasligi uchun fallback
    final ollamaUrl = _ollamaUrlCtrl.text.trim().isEmpty
        ? 'http://localhost:11434'
        : _ollamaUrlCtrl.text.trim();
    final mlxUrl = _mlxUrlCtrl.text.trim().isEmpty
        ? 'http://localhost:8080'
        : _mlxUrlCtrl.text.trim();

    ref.read(settingsProvider.notifier).applySettingsDirect(
      backendType: _backendType,
      ollamaUrl: ollamaUrl,
      mlxUrl: mlxUrl,
      model: model,
      alreadyConnected: _testSuccess == true,
      detectedModels: _serverModels,
      useLocalModel: _useLocalModel,
    );

    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: AppColors.green,
      content: Text(
        'Saqlandi — ${_useLocalModel ? "Lokal model" : _backendType.name.toUpperCase()}',
        style: const TextStyle(color: Colors.white, fontSize: 13),
      ),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;

    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: AppColors.border),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 520,
          maxHeight: screenH * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Fixed Header ────────────────────────────────────────────
            _Header(
              onClose: () => Navigator.pop(context),
              backendType: _backendType,
              restarting: _restarting,
              onRestart: _reset,
            ),

            // ── Scrollable Body ─────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Backend
                    _label('Backend'),
                    const SizedBox(height: 8),
                    _BackendToggle(
                      selected: _backendType,
                      onChanged: (t) => setState(() {
                        _backendType = t;
                        _testResult = null;
                        _testSuccess = null;
                      }),
                    ),

                    const SizedBox(height: 18),

                    // Ollama URL
                    _label('Ollama URL'),
                    const SizedBox(height: 6),
                    _UrlField(
                      controller: _ollamaUrlCtrl,
                      enabled: _backendType == BackendType.ollama,
                      hint: 'http://localhost:11434',
                      icon: Icons.hub_outlined,
                    ),

                    const SizedBox(height: 12),

                    // MLX URL
                    _label('MLX-LM URL'),
                    const SizedBox(height: 6),
                    _UrlField(
                      controller: _mlxUrlCtrl,
                      enabled: _backendType == BackendType.mlx,
                      hint: 'http://localhost:8080',
                      icon: Icons.memory_outlined,
                    ),

                    const SizedBox(height: 14),

                    // Test tugmasi
                    Row(children: [
                      OutlinedButton.icon(
                        onPressed: _testing ? null : _testConnection,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.text,
                          side: const BorderSide(color: AppColors.border),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 9),
                        ),
                        icon: _testing
                            ? const SizedBox(
                                width: 13,
                                height: 13,
                                child: CircularProgressIndicator(
                                    strokeWidth: 1.5, color: AppColors.textDim))
                            : const Icon(Icons.wifi_tethering, size: 14),
                        label: Text(
                          _testing ? 'Tekshirilmoqda…' : 'Ulanishni tekshirish',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (_testResult != null)
                        Flexible(
                          child: Row(children: [
                            Icon(
                              _testSuccess == true
                                  ? Icons.check_circle_outline
                                  : Icons.error_outline,
                              size: 13,
                              color: _testSuccess == true
                                  ? AppColors.green
                                  : AppColors.red,
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                _testResult!,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: _testSuccess == true
                                      ? AppColors.green
                                      : AppColors.red,
                                ),
                              ),
                            ),
                          ]),
                        ),
                    ]),

                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 12),

                    // ── Model bo'limi ──────────────────────────────────
                    Row(children: [
                      const Expanded(
                        child: Text('Model',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textBright)),
                      ),
                      // Server / Lokal toggle
                      Container(
                        height: 30,
                        width: 150,
                        decoration: BoxDecoration(
                          color: AppColors.bg,
                          border: Border.all(color: AppColors.border),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: TabBar(
                          controller: _tabCtrl,
                          isScrollable: false,
                          dividerColor: Colors.transparent,
                          indicator: BoxDecoration(
                            color: AppColors.accent,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          indicatorSize: TabBarIndicatorSize.tab,
                          labelColor: Colors.white,
                          unselectedLabelColor: AppColors.textDim,
                          labelStyle: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w500),
                          tabs: const [
                            Tab(text: 'Server'),
                            Tab(text: 'Lokal'),
                          ],
                        ),
                      ),
                    ]),

                    const SizedBox(height: 10),

                    // Server modellari
                    if (!_useLocalModel) ...[
                      if (_serverModels.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.bg,
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(children: [
                            const Icon(Icons.info_outline,
                                size: 14, color: AppColors.textDim),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Ulanishni tekshiring — server modellari yuklanadi',
                                style: TextStyle(
                                    fontSize: 12, color: AppColors.textDim),
                              ),
                            ),
                          ]),
                        )
                      else
                        _ModelList(
                          models: _serverModels,
                          selected: _selectedModel,
                          onSelect: (m) => setState(() => _selectedModel = m),
                        ),
                    ],

                    // Lokal modellar
                    if (_useLocalModel) ...[
                      // Qo'shish tugmasi
                      Row(children: [
                        OutlinedButton.icon(
                          onPressed: _addingModel ? null : _addLocalModel,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.accent,
                            side: const BorderSide(color: AppColors.accent),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 8),
                          ),
                          icon: _addingModel
                              ? const SizedBox(
                                  width: 13,
                                  height: 13,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      color: AppColors.accent))
                              : const Icon(Icons.add_circle_outline, size: 14),
                          label: Text(
                            _addingModel
                                ? (_copyProgress == null
                                    ? 'Tayyorlanmoqda…'
                                    : 'Nusxa ko\'chirilmoqda…')
                                : 'Model qo\'shish',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Tooltip(
                          message: 'Cache papkasini ochish',
                          child: InkWell(
                            onTap: () => ModelCacheService().openCacheDir(),
                            borderRadius: BorderRadius.circular(6),
                            child: const Padding(
                              padding: EdgeInsets.all(6),
                              child: Icon(Icons.folder_outlined,
                                  size: 16, color: AppColors.textDim),
                            ),
                          ),
                        ),
                      ]),

                      const SizedBox(height: 8),

                      // Status matni (copy boshlangunga qadar)
                      if (_addingModel && _copyProgress == null && _copyStatusText != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(children: [
                            const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(
                                  strokeWidth: 1.5, color: AppColors.accent),
                            ),
                            const SizedBox(width: 8),
                            Text(_copyStatusText!,
                                style: const TextStyle(
                                    fontSize: 12, color: AppColors.textDim)),
                          ]),
                        ),

                      // Copy progress
                      if (_copyProgress != null) ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.bg,
                            border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                const Icon(Icons.copy_all, size: 13, color: AppColors.accent),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _copyProgress!.currentFile,
                                    style: const TextStyle(fontSize: 11, color: AppColors.text, fontFamily: 'monospace'),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Text(
                                  '${_copyProgress!.copiedFiles}/${_copyProgress!.totalFiles}',
                                  style: const TextStyle(fontSize: 10, color: AppColors.textDim),
                                ),
                              ]),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: _copyProgress!.fraction,
                                  backgroundColor: AppColors.surfaceHigh,
                                  valueColor: const AlwaysStoppedAnimation(AppColors.accent),
                                  minHeight: 4,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _copyProgress!.label,
                                style: const TextStyle(fontSize: 10, color: AppColors.textDim),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],

                      // Cache papka yo'li
                      FutureBuilder<String>(
                        future: ModelCacheService().getCacheDir(),
                        builder: (ctx, snap) {
                          if (!snap.hasData) return const SizedBox.shrink();
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(
                              '📁 ${snap.data}',
                              style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.textDim,
                                  fontFamily: 'monospace'),
                            ),
                          );
                        },
                      ),

                      // Lokal model ro'yxati
                      if (_loadingLocalModels)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              valueColor:
                                  AlwaysStoppedAnimation(AppColors.accent),
                            ),
                          ),
                        )
                      else if (_localModels.isEmpty)
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: AppColors.bg,
                            border: Border.all(
                                color: AppColors.border,
                                style: BorderStyle.solid),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(children: [
                            const Icon(Icons.folder_open_outlined,
                                size: 28, color: AppColors.textDim),
                            const SizedBox(height: 8),
                            const Text(
                              'Hali model qo\'shilmagan',
                              style: TextStyle(
                                  fontSize: 13, color: AppColors.textDim),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Masalan: /Volumes/First Disk/Ai/model-nomi',
                              style: const TextStyle(
                                  fontSize: 11, color: AppColors.textDim),
                            ),
                          ]),
                        )
                      else
                        _LocalModelList(
                          models: _localModels,
                          selected: _selectedModel,
                          onSelect: (path) =>
                              setState(() => _selectedModel = path),
                          onRemove: _removeLocalModel,
                        ),
                    ],

                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),

            // ── Fixed Footer (ALWAYS visible) ────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.border)),
                color: AppColors.surface,
                borderRadius:
                    BorderRadius.vertical(bottom: Radius.circular(14)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Tanlangan model preview
                  Expanded(
                    child: _selectedModel != null
                        ? Row(children: [
                            const Icon(Icons.smart_toy_outlined,
                                size: 13, color: AppColors.accent),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                _selectedModel!.split('/').last,
                                style: const TextStyle(
                                    fontSize: 11, color: AppColors.accent),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ])
                        : const Text('Model tanlanmagan',
                            style: TextStyle(
                                fontSize: 11, color: AppColors.textDim)),
                  ),
                  Row(children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Bekor qilish',
                          style:
                              TextStyle(color: AppColors.textDim, fontSize: 13)),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _save,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.save_outlined,
                          size: 14, color: Colors.white),
                      label: const Text('Saqlash',
                          style: TextStyle(
                              fontSize: 13,
                              color: Colors.white,
                              fontWeight: FontWeight.w500)),
                    ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.textDim,
          letterSpacing: 0.5,
        ),
      );
}

// ─── Header ─────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final VoidCallback onClose;
  final BackendType backendType;
  final bool restarting;
  final VoidCallback onRestart;

  const _Header({
    required this.onClose,
    required this.backendType,
    required this.restarting,
    required this.onRestart,
  });

  @override
  Widget build(BuildContext context) {
    final label = backendType == BackendType.ollama ? 'Ollama' : 'MLX-LM';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.surfaceHigh,
              borderRadius: BorderRadius.circular(7),
              border: Border.all(color: AppColors.border),
            ),
            child: const Icon(Icons.settings_outlined,
                size: 14, color: AppColors.textDim),
          ),
          const SizedBox(width: 10),
          const Text('Sozlamalar',
              style: TextStyle(
                  color: AppColors.textBright,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          const Spacer(),

          // ── Restart tugmasi — header'da, har doim ko'rinadi ──
          Tooltip(
            message: '$label serverni force restart qilish',
            child: InkWell(
              onTap: restarting ? null : onRestart,
              borderRadius: BorderRadius.circular(7),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: restarting
                      ? AppColors.accent.withValues(alpha: 0.15)
                      : AppColors.surfaceHigh,
                  border: Border.all(
                    color: restarting ? AppColors.accent : AppColors.border,
                  ),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  restarting
                      ? const SizedBox(
                          width: 11,
                          height: 11,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: AppColors.accent,
                          ),
                        )
                      : const Icon(Icons.restart_alt,
                          size: 14, color: AppColors.textDim),
                  const SizedBox(width: 5),
                  Text(
                    restarting ? 'Restart…' : 'Restart',
                    style: TextStyle(
                      fontSize: 12,
                      color: restarting ? AppColors.accent : AppColors.textDim,
                      fontWeight: restarting
                          ? FontWeight.w500
                          : FontWeight.normal,
                    ),
                  ),
                ]),
              ),
            ),
          ),

          const SizedBox(width: 8),
          InkWell(
            onTap: onClose,
            borderRadius: BorderRadius.circular(6),
            child: const Padding(
              padding: EdgeInsets.all(5),
              child: Icon(Icons.close, size: 15, color: AppColors.textDim),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Backend Toggle ──────────────────────────────────────────────────────────

class _BackendToggle extends StatelessWidget {
  final BackendType selected;
  final void Function(BackendType) onChanged;
  const _BackendToggle({required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      _Chip(
        label: 'Ollama',
        sub: 'NDJSON /api/chat',
        icon: Icons.hub_outlined,
        active: selected == BackendType.ollama,
        onTap: () => onChanged(BackendType.ollama),
      ),
      const SizedBox(width: 10),
      _Chip(
        label: 'MLX-LM',
        sub: 'OpenAI SSE /v1/chat',
        icon: Icons.memory_outlined,
        active: selected == BackendType.mlx,
        onTap: () => onChanged(BackendType.mlx),
      ),
    ]);
  }
}

class _Chip extends StatelessWidget {
  final String label, sub;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;
  const _Chip(
      {required this.label,
      required this.sub,
      required this.icon,
      required this.active,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: active
                ? AppColors.accent.withValues(alpha: 0.12)
                : AppColors.surfaceHigh,
            border: Border.all(
              color: active ? AppColors.accent : AppColors.border,
              width: active ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            Icon(icon,
                size: 15,
                color: active ? AppColors.accent : AppColors.textDim),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: active
                                ? AppColors.textBright
                                : AppColors.text)),
                    Text(sub,
                        style: const TextStyle(
                            fontSize: 10, color: AppColors.textDim)),
                  ]),
            ),
            if (active)
              const Icon(Icons.check_circle,
                  size: 13, color: AppColors.accent),
          ]),
        ),
      ),
    );
  }
}

// ─── URL Field ───────────────────────────────────────────────────────────────

class _UrlField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final bool enabled;
  const _UrlField(
      {required this.controller,
      required this.hint,
      required this.icon,
      this.enabled = true});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      style: TextStyle(
        fontSize: 13,
        color: enabled ? AppColors.textBright : AppColors.textDim,
        fontFamily: 'monospace',
      ),
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, size: 14, color: AppColors.textDim),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        filled: true,
        fillColor: enabled ? AppColors.bg : AppColors.surfaceHigh,
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              BorderSide(color: AppColors.border.withValues(alpha: 0.4)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.accent),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

// ─── Server model ro'yxati ───────────────────────────────────────────────────

class _ModelList extends StatelessWidget {
  final List<String> models;
  final String? selected;
  final void Function(String) onSelect;
  const _ModelList(
      {required this.models, this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bg,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: models.asMap().entries.map((e) {
          final i = e.key;
          final m = e.value;
          final sel = m == selected;
          return InkWell(
            onTap: () => onSelect(m),
            borderRadius: BorderRadius.vertical(
              top: i == 0 ? const Radius.circular(8) : Radius.zero,
              bottom: i == models.length - 1
                  ? const Radius.circular(8)
                  : Radius.zero,
            ),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: sel
                    ? AppColors.accent.withValues(alpha: 0.1)
                    : Colors.transparent,
                border: i < models.length - 1
                    ? const Border(
                        bottom: BorderSide(color: AppColors.border))
                    : null,
              ),
              child: Row(children: [
                Icon(
                  sel
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 14,
                  color: sel ? AppColors.accent : AppColors.textDim,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(m,
                      style: TextStyle(
                          fontSize: 12,
                          color: sel ? AppColors.accent : AppColors.text,
                          fontFamily: 'monospace')),
                ),
              ]),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─── Lokal model ro'yxati ────────────────────────────────────────────────────

class _LocalModelList extends StatelessWidget {
  final List<ModelEntry> models;
  final String? selected;
  final void Function(String) onSelect;
  final void Function(ModelEntry) onRemove;
  const _LocalModelList(
      {required this.models,
      this.selected,
      required this.onSelect,
      required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: models.map((entry) {
        final sel = selected == entry.cachedPath;
        return GestureDetector(
          onTap: () => onSelect(entry.cachedPath),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: sel
                  ? AppColors.accent.withValues(alpha: 0.1)
                  : AppColors.bg,
              border: Border.all(
                color: sel ? AppColors.accent : AppColors.border,
                width: sel ? 1.5 : 1,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(children: [
              Icon(
                entry.exists
                    ? Icons.smart_toy_outlined
                    : Icons.broken_image_outlined,
                size: 16,
                color: sel
                    ? AppColors.accent
                    : entry.exists
                        ? AppColors.green
                        : AppColors.red,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entry.name,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color:
                              sel ? AppColors.accent : AppColors.textBright,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        entry.sourcePath,
                        style: const TextStyle(
                            fontSize: 10,
                            color: AppColors.textDim,
                            fontFamily: 'monospace'),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (entry.sizeLabel.isNotEmpty)
                        Text(entry.sizeLabel,
                            style: const TextStyle(
                                fontSize: 10, color: AppColors.textDim)),
                    ]),
              ),
              const SizedBox(width: 8),
              // O'chirish
              Tooltip(
                message: 'Cache\'dan o\'chirish',
                child: InkWell(
                  onTap: () => onRemove(entry),
                  borderRadius: BorderRadius.circular(4),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.delete_outline,
                        size: 14, color: AppColors.textDim),
                  ),
                ),
              ),
            ]),
          ),
        );
      }).toList(),
    );
  }
}
