class ToolCall {
  final String name;
  final Map<String, String> args;
  final String? result;
  bool expanded;

  ToolCall({
    required this.name,
    required this.args,
    this.result,
    this.expanded = false,
  });

  factory ToolCall.fromJson(Map<String, dynamic> json) => ToolCall(
        name: json['name'] as String,
        args: Map<String, String>.from(json['args'] as Map? ?? {}),
        result: json['result'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'args': args,
        'result': result,
      };
}

class ParsedAction {
  final String name;
  final Map<String, String> args;
  final int startIndex;
  final int endIndex;

  ParsedAction({
    required this.name,
    required this.args,
    required this.startIndex,
    required this.endIndex,
  });
}
