import 'dart:async';
import 'dart:io';

enum ServerStatus { stopped, starting, running, error }

class ServerManager {
  static final ServerManager _instance = ServerManager._();
  ServerManager._();
  factory ServerManager() => _instance;

  ServerStatus status = ServerStatus.stopped;
  String? lastError;

  // ─── Binary topish ──────────────────────────────────────────────────────
  // GUI ilova sifatida ishga tushganda PATH'da Homebrew/pip bin yo'llari
  // bo'lmaydi (Finder/.app launch shell profile'ni o'qimaydi). Shuning uchun
  // standart joylardan qidiramiz va to'liq yo'lni ishlatamiz.

  static const List<String> _mlxSearchPaths = [
    '/Library/Frameworks/Python.framework/Versions/3.13/bin/mlx_lm.server',
    '/Library/Frameworks/Python.framework/Versions/3.12/bin/mlx_lm.server',
    '/Library/Frameworks/Python.framework/Versions/3.11/bin/mlx_lm.server',
    '/opt/homebrew/bin/mlx_lm.server',
    '/usr/local/bin/mlx_lm.server',
  ];

  static const List<String> _ollamaSearchPaths = [
    '/opt/homebrew/bin/ollama',
    '/usr/local/bin/ollama',
    '/Applications/Ollama.app/Contents/Resources/ollama',
  ];

  String? _cachedMlxBin;
  String? _cachedOllamaBin;

  Future<String?> _findBinary(String name, List<String> knownPaths) async {
    for (final path in knownPaths) {
      if (await File(path).exists()) return path;
    }
    // Login shell orqali PATH'ni so'raymiz (oxirgi chora)
    try {
      final result = await Process.run(
        'bash',
        ['-l', '-c', 'which $name'],
      ).timeout(const Duration(seconds: 5));
      final out = result.stdout.toString().trim();
      if (out.isNotEmpty && await File(out).exists()) return out;
    } catch (_) {}

    // ~/Library/Python va pip user-installs ham qidiramiz
    final home = Platform.environment['HOME'] ?? '';
    final extra = [
      '$home/Library/Python/3.13/bin/$name',
      '$home/Library/Python/3.12/bin/$name',
      '$home/.local/bin/$name',
    ];
    for (final path in extra) {
      if (await File(path).exists()) return path;
    }
    return null;
  }

  Future<String?> findMlxBinary() async {
    _cachedMlxBin ??= await _findBinary('mlx_lm.server', _mlxSearchPaths);
    return _cachedMlxBin;
  }

  Future<String?> findOllamaBinary() async {
    _cachedOllamaBin ??= await _findBinary('ollama', _ollamaSearchPaths);
    return _cachedOllamaBin;
  }

  // ─── MLX-LM restart ──────────────────────────────────────────────────────

  Future<bool> restartMlx({
    required String modelPath,
    required String mlxUrl,
  }) async {
    status = ServerStatus.starting;
    lastError = null;

    await _killMlx();

    final mlxBin = await findMlxBinary();
    if (mlxBin == null) {
      status = ServerStatus.error;
      lastError = 'mlx_lm.server topilmadi. Terminalda ishlatib ko\'ring: '
          'pip3 install mlx-lm';
      return false;
    }

    // mlxUrl haqiqiy http(s) URL ekanligini tekshiramiz — masalan fayl yo'li
    // tasodifan shu maydonga yozilib qolgan bo'lsa, port=0 bo'lib server
    // noto'g'ri ishga tushib qolmasligi uchun
    final parsedUrl = Uri.tryParse(mlxUrl);
    if (parsedUrl == null ||
        !(parsedUrl.scheme == 'http' || parsedUrl.scheme == 'https') ||
        parsedUrl.host.isEmpty) {
      status = ServerStatus.error;
      lastError = '"$mlxUrl" — yaroqli URL emas. MLX-LM URL maydoni '
          'http://localhost:8080 kabi bo\'lishi kerak (model yo\'li emas).';
      return false;
    }
    final port = parsedUrl.port == 0 ? 8080 : parsedUrl.port;

    try {
      final safeModel = modelPath.replaceAll("'", "'\\''");
      final safeBin = mlxBin.replaceAll("'", "'\\''");
      await Process.run('bash', [
        '-c',
        "nohup '$safeBin' --model '$safeModel' --port $port "
            "> /tmp/mlx_server.log 2>&1 &",
      ]);

      final ready = await _waitReady(mlxUrl, maxSeconds: 300);
      status = ready ? ServerStatus.running : ServerStatus.error;
      if (!ready) {
        lastError = await _readLastError('/tmp/mlx_server.log') ??
            'Server 5 daqiqa ichida javob bermadi';
      }
      return ready;
    } catch (e) {
      status = ServerStatus.error;
      lastError = e.toString();
      return false;
    }
  }

  Future<void> _killMlx() async {
    await Process.run('pkill', ['-9', '-f', 'mlx_lm.server'])
        .catchError((_) => ProcessResult(0, 0, '', ''));
    await Future.delayed(const Duration(milliseconds: 800));
  }

  // ─── Ollama restart ───────────────────────────────────────────────────────

  Future<bool> restartOllama({required String ollamaUrl}) async {
    status = ServerStatus.starting;
    lastError = null;

    await _killOllama();

    final ollamaBin = await findOllamaBinary();
    if (ollamaBin == null) {
      status = ServerStatus.error;
      lastError = 'Ollama topilmadi. O\'rnatish: brew install ollama';
      return false;
    }

    try {
      final safeBin = ollamaBin.replaceAll("'", "'\\''");
      await Process.run('bash', [
        '-c',
        "nohup '$safeBin' serve > /tmp/ollama_server.log 2>&1 &",
      ]);

      final ready = await _waitReady(
        ollamaUrl,
        maxSeconds: 15,
        path: '/api/tags',
      );
      status = ready ? ServerStatus.running : ServerStatus.error;
      if (!ready) lastError = 'Ollama server javob bermadi';
      return ready;
    } catch (e) {
      status = ServerStatus.error;
      lastError = e.toString();
      return false;
    }
  }

  Future<void> _killOllama() async {
    await Process.run('pkill', ['-f', 'ollama'])
        .catchError((_) => ProcessResult(0, 0, '', ''));
    await Future.delayed(const Duration(milliseconds: 500));
  }

  // ─── Health check ─────────────────────────────────────────────────────────

  Future<bool> _waitReady(
    String baseUrl, {
    required int maxSeconds,
    String path = '/v1/models',
  }) async {
    final deadline = DateTime.now().add(Duration(seconds: maxSeconds));
    while (DateTime.now().isBefore(deadline)) {
      try {
        final client = HttpClient()
          ..connectionTimeout = const Duration(seconds: 3);
        final req = await client
            .getUrl(Uri.parse('$baseUrl$path'))
            .timeout(const Duration(seconds: 3));
        final res = await req.close().timeout(const Duration(seconds: 3));
        client.close();
        if (res.statusCode == 200) return true;
      } catch (_) {}
      await Future.delayed(const Duration(seconds: 5));
    }
    return false;
  }

  Future<String?> _readLastError(String logPath) async {
    try {
      final file = File(logPath);
      if (!await file.exists()) return null;
      final lines = await file.readAsLines();
      // Oxirgi ValueError/Error/Exception qatorini topamiz
      for (final line in lines.reversed) {
        if (line.contains('Error') || line.contains('Exception')) {
          return line.trim();
        }
      }
    } catch (_) {}
    return null;
  }
}
