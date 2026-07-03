import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show Endian;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

// Config fayllar ro'yxati — weights emas, faqat kichik yordamchi fayllar
const _configFiles = [
  'config.json',
  'tokenizer.json',
  'tokenizer_config.json',
  'generation_config.json',
  'tokenizer.model',
  'vocab.json',
  'merges.txt',
  'special_tokens_map.json',
  'model.safetensors.index.json',  // sharded model uchun
];

class ModelEntry {
  final String name;
  final String sourcePath;
  final String cachedPath;
  final DateTime addedAt;
  final int sizeBytes;

  ModelEntry({
    required this.name,
    required this.sourcePath,
    required this.cachedPath,
    DateTime? addedAt,
    this.sizeBytes = 0,
  }) : addedAt = addedAt ?? DateTime.now();

  factory ModelEntry.fromJson(Map<String, dynamic> j) => ModelEntry(
        name: j['name'] as String,
        sourcePath: j['sourcePath'] as String,
        cachedPath: j['cachedPath'] as String,
        addedAt: DateTime.fromMillisecondsSinceEpoch(j['addedAt'] as int),
        sizeBytes: j['sizeBytes'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'sourcePath': sourcePath,
        'cachedPath': cachedPath,
        'addedAt': addedAt.millisecondsSinceEpoch,
        'sizeBytes': sizeBytes,
      };

  String get sizeLabel {
    if (sizeBytes <= 0) return '';
    final gb = sizeBytes / (1024 * 1024 * 1024);
    if (gb >= 1) return '${gb.toStringAsFixed(1)} GB';
    final mb = sizeBytes / (1024 * 1024);
    return '${mb.toStringAsFixed(0)} MB';
  }

  bool get exists => Directory(cachedPath).existsSync() || File(cachedPath).existsSync();
}

class CopyProgress {
  final String currentFile;
  final int copiedFiles;
  final int totalFiles;
  final int copiedBytes;
  final int totalBytes;

  CopyProgress({
    required this.currentFile,
    required this.copiedFiles,
    required this.totalFiles,
    required this.copiedBytes,
    required this.totalBytes,
  });

  double get fraction =>
      totalBytes > 0 ? (copiedBytes / totalBytes).clamp(0.0, 1.0) : 0.0;

  String get label {
    final pct = (fraction * 100).toStringAsFixed(0);
    final gb = copiedBytes / (1024 * 1024 * 1024);
    final totalGb = totalBytes / (1024 * 1024 * 1024);
    if (totalGb >= 1) {
      return '$pct% • ${gb.toStringAsFixed(2)} / ${totalGb.toStringAsFixed(2)} GB';
    }
    final mb = copiedBytes / (1024 * 1024);
    final totalMb = totalBytes / (1024 * 1024);
    return '$pct% • ${mb.toStringAsFixed(0)} / ${totalMb.toStringAsFixed(0)} MB';
  }
}

class ModelCacheService {
  static final ModelCacheService _instance = ModelCacheService._();
  ModelCacheService._();
  factory ModelCacheService() => _instance;

  static const _registryName = 'registry.json';

  Future<String> getCacheDir() async {
    final home = Platform.environment['HOME']!;
    final dir = Directory(p.join(home, 'Documents', 'offline_model_caches'));
    await dir.create(recursive: true);
    return dir.path;
  }

  Future<File> _registryFile() async =>
      File(p.join(await getCacheDir(), _registryName));

  Future<List<ModelEntry>> listModels() async {
    final file = await _registryFile();
    List<ModelEntry> models = [];
    if (file.existsSync()) {
      try {
        final data = jsonDecode(await file.readAsString()) as List;
        models = data
            .map((j) => ModelEntry.fromJson(j as Map<String, dynamic>))
            .toList();
      } catch (_) {
        models = [];
      }
    }

    // Cache papkaga qo'lda tashlangan (registry'da yo'q) model papkalarini
    // avtomatik topib, ro'yxatga qo'shamiz
    final discovered = await _discoverUnregisteredModels(models);
    if (discovered.isNotEmpty) {
      models = [...discovered, ...models];
      await _save(models);
    }

    models.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return models;
  }

  // Cache papkasidagi barcha subfolder'larni ko'rib chiqib, registry'da
  // bo'lmagan va model fayllariga ega bo'lganlarini topadi
  Future<List<ModelEntry>> _discoverUnregisteredModels(
      List<ModelEntry> known) async {
    final cacheDir = await getCacheDir();
    final dir = Directory(cacheDir);
    if (!dir.existsSync()) return [];

    final knownNames = known.map((m) => m.name).toSet();
    final found = <ModelEntry>[];

    for (final entry in dir.listSync()) {
      if (entry is! Directory) continue;
      final name = p.basename(entry.path);
      if (knownNames.contains(name)) continue;

      final hasWeights = entry
          .listSync()
          .any((e) => e is File && e.path.endsWith('.safetensors'));
      if (!hasWeights) continue;

      found.add(ModelEntry(
        name: name,
        sourcePath: entry.path,
        cachedPath: entry.path,
        sizeBytes: await _measureSize(entry.path),
      ));
    }
    return found;
  }

  // ─── Asosiy metod: nusxa + yordamchi fayllar ────────────────────────────

  Future<ModelEntry> addModel(
    String sourcePath, {
    // HuggingFace model ID (masalan "Qwen/Qwen2.5-Coder-14B-Instruct")
    // Agar config fayllar manba papkada yo'q bo'lsa, shu ID orqali yuklanadi
    String? hfModelId,
    void Function(CopyProgress)? onProgress,
    void Function(String)? onStatus,
  }) async {
    final cacheDir = await getCacheDir();
    final name = p.basename(sourcePath);
    final cachedPath = p.join(cacheDir, name);

    await Directory(cachedPath).create(recursive: true);

    // 1. Manba papkadagi barcha fayllarni nusxa ko'chiramiz
    onStatus?.call('Fayllar hisoblanmoqda…');
    final totalBytes = await _measureSize(sourcePath);

    onStatus?.call('Nusxa ko\'chirilmoqda…');
    await _copyDirectory(
      sourcePath,
      cachedPath,
      totalBytes: totalBytes,
      onProgress: onProgress,
    );

    // 2. Weights quantized (MLX 4-bit/8-bit) yoki oddiymi — aniqlaymiz
    onStatus?.call('Model formati tekshirilmoqda…');
    final isQuantized = await _detectQuantization(cachedPath);

    // 3. Yordamchi fayllar (config.json va boshqalar) bor-yo'qligini tekshiramiz
    final initialMissing = _findMissingConfigs(cachedPath);
    final alreadyHasConfig = File(p.join(cachedPath, 'config.json')).existsSync();

    // Agar config bor bo'lsa ham, quantization mos kelmasa qayta yuklaymiz
    final needsConfig = initialMissing.isNotEmpty ||
        (alreadyHasConfig && _configHasQuantization(cachedPath) != isQuantized);

    if (needsConfig && hfModelId != null && hfModelId.isNotEmpty) {
      final candidates = _buildModelIdCandidates(hfModelId, isQuantized);

      bool success = false;
      for (final candidate in candidates) {
        onStatus?.call('Sinab ko\'rilmoqda: $candidate…');
        // Har bir urinishda config.json'ni majburan qayta yuklaymiz
        final filesToFetch = {'config.json', ..._configFiles}.toList();
        await _downloadConfigs(
          hfModelId: candidate,
          destDir: cachedPath,
          files: filesToFetch,
          onStatus: onStatus,
        );

        if (File(p.join(cachedPath, 'config.json')).existsSync()) {
          final configQuantized = _configHasQuantization(cachedPath);
          if (configQuantized == isQuantized) {
            success = true;
            onStatus?.call('✓ Mos config topildi: $candidate');
            break;
          }
        }
      }

      if (!success) {
        onStatus?.call(
            '⚠ Avtomatik mos config topilmadi — model ishlamasligi mumkin');
      }
    }

    // 4. Registry'ga yozamiz
    final entry = ModelEntry(
      name: name,
      sourcePath: sourcePath,
      cachedPath: cachedPath,
      sizeBytes: await _measureSize(cachedPath),
    );

    final models = await listModels();
    models.removeWhere((m) => m.name == name);
    models.insert(0, entry);
    await _save(models);
    return entry;
  }

  // Safetensors fayl headerini o'qib, MLX quantization (scales/biases)
  // bor-yo'qligini aniqlaydi — bu weights MLX 4-bit/8-bit ekanini bildiradi
  Future<bool> _detectQuantization(String modelDir) async {
    try {
      final dir = Directory(modelDir);
      final stFile = await dir
          .list()
          .firstWhere((e) => e.path.endsWith('.safetensors'));
      final file = File(stFile.path);
      final raf = await file.open();
      final headerSizeBytes = await raf.read(8);
      final headerSize = headerSizeBytes.buffer.asByteData().getUint64(0, Endian.little);
      final headerBytes = await raf.read(headerSize);
      await raf.close();
      final header = utf8.decode(headerBytes);
      return header.contains('"scales"') || header.contains('.scales"');
    } catch (_) {
      return false;
    }
  }

  // config.json ichida quantization maydoni borligini tekshiradi
  bool _configHasQuantization(String modelDir) {
    try {
      final configFile = File(p.join(modelDir, 'config.json'));
      if (!configFile.existsSync()) return false;
      final config = jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
      return config['quantization'] != null;
    } catch (_) {
      return false;
    }
  }

  // Quantized model uchun mlx-community variantlarini ham sinab ko'ramiz
  List<String> _buildModelIdCandidates(String hfModelId, bool isQuantized) {
    final candidates = <String>[];

    if (isQuantized) {
      // Agar foydalanuvchi allaqachon mlx-community/... yozgan bo'lsa — birinchi
      if (hfModelId.toLowerCase().contains('mlx-community') ||
          hfModelId.toLowerCase().contains('-4bit') ||
          hfModelId.toLowerCase().contains('-8bit')) {
        candidates.add(hfModelId);
      } else {
        // Asosiy nomdan mlx-community variant quramiz
        final shortName = hfModelId.split('/').last;
        candidates.add('mlx-community/$shortName-4bit');
        candidates.add('mlx-community/$shortName-8bit');
        candidates.add(hfModelId); // fallback
      }
    } else {
      candidates.add(hfModelId);
    }

    return candidates;
  }

  // Qaysi config fayllar yo'qligini aniqlaydi
  List<String> _findMissingConfigs(String dirPath) {
    // Eng muhimi: config.json bo'lishi shart
    final missing = <String>[];
    // config.json majburiy
    if (!File(p.join(dirPath, 'config.json')).existsSync()) {
      missing.add('config.json');
    }
    // Qolganlar optional lekin kerakli
    for (final f in _configFiles) {
      if (!File(p.join(dirPath, f)).existsSync()) {
        missing.add(f);
      }
    }
    return missing;
  }

  // HuggingFace'dan faqat config fayllarini yuklab oladi (MB'lar, emas GB)
  Future<void> _downloadConfigs({
    required String hfModelId,
    required String destDir,
    required List<String> files,
    void Function(String)? onStatus,
  }) async {
    final base = 'https://huggingface.co/$hfModelId/resolve/main';
    for (final file in files) {
      onStatus?.call('Yuklanmoqda: $file');
      try {
        final res = await http
            .get(Uri.parse('$base/$file'))
            .timeout(const Duration(seconds: 30));
        if (res.statusCode == 200) {
          await File(p.join(destDir, file)).writeAsBytes(res.bodyBytes);
        }
        // 404 bo'lsa o'tkazib yuboramiz (optional fayl)
      } catch (_) {
        // Network error — o'tkazib yuboramiz
      }
    }
  }

  // Papkadagi config.json mavjudligini tekshiradi
  bool hasConfig(String folderPath) =>
      File(p.join(folderPath, 'config.json')).existsSync();

  // ─── Yordamchi metodlar ──────────────────────────────────────────────────

  Future<void> removeModel(String name) async {
    final cacheDir = await getCacheDir();
    final modelPath = p.join(cacheDir, name);
    final dir = Directory(modelPath);
    if (dir.existsSync()) await dir.delete(recursive: true);
    final models = await listModels();
    models.removeWhere((m) => m.name == name);
    await _save(models);
  }

  Future<void> _save(List<ModelEntry> models) async {
    final file = await _registryFile();
    await file.writeAsString(
        jsonEncode(models.map((m) => m.toJson()).toList()));
  }

  Future<void> openCacheDir() async {
    final dir = await getCacheDir();
    await Process.run('open', [dir]);
  }

  Future<int> _measureSize(String path) async {
    int total = 0;
    final type = FileSystemEntity.typeSync(path);
    if (type == FileSystemEntityType.directory) {
      await for (final e in Directory(path).list(recursive: true)) {
        if (e is File) total += await e.length();
      }
    } else if (type == FileSystemEntityType.file) {
      total = await File(path).length();
    }
    return total;
  }

  Future<void> _copyDirectory(
    String source,
    String dest, {
    required int totalBytes,
    void Function(CopyProgress)? onProgress,
  }) async {
    final srcDir = Directory(source);
    final dstDir = Directory(dest);
    await dstDir.create(recursive: true);

    final all = await srcDir.list(recursive: true).toList();
    final files = all.whereType<File>().toList();

    int copiedBytes = 0;
    int copiedFiles = 0;

    for (final file in files) {
      final rel = p.relative(file.path, from: srcDir.path);
      final dstFile = File(p.join(dstDir.path, rel));
      await dstFile.parent.create(recursive: true);

      final bytes = await file.readAsBytes();
      await dstFile.writeAsBytes(bytes);

      copiedBytes += bytes.length;
      copiedFiles++;

      onProgress?.call(CopyProgress(
        currentFile: p.basename(file.path),
        copiedFiles: copiedFiles,
        totalFiles: files.length,
        copiedBytes: copiedBytes,
        totalBytes: totalBytes,
      ));
    }
  }
}
