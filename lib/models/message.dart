import 'tool_call.dart';

enum MessageRole { user, assistant, system, tool }

enum ActivityType { thinking, writing, running, searching }

class AgentActivity {
  final ActivityType type;
  final String? label;
  final DateTime startedAt;

  AgentActivity({required this.type, this.label, DateTime? startedAt})
      : startedAt = startedAt ?? DateTime.now();

  factory AgentActivity.fromJson(Map<String, dynamic> json) => AgentActivity(
        type: ActivityType.values.firstWhere((e) => e.name == json['type']),
        label: json['label'] as String?,
        startedAt: DateTime.fromMillisecondsSinceEpoch(json['startedAt'] as int),
      );

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'label': label,
        'startedAt': startedAt.millisecondsSinceEpoch,
      };
}

class Message {
  final String id;
  final MessageRole role;
  String content;
  final List<ToolCall> toolCalls;
  final DateTime createdAt;
  bool done;
  AgentActivity? activity;
  String? thinkingContent;

  Message({
    required this.id,
    required this.role,
    required this.content,
    List<ToolCall>? toolCalls,
    DateTime? createdAt,
    this.done = true,
    this.activity,
    this.thinkingContent,
  })  : toolCalls = toolCalls ?? [],
        createdAt = createdAt ?? DateTime.now();

  factory Message.user(String content) => Message(
        id: _uid(),
        role: MessageRole.user,
        content: content,
      );

  factory Message.assistant({String content = '', bool done = false}) => Message(
        id: _uid(),
        role: MessageRole.assistant,
        content: content,
        done: done,
      );

  factory Message.system(String content) => Message(
        id: _uid(),
        role: MessageRole.system,
        content: content,
      );

  factory Message.tool(String result, String toolName) => Message(
        id: _uid(),
        role: MessageRole.tool,
        content: result,
        toolCalls: [ToolCall(name: toolName, args: {}, result: result)],
      );

  factory Message.fromJson(Map<String, dynamic> json) => Message(
        id: json['id'] as String,
        role: MessageRole.values.firstWhere(
          (e) => e.name == json['role'],
          orElse: () => MessageRole.user,
        ),
        content: json['content'] as String,
        toolCalls: (json['toolCalls'] as List? ?? [])
            .map((t) => ToolCall.fromJson(t as Map<String, dynamic>))
            .toList(),
        createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
        done: json['done'] as bool? ?? true,
        activity: json['activity'] != null
            ? AgentActivity.fromJson(json['activity'] as Map<String, dynamic>)
            : null,
        thinkingContent: json['thinkingContent'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role.name,
        'content': content,
        'toolCalls': toolCalls.map((t) => t.toJson()).toList(),
        'createdAt': createdAt.millisecondsSinceEpoch,
        'done': done,
        'activity': activity?.toJson(),
        'thinkingContent': thinkingContent,
      };

  static int _counter = 0;
  static String _uid() => '${DateTime.now().millisecondsSinceEpoch}_${_counter++}';
}
