import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/message.dart';

enum BackendType { ollama, mlx }

class OllamaService {
  static final OllamaService _instance = OllamaService._();
  OllamaService._();
  factory OllamaService() => _instance;

  // Mutable config — settings sahifasidan yangilanadi
  String ollamaUrl = 'http://localhost:11434';
  String mlxUrl = 'http://localhost:8080';
  BackendType backendType = BackendType.ollama;

  final http.Client _client = http.Client();

  // ─── Model ro'yxati ───────────────────────────────────────────────────────

  Future<List<String>> listModels() async {
    try {
      if (backendType == BackendType.ollama) {
        return await _listOllamaModels();
      } else {
        return await _listMlxModels();
      }
    } catch (_) {
      return [];
    }
  }

  Future<List<String>> _listOllamaModels() async {
    final res = await http
        .get(Uri.parse('$ollamaUrl/api/tags'))
        .timeout(const Duration(seconds: 4));
    if (res.statusCode != 200) return [];
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final models = data['models'] as List? ?? [];
    return models.map((m) => m['name'] as String).toList();
  }

  Future<List<String>> _listMlxModels() async {
    // MLX OpenAI-compatible /v1/models endpoint
    final res = await http
        .get(Uri.parse('$mlxUrl/v1/models'))
        .timeout(const Duration(seconds: 4));
    if (res.statusCode != 200) return [];
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final models = data['data'] as List? ?? [];
    return models.map((m) => m['id'] as String).toList();
  }

  // ─── Ulanish tekshiruvi ───────────────────────────────────────────────────

  Future<bool> isRunning() async {
    try {
      if (backendType == BackendType.ollama) {
        final res = await http
            .get(Uri.parse('$ollamaUrl/api/tags'))
            .timeout(const Duration(seconds: 3));
        return res.statusCode == 200;
      } else {
        final res = await http
            .get(Uri.parse('$mlxUrl/v1/models'))
            .timeout(const Duration(seconds: 3));
        return res.statusCode == 200;
      }
    } catch (_) {
      return false;
    }
  }

  // Backend almashtirish va tekshirish
  Future<({bool running, List<String> models})> testBackend({
    required BackendType type,
    required String url,
  }) async {
    final old = backendType;
    final oldOllama = ollamaUrl;
    final oldMlx = mlxUrl;
    try {
      backendType = type;
      if (type == BackendType.ollama) {
        ollamaUrl = url;
      } else {
        mlxUrl = url;
      }
      final running = await isRunning();
      final models = running ? await listModels() : <String>[];
      return (running: running, models: models);
    } finally {
      // Muvaffaqiyatsiz bo'lsa qaytarish
      backendType = old;
      ollamaUrl = oldOllama;
      mlxUrl = oldMlx;
    }
  }

  // ─── Token oqimi ─────────────────────────────────────────────────────────

  Stream<String> streamChat({
    required String model,
    required List<Message> messages,
    String? systemPrompt,
    double temperature = 0.7,
  }) async* {
    if (backendType == BackendType.ollama) {
      yield* _streamOllama(model: model, messages: messages, systemPrompt: systemPrompt, temperature: temperature);
    } else {
      yield* _streamMlx(model: model, messages: messages, systemPrompt: systemPrompt, temperature: temperature);
    }
  }

  // Ollama NDJSON format — /api/chat
  Stream<String> _streamOllama({
    required String model,
    required List<Message> messages,
    String? systemPrompt,
    double temperature = 0.7,
  }) async* {
    final ollamaMessages = _buildMessages(messages, systemPrompt);

    final body = jsonEncode({
      'model': model,
      'messages': ollamaMessages,
      'stream': true,
      'options': {
        'temperature': temperature,
        'num_ctx': 8192,
        'repeat_penalty': 1.3,
        'repeat_last_n': 128,
      },
    });

    final request = http.Request('POST', Uri.parse('$ollamaUrl/api/chat'));
    request.headers['Content-Type'] = 'application/json';
    request.body = body;

    final response = await _client.send(request);
    if (response.statusCode != 200) {
      final err = await response.stream.bytesToString();
      throw Exception('Ollama error ${response.statusCode}: $err');
    }

    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final line in lines) {
      if (line.isEmpty) continue;
      try {
        final data = jsonDecode(line) as Map<String, dynamic>;
        final msg = data['message'] as Map<String, dynamic>?;
        if (msg != null) {
          final token = msg['content'] as String? ?? '';
          if (token.isNotEmpty) yield token;
        }
        if (data['done'] == true) break;
      } catch (_) {}
    }
  }

  // MLX OpenAI-compatible SSE format — /v1/chat/completions
  Stream<String> _streamMlx({
    required String model,
    required List<Message> messages,
    String? systemPrompt,
    double temperature = 0.7,
  }) async* {
    final mlxMessages = _buildMessages(messages, systemPrompt);

    final body = jsonEncode({
      'model': model,
      'messages': mlxMessages,
      'stream': true,
      'temperature': temperature,
      'max_tokens': 2048,
      'repetition_penalty': 1.3,
      'repetition_context_size': 128,
    });

    final request =
        http.Request('POST', Uri.parse('$mlxUrl/v1/chat/completions'));
    request.headers['Content-Type'] = 'application/json';
    request.body = body;

    final response = await _client.send(request);
    if (response.statusCode != 200) {
      final err = await response.stream.bytesToString();
      throw Exception('MLX error ${response.statusCode}: $err');
    }

    final lines = response.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final line in lines) {
      if (line.isEmpty || line == 'data: [DONE]') continue;
      if (!line.startsWith('data: ')) continue;
      try {
        final json = line.substring(6); // 'data: ' dan keyingi qism
        final data = jsonDecode(json) as Map<String, dynamic>;
        final choices = data['choices'] as List?;
        if (choices == null || choices.isEmpty) continue;
        final delta = choices[0]['delta'] as Map<String, dynamic>?;
        final token = delta?['content'] as String? ?? '';
        if (token.isNotEmpty) yield token;
        if (choices[0]['finish_reason'] != null) break;
      } catch (_) {}
    }
  }

  List<Map<String, dynamic>> _buildMessages(
      List<Message> messages, String? systemPrompt) {
    final result = <Map<String, dynamic>>[];
    if (systemPrompt != null) {
      result.add({'role': 'system', 'content': systemPrompt});
    }
    for (final msg in messages) {
      if (msg.role == MessageRole.system) continue;
      result.add({
        'role': _roleStr(msg.role),
        'content': msg.content,
      });
    }
    return result;
  }

  String _roleStr(MessageRole role) => switch (role) {
        MessageRole.user => 'user',
        MessageRole.assistant => 'assistant',
        MessageRole.tool => 'tool',
        MessageRole.system => 'system',
      };
}
