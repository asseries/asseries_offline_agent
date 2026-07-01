import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/tool_call.dart';
import '../services/agent_loop.dart';
import '../services/ollama_service.dart';
import '../services/workspace_service.dart';
import '../storage/storage_service.dart';

final _uuid = Uuid();

// ─── Settings ───────────────────────────────────────────────────────────────

class AppSettings {
  final String model;
  final List<String> availableModels;
  final bool ollamaRunning;
  final BackendType backendType;
  final String ollamaUrl;
  final String mlxUrl;
  final bool isTestingConnection;
  final bool useLocalModel;

  const AppSettings({
    this.model = 'qwen2.5-coder:latest',
    this.availableModels = const [],
    this.ollamaRunning = false,
    this.backendType = BackendType.ollama,
    this.ollamaUrl = 'http://localhost:11434',
    this.mlxUrl = 'http://localhost:8080',
    this.isTestingConnection = false,
    this.useLocalModel = false,
  });

  String get activeUrl =>
      backendType == BackendType.ollama ? ollamaUrl : mlxUrl;

  AppSettings copyWith({
    String? model,
    List<String>? availableModels,
    bool? ollamaRunning,
    BackendType? backendType,
    String? ollamaUrl,
    String? mlxUrl,
    bool? isTestingConnection,
    bool? useLocalModel,
  }) =>
      AppSettings(
        model: model ?? this.model,
        availableModels: availableModels ?? this.availableModels,
        ollamaRunning: ollamaRunning ?? this.ollamaRunning,
        backendType: backendType ?? this.backendType,
        ollamaUrl: ollamaUrl ?? this.ollamaUrl,
        mlxUrl: mlxUrl ?? this.mlxUrl,
        isTestingConnection: isTestingConnection ?? this.isTestingConnection,
        useLocalModel: useLocalModel ?? this.useLocalModel,
      );
}

class SettingsNotifier extends StateNotifier<AppSettings> {
  final OllamaService _ollama;

  static const _kBackend = 'settings.backendType';
  static const _kOllamaUrl = 'settings.ollamaUrl';
  static const _kMlxUrl = 'settings.mlxUrl';
  static const _kModel = 'settings.model';
  static const _kUseLocal = 'settings.useLocalModel';

  SettingsNotifier(this._ollama) : super(const AppSettings()) {
    _loadAndInit();
  }

  // Bo'sh satr saqlangan bo'lsa ham standart qiymatga qaytaradi —
  // oddiy `?? default` faqat null holatda ishlaydi, "" da ishlamaydi
  String _readNonEmpty(SharedPreferences prefs, String key, String fallback) {
    final v = prefs.getString(key);
    return (v == null || v.trim().isEmpty) ? fallback : v;
  }

  Future<void> _loadAndInit() async {
    // SharedPreferences'dan saqlangan sozlamalarni o'qish
    final prefs = await SharedPreferences.getInstance();
    final backendName = _readNonEmpty(prefs, _kBackend, 'ollama');
    final backendType = backendName == 'mlx' ? BackendType.mlx : BackendType.ollama;
    final ollamaUrl = _readNonEmpty(prefs, _kOllamaUrl, 'http://localhost:11434');
    final mlxUrl = _readNonEmpty(prefs, _kMlxUrl, 'http://localhost:8080');
    final savedModel = _readNonEmpty(prefs, _kModel, 'qwen2.5-coder:latest');
    final useLocal = prefs.getBool(_kUseLocal) ?? false;

    _ollama.backendType = backendType;
    _ollama.ollamaUrl = ollamaUrl;
    _ollama.mlxUrl = mlxUrl;

    state = state.copyWith(
      backendType: backendType,
      ollamaUrl: ollamaUrl,
      mlxUrl: mlxUrl,
      model: savedModel,
      useLocalModel: useLocal,
    );

    await _refreshConnection();
  }

  Future<void> _refreshConnection() async {
    final running = await _ollama.isRunning();
    final models = running ? await _ollama.listModels() : <String>[];
    String model = state.model;
    if (models.isNotEmpty && !models.contains(model)) {
      model = models.first;
    }
    state = state.copyWith(
      ollamaRunning: running,
      availableModels: models,
      model: model,
    );
  }

  void setModel(String model) {
    state = state.copyWith(model: model);
    _persist();
  }

  // Settings sahifasidan chaqiriladi
  Future<bool> applyBackendSettings({
    required BackendType backendType,
    required String ollamaUrl,
    required String mlxUrl,
    required String model,
  }) async {
    state = state.copyWith(isTestingConnection: true);

    // Yangi sozlamalarni sinab ko'rish
    final result = await _ollama.testBackend(
      type: backendType,
      url: backendType == BackendType.ollama ? ollamaUrl : mlxUrl,
    );

    // Muvaffaqiyatli bo'lsa qo'llash
    _ollama.backendType = backendType;
    _ollama.ollamaUrl = ollamaUrl;
    _ollama.mlxUrl = mlxUrl;

    String activeModel = model;
    if (result.models.isNotEmpty && !result.models.contains(model)) {
      activeModel = result.models.first;
    }

    state = state.copyWith(
      backendType: backendType,
      ollamaUrl: ollamaUrl,
      mlxUrl: mlxUrl,
      ollamaRunning: result.running,
      availableModels: result.models,
      model: activeModel,
      isTestingConnection: false,
    );

    await _persist();
    return result.running;
  }

  // To'g'ridan-to'g'ri qo'llash — qayta test qilmasdan (dialog "Saqlash" uchun)
  Future<void> applySettingsDirect({
    required BackendType backendType,
    required String ollamaUrl,
    required String mlxUrl,
    required String model,
    required bool alreadyConnected,
    required List<String> detectedModels,
    required bool useLocalModel,
  }) async {
    _ollama.backendType = backendType;
    _ollama.ollamaUrl = ollamaUrl;
    _ollama.mlxUrl = mlxUrl;

    state = state.copyWith(
      backendType: backendType,
      ollamaUrl: ollamaUrl,
      mlxUrl: mlxUrl,
      model: model,
      ollamaRunning: alreadyConnected,
      availableModels: detectedModels,
      useLocalModel: useLocalModel,
    );

    await _persist();
  }

  Future<void> refresh() => _refreshConnection();

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kBackend, state.backendType.name);
    await prefs.setString(_kOllamaUrl, state.ollamaUrl);
    await prefs.setString(_kMlxUrl, state.mlxUrl);
    await prefs.setString(_kModel, state.model);
    await prefs.setBool(_kUseLocal, state.useLocalModel);
  }
}

final settingsProvider =
    StateNotifierProvider<SettingsNotifier, AppSettings>((ref) {
  return SettingsNotifier(OllamaService());
});

// ─── Chat State ──────────────────────────────────────────────────────────────

class ChatState {
  final List<Conversation> conversations;
  final String? activeId;
  final bool isStreaming;
  final String? selectedFile; // for canvas panel

  const ChatState({
    this.conversations = const [],
    this.activeId,
    this.isStreaming = false,
    this.selectedFile,
  });

  Conversation? get active =>
      activeId == null ? null : conversations.where((c) => c.id == activeId).firstOrNull;

  ChatState copyWith({
    List<Conversation>? conversations,
    String? activeId,
    bool? isStreaming,
    String? selectedFile,
    bool clearActive = false,
    bool clearFile = false,
  }) =>
      ChatState(
        conversations: conversations ?? this.conversations,
        activeId: clearActive ? null : (activeId ?? this.activeId),
        isStreaming: isStreaming ?? this.isStreaming,
        selectedFile: clearFile ? null : (selectedFile ?? this.selectedFile),
      );
}

class ChatNotifier extends StateNotifier<ChatState> {
  final StorageService _storage;
  final OllamaService _ollama;
  final WorkspaceService _workspace;

  ChatNotifier(this._storage, this._ollama, this._workspace)
      : super(const ChatState()) {
    _load();
  }

  Future<void> _load() async {
    final convos = await _storage.loadConversations();
    // Saqlangan custom workspace yo'llarini WorkspaceService'ga tiklaymiz
    for (final c in convos) {
      if (c.customWorkspacePath != null) {
        _workspace.setCustomPath(c.id, c.customWorkspacePath);
      }
    }
    state = state.copyWith(
      conversations: convos,
      activeId: convos.isNotEmpty ? convos.first.id : null,
    );
  }

  // Foydalanuvchi haqiqiy loyiha papkasini tanlaganda chaqiriladi
  void setCustomWorkspacePath(String? path) {
    final convo = state.active;
    if (convo == null) return;
    convo.customWorkspacePath = path;
    _workspace.setCustomPath(convo.id, path);
    _notify();
    _save();
  }

  Future<void> _save() async {
    await _storage.saveConversations(state.conversations);
  }

  // ─── Conversation management ─────────────────────────────────────────────

  void newConversation(AgentMode mode) {
    final convo = Conversation(
      id: _uuid.v4(),
      title: 'New conversation',
      messages: [],
      createdAt: DateTime.now(),
      mode: mode,
    );
    state = state.copyWith(
      conversations: [convo, ...state.conversations],
      activeId: convo.id,
    );
    _save();
  }

  void selectConversation(String id) {
    state = state.copyWith(activeId: id, clearFile: true);
  }

  void deleteConversation(String id) {
    final convos = state.conversations.where((c) => c.id != id).toList();
    String? newActive =
        state.activeId == id ? convos.firstOrNull?.id : state.activeId;
    state = state.copyWith(conversations: convos, activeId: newActive);
    _storage.deleteConversation(id);
  }

  void toggleCanvas() {
    final convo = state.active;
    if (convo == null) return;
    convo.canvasOpen = !convo.canvasOpen;
    _notify();
  }

  void setMode(AgentMode mode) {
    final convo = state.active;
    if (convo == null) return;
    convo.mode = mode;
    _notify();
    _save();
  }

  void setSelectedFile(String? path) {
    state = state.copyWith(selectedFile: path);
  }

  // ─── Messaging ───────────────────────────────────────────────────────────

  Future<void> sendMessage({
    required String text,
    required String model,
  }) async {
    final convo = state.active;
    if (convo == null || state.isStreaming) return;

    // Add user message
    convo.messages.add(Message.user(text));

    // Auto-generate title from first message
    if (convo.messages.length == 1) {
      convo.title = text.length > 40 ? '${text.substring(0, 40)}…' : text;
    }

    // Add placeholder assistant message
    final assistantMsg = Message.assistant(done: false);
    assistantMsg.activity = AgentActivity(type: ActivityType.thinking);
    convo.messages.add(assistantMsg);

    state = state.copyWith(isStreaming: true);
    _notify();

    final List<ToolCall> toolCalls = [];
    try {
      await for (final event in runAgentLoop(
        conversationId: convo.id,
        history: List.from(convo.messages)
          ..removeWhere((m) => m.id == assistantMsg.id || m.role == MessageRole.tool),
        userMessage: text,
        mode: convo.mode,
        model: model,
        ollama: _ollama,
        workspace: _workspace,
      )) {
        if (!mounted) break;

        switch (event) {
          case TokenEvent(:final fullText):
            assistantMsg.content = fullText;
            assistantMsg.activity = null;
            _notify();

          case ThinkingEvent(:final content):
            assistantMsg.thinkingContent = content;
            _notify();

          case ActivityEvent(:final type, :final label):
            assistantMsg.activity = AgentActivity(type: type, label: label);
            _notify();

          case ToolStartEvent(:final action):
            final tc = ToolCall(
              name: action.name,
              args: action.args,
            );
            toolCalls.add(tc);
            assistantMsg.toolCalls
              ..clear()
              ..addAll(toolCalls);
            _notify();

          case ToolDoneEvent(:final action, :final result):
            final tc = toolCalls.lastOrNull;
            if (tc != null && tc.name == action.name) {
              toolCalls[toolCalls.length - 1] = ToolCall(
                name: action.name,
                args: action.args,
                result: result,
              );
              assistantMsg.toolCalls
                ..clear()
                ..addAll(toolCalls);
            }
            _notify();

          case DoneEvent():
            assistantMsg.done = true;
            assistantMsg.activity = null;

          case ErrorEvent(:final error):
            assistantMsg.content = '**Error:** $error';
            assistantMsg.done = true;
            assistantMsg.activity = null;
        }
      }
    } catch (e) {
      assistantMsg.content = '**Error:** $e';
      assistantMsg.done = true;
      assistantMsg.activity = null;
    }

    state = state.copyWith(isStreaming: false);
    _notify();
    _save();
  }

  void stopStreaming() {
    // Mark last assistant message as done
    final convo = state.active;
    if (convo == null) return;
    final last = convo.messages.lastOrNull;
    if (last != null && last.role == MessageRole.assistant) {
      last.done = true;
      last.activity = null;
    }
    state = state.copyWith(isStreaming: false);
    _notify();
    _save();
  }

  void regenerateLastMessage(String model) {
    final convo = state.active;
    if (convo == null || state.isStreaming) return;

    // Remove last assistant message(s)
    while (convo.messages.isNotEmpty &&
        convo.messages.last.role == MessageRole.assistant) {
      convo.messages.removeLast();
    }

    // Get last user message
    final lastUser = convo.messages.lastOrNull;
    if (lastUser == null || lastUser.role != MessageRole.user) return;

    // Remove it too so sendMessage can re-add it
    convo.messages.removeLast();
    final userText = lastUser.content;

    _notify();
    sendMessage(text: userText, model: model);
  }

  void _notify() {
    // Trigger rebuild by creating a new list reference
    state = state.copyWith(conversations: List.from(state.conversations));
  }
}

final chatProvider = StateNotifierProvider<ChatNotifier, ChatState>((ref) {
  return ChatNotifier(
    StorageService(),
    OllamaService(),
    WorkspaceService(),
  );
});
