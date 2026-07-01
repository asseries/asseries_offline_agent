import 'message.dart';

enum AgentMode { chat, code }

class Conversation {
  final String id;
  String title;
  final List<Message> messages;
  final DateTime createdAt;
  AgentMode mode;
  bool canvasOpen;
  String? customWorkspacePath; // foydalanuvchi tanlagan haqiqiy loyiha papkasi

  Conversation({
    required this.id,
    required this.title,
    required this.messages,
    required this.createdAt,
    this.mode = AgentMode.chat,
    this.canvasOpen = false,
    this.customWorkspacePath,
  });

  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
        id: json['id'] as String,
        title: json['title'] as String,
        messages: (json['messages'] as List)
            .map((m) => Message.fromJson(m as Map<String, dynamic>))
            .toList(),
        createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
        mode: AgentMode.values.firstWhere(
          (e) => e.name == (json['mode'] as String? ?? 'chat'),
          orElse: () => AgentMode.chat,
        ),
        canvasOpen: json['canvasOpen'] as bool? ?? false,
        customWorkspacePath: json['customWorkspacePath'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'messages': messages.map((m) => m.toJson()).toList(),
        'createdAt': createdAt.millisecondsSinceEpoch,
        'mode': mode.name,
        'canvasOpen': canvasOpen,
        'customWorkspacePath': customWorkspacePath,
      };

  Conversation copyWith({
    String? title,
    List<Message>? messages,
    AgentMode? mode,
    bool? canvasOpen,
    String? customWorkspacePath,
  }) =>
      Conversation(
        id: id,
        title: title ?? this.title,
        messages: messages ?? this.messages,
        createdAt: createdAt,
        mode: mode ?? this.mode,
        canvasOpen: canvasOpen ?? this.canvasOpen,
        customWorkspacePath: customWorkspacePath ?? this.customWorkspacePath,
      );
}
