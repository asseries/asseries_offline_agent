import 'dart:async';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/tool_call.dart';
import 'ollama_service.dart';
import 'tools.dart';
import 'workspace_service.dart';

// Events emitted by the agent loop
sealed class AgentEvent {}

class TokenEvent extends AgentEvent {
  final String token;
  final String fullText; // safe portion of accumulated text
  TokenEvent({required this.token, required this.fullText});
}

class ThinkingEvent extends AgentEvent {
  final String content;
  ThinkingEvent(this.content);
}

class ActivityEvent extends AgentEvent {
  final ActivityType type;
  final String? label;
  ActivityEvent({required this.type, this.label});
}

class ToolStartEvent extends AgentEvent {
  final ParsedAction action;
  ToolStartEvent(this.action);
}

class ToolDoneEvent extends AgentEvent {
  final ParsedAction action;
  final String result;
  ToolDoneEvent({required this.action, required this.result});
}

class DoneEvent extends AgentEvent {}

class ErrorEvent extends AgentEvent {
  final String error;
  ErrorEvent(this.error);
}

// ─── Agent Loop ─────────────────────────────────────────────────────────────

Stream<AgentEvent> runAgentLoop({
  required String conversationId,
  required List<Message> history,
  required String userMessage,
  required AgentMode mode,
  required String model,
  required OllamaService ollama,
  required WorkspaceService workspace,
}) async* {
  final int maxRounds = mode == AgentMode.code ? 40 : 6;
  // Kod rejimida pastroq temperature — model "gapirib" emas, tool chaqirib
  // ishlashga ko'proq moyil bo'ladi (gemma-chat ham shunday qilgan)
  final double temperature = mode == AgentMode.code ? 0.3 : 0.7;
  int rounds = 0;
  bool anyToolCalledThisTurn = false;
  bool nudgeUsed = false; // bitta marta avtomatik eslatma berish limiti

  // Build the working messages list (exclude system messages from history)
  final List<Message> messages = history
      .where((m) => m.role != MessageRole.system)
      .toList();
  messages.add(Message.user(userMessage));

  // Get system prompt
  String systemPrompt;
  if (mode == AgentMode.code) {
    final wsPath = await workspace.getWorkspacePath(conversationId);
    final isUserProject = workspace.getCustomPath(conversationId) != null;
    final existingFiles = await workspace.listFiles(conversationId);
    systemPrompt = codeSystemPrompt(
      wsPath,
      isUserProject: isUserProject,
      existingFiles: existingFiles,
    );
  } else {
    systemPrompt = chatSystemPrompt();
  }

  while (rounds < maxRounds) {
    rounds++;

    String accumulated = '';
    String? thinkingContent;
    bool actionTriggeredBreak = false; // tool topilib break bo'ldimi

    yield ActivityEvent(type: ActivityType.thinking);

    try {
      await for (final token in ollama.streamChat(
        model: model,
        messages: messages,
        systemPrompt: systemPrompt,
        temperature: temperature,
      )) {
        accumulated += token;

        // Parse <think> / <thinking> blocks (for Qwen2.5 thinking mode)
        final think = _extractThinking(accumulated);
        if (think.thinking != null && think.thinking != thinkingContent) {
          thinkingContent = think.thinking;
          yield ThinkingEvent(thinkingContent!);
        }

        // Find safe boundary to display (don't emit partial <action> tags)
        final safeText = think.visible;
        final safe = findSafeBoundary(safeText);
        final visible = safeText.substring(0, safe);

        yield TokenEvent(token: token, fullText: visible);

        // Repetition loop'ni aniqlab to'xtatish — model parametrlari yetarli
        // bo'lmasa ham (repetition_penalty), bu oxirgi himoya chizig'i
        if (_isRepeatingLoop(visible)) {
          yield DoneEvent();
          return;
        }

        // Check if a complete action is available
        final action = findNextAction(accumulated);
        if (action != null) {
          // Emit the text before the action
          final preActionText = accumulated.substring(0, action.startIndex).trim();

          // Signal tool execution
          yield ActivityEvent(type: ActivityType.running, label: action.name);
          yield ToolStartEvent(action);

          // Execute the tool
          final result = await executeTool(action, conversationId, workspace);

          yield ToolDoneEvent(action: action, result: result);

          // Add assistant's text + tool result to messages
          if (preActionText.isNotEmpty) {
            messages.add(Message.assistant(content: preActionText, done: true));
          }

          // Add the XML action itself as part of assistant message for context
          final actionBlock = accumulated.substring(action.startIndex, action.endIndex);
          messages.add(Message.assistant(content: actionBlock, done: true));

          // Add tool result
          messages.add(Message.tool(result, action.name));

          // Reset for next round
          accumulated = accumulated.substring(action.endIndex).trim();
          anyToolCalledThisTurn = true;

          // Restart the stream — keyingi turga o'tish kerak
          actionTriggeredBreak = true;
          break;
        }
      }

      // Faqat stream TABIIY tugagan bo'lsa (action topilib break bo'lmagan
      // bo'lsa) tekshiramiz — aks holda keyingi turga o'tamiz (while davom etadi)
      if (!actionTriggeredBreak) {
        final action = findNextAction(accumulated);
        if (action == null) {
          // Kod rejimida model hech qanday tool chaqirmasdan "gapirib"
          // tugatdi — bir marta eslatma berib avtomatik qayta urinamiz
          if (mode == AgentMode.code && !anyToolCalledThisTurn && !nudgeUsed) {
            nudgeUsed = true;
            if (accumulated.isNotEmpty) {
              messages.add(Message.assistant(content: accumulated, done: true));
            }
            messages.add(Message.user(
              'You described a plan but did not call any tool. Stop explaining '
              'and immediately write the actual code now using a write_file '
              'action — do not describe what you will do, just do it.',
            ));
            continue; // while tsikli davom etadi — yangi tur boshlanadi
          }
          yield DoneEvent();
          return;
        }
      }
    } catch (e) {
      yield ErrorEvent(e.toString());
      return;
    }
  }

  // Reached max rounds
  yield DoneEvent();
}

// ─── Repetition Loop Detector ────────────────────────────────────────────────
// Model bir xil paragraf/jumlani qaytarib generatsiya qilishni boshlasa,
// buni aniqlab to'xtatadi (repetition_penalty model tomonida ishlamasa ham).

bool _isRepeatingLoop(String text) {
  const windowSize = 80; // tekshiriladigan oxirgi bo'lak uzunligi
  const minRepeats = 3; // kamida shuncha marta qatorma-qator takrorlansa

  if (text.length < windowSize * minRepeats) return false;

  final tail = text.substring(text.length - windowSize);
  if (tail.trim().isEmpty) return false;

  // Oxirgi qismda tail necha marta uchraydi tekshiramiz — start index 0 dan
  // past tushmasligi uchun clamp qilamiz
  final searchStart =
      (text.length - windowSize * (minRepeats + 1)).clamp(0, text.length);
  final searchArea = text.substring(searchStart);
  int count = 0;
  int idx = 0;
  while (true) {
    final found = searchArea.indexOf(tail, idx);
    if (found == -1) break;
    count++;
    idx = found + windowSize;
  }
  return count >= minRepeats;
}

// ─── Thinking Block Parser ───────────────────────────────────────────────────

class _ThinkResult {
  final String visible;
  final String? thinking;
  _ThinkResult({required this.visible, this.thinking});
}

_ThinkResult _extractThinking(String text) {
  final patterns = [
    (RegExp(r'<think>([\s\S]*?)</think>', caseSensitive: false), 'think'),
    (RegExp(r'<thinking>([\s\S]*?)</thinking>', caseSensitive: false), 'thinking'),
  ];

  String thinking = '';
  String visible = text;

  for (final (re, _) in patterns) {
    for (final m in re.allMatches(text)) {
      thinking += m.group(1) ?? '';
      visible = visible.replaceFirst(m.group(0)!, '');
    }
  }

  // Check for unclosed <think> tag
  final openRe = RegExp(r'<think(?:ing)?>(.*)$', caseSensitive: false, dotAll: true);
  final openMatch = openRe.firstMatch(visible);
  if (openMatch != null && !visible.contains('</think')) {
    thinking += openMatch.group(1) ?? '';
    visible = visible.replaceFirst(openMatch.group(0)!, '');
  }

  return _ThinkResult(
    visible: visible.trim(),
    thinking: thinking.isNotEmpty ? thinking.trim() : null,
  );
}
