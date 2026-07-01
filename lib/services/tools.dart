import 'dart:async';
import 'dart:io';
import '../models/tool_call.dart';
import 'workspace_service.dart';

// ─── XML Action Parser (mirrors gemma-chat findNextAction) ─────────────────

ParsedAction? findNextAction(String text) {
  final lower = text.toLowerCase();
  final startIdx = lower.indexOf('<action ');
  if (startIdx == -1) return null;

  final endTag = '</action>';
  final endIdx = text.toLowerCase().indexOf(endTag, startIdx);
  if (endIdx == -1) return null;

  final fullBlock = text.substring(startIdx, endIdx + endTag.length);

  // Extract name attribute
  final nameMatch = RegExp(r'<action\s+name="([^"]+)"', caseSensitive: false)
      .firstMatch(fullBlock);
  if (nameMatch == null) return null;
  final name = nameMatch.group(1)!;

  // Extract parameters: <param>value</param>
  final args = <String, String>{};
  final paramRe = RegExp(r'<(\w+)>([\s\S]*?)<\/\1>', multiLine: true);

  // Special handling for <content> — use last </content> to survive nesting
  String blockForParams = fullBlock;
  if (name == 'write_file' || name == 'edit_file') {
    final contentStart = fullBlock.indexOf('<content>');
    final contentEnd = fullBlock.lastIndexOf('</content>');
    if (contentStart != -1 && contentEnd != -1) {
      final contentValue = fullBlock.substring(contentStart + 9, contentEnd);
      args['content'] = contentValue;
      // Remove content block to parse other params safely
      blockForParams =
          fullBlock.replaceRange(contentStart, contentEnd + 10, '');
    }
  }

  for (final m in paramRe.allMatches(blockForParams)) {
    final tag = m.group(1)!;
    final val = m.group(2)!.trim();
    if (tag != 'action') args[tag] = val;
  }

  return ParsedAction(
    name: name,
    args: args,
    startIndex: startIdx,
    endIndex: endIdx + endTag.length,
  );
}

// Find safe boundary — don't emit incomplete <action tags mid-stream
int findSafeBoundary(String text) {
  int safe = text.length;
  // Walk backwards from end to find any potential partial <action start
  for (int i = text.length - 1; i >= 0; i--) {
    if (text[i] == '<') {
      final sub = text.substring(i).toLowerCase();
      if ('action'.startsWith(sub.substring(1).replaceAll(RegExp(r'\s.*'), '')) ||
          sub.startsWith('<action')) {
        safe = i;
      }
      break;
    }
  }
  return safe;
}

// ─── Tool Execution ─────────────────────────────────────────────────────────

const List<String> _bashDenyList = [
  'rm -rf /',
  'sudo rm',
  'chmod 777 /',
  'mkfs',
  ':(){:|:&};:',
  'shutdown',
  'reboot',
  'halt',
  'poweroff',
];

const int _bashOutputLimit = 16 * 1024; // 16KB
const Duration _bashTimeout = Duration(seconds: 60);

Future<String> executeTool(
  ParsedAction action,
  String conversationId,
  WorkspaceService workspace,
) async {
  final args = action.args;

  switch (action.name) {
    case 'write_file':
      return _writeFile(args, conversationId, workspace);
    case 'read_file':
      return _readFile(args, conversationId, workspace);
    case 'edit_file':
      return _editFile(args, conversationId, workspace);
    case 'delete_file':
      return _deleteFile(args, conversationId, workspace);
    case 'list_files':
      return _listFiles(conversationId, workspace);
    case 'run_bash':
      return _runBash(args, conversationId, workspace);
    case 'calc':
      return _calc(args);
    default:
      return 'Unknown tool: ${action.name}';
  }
}

Future<String> _writeFile(
  Map<String, String> args,
  String conversationId,
  WorkspaceService ws,
) async {
  final path = args['path'];
  final content = args['content'];
  if (path == null || content == null) return 'Error: missing path or content';
  try {
    await ws.writeFile(conversationId, path, content);
    return 'File written: $path';
  } catch (e) {
    return 'Error writing file: $e';
  }
}

Future<String> _readFile(
  Map<String, String> args,
  String conversationId,
  WorkspaceService ws,
) async {
  final path = args['path'];
  if (path == null) return 'Error: missing path';
  try {
    final content = await ws.readFile(conversationId, path);
    return content;
  } catch (e) {
    return 'Error reading file: $e';
  }
}

Future<String> _editFile(
  Map<String, String> args,
  String conversationId,
  WorkspaceService ws,
) async {
  final path = args['path'];
  final oldStr = args['old'];
  final newStr = args['new'];
  if (path == null || oldStr == null || newStr == null) {
    return 'Error: missing path, old, or new';
  }
  if (oldStr.trim().isEmpty) {
    return 'Error: "old" is empty. edit_file requires the EXACT existing text '
        'to replace — you must read_file first to see the real current '
        'content before editing. Blind/guessed edits are not allowed.';
  }
  try {
    var content = await ws.readFile(conversationId, path);
    if (!content.contains(oldStr)) {
      return 'Error: the "old" text was not found in $path. This usually means '
          'you guessed the content instead of reading the actual file first. '
          'Use read_file on $path to see its real current content, then retry '
          'edit_file with text copied exactly from it.';
    }
    content = content.replaceFirst(oldStr, newStr);
    await ws.writeFile(conversationId, path, content);
    return 'File edited: $path';
  } catch (e) {
    return 'Error editing file: $e';
  }
}

Future<String> _deleteFile(
  Map<String, String> args,
  String conversationId,
  WorkspaceService ws,
) async {
  final path = args['path'];
  if (path == null) return 'Error: missing path';
  try {
    await ws.deleteFile(conversationId, path);
    return 'Deleted: $path';
  } catch (e) {
    return 'Error deleting: $e';
  }
}

Future<String> _listFiles(
  String conversationId,
  WorkspaceService ws,
) async {
  try {
    final files = await ws.listFiles(conversationId);
    if (files.isEmpty) return '(empty workspace)';
    return files.join('\n');
  } catch (e) {
    return 'Error listing files: $e';
  }
}

Future<String> _runBash(
  Map<String, String> args,
  String conversationId,
  WorkspaceService ws,
) async {
  final cmd = args['command'] ?? args['cmd'];
  if (cmd == null) return 'Error: missing command';

  // Safety check
  final cmdLower = cmd.toLowerCase();
  for (final denied in _bashDenyList) {
    if (cmdLower.contains(denied)) {
      return 'Error: command is not allowed for safety reasons';
    }
  }

  final workspacePath = await ws.getWorkspacePath(conversationId);
  try {
    final result = await Process.run(
      'bash',
      ['-c', cmd],
      workingDirectory: workspacePath,
    ).timeout(_bashTimeout);

    var stdout = result.stdout.toString();
    var stderr = result.stderr.toString();

    if (stdout.length > _bashOutputLimit) {
      stdout = '${stdout.substring(0, _bashOutputLimit)}\n[truncated]';
    }
    if (stderr.length > _bashOutputLimit) {
      stderr = '${stderr.substring(0, _bashOutputLimit)}\n[truncated]';
    }

    final combined = [
      if (stdout.isNotEmpty) stdout,
      if (stderr.isNotEmpty) 'stderr: $stderr',
    ].join('\n').trim();

    return combined.isEmpty ? '(no output, exit code: ${result.exitCode})' : combined;
  } on TimeoutException {
    return 'Error: command timed out after 60 seconds';
  } catch (e) {
    return 'Error running command: $e';
  }
}

String _calc(Map<String, String> args) {
  final expr = args['expression'] ?? args['expr'];
  if (expr == null) return 'Error: missing expression';
  try {
    // Simple safe eval for basic math
    final cleaned = expr.replaceAll(RegExp(r'[^0-9+\-*/.() ]'), '');
    return _evalExpr(cleaned).toString();
  } catch (e) {
    return 'Error: $e';
  }
}

double _evalExpr(String expr) {
  expr = expr.trim();
  // Very simple recursive descent parser for +, -, *, /
  return _parseAddSub(expr, _Pos());
}

double _parseAddSub(String expr, _Pos p) {
  double result = _parseMulDiv(expr, p);
  while (p.i < expr.length) {
    final c = expr[p.i];
    if (c == '+') {
      p.i++;
      result += _parseMulDiv(expr, p);
    } else if (c == '-') {
      p.i++;
      result -= _parseMulDiv(expr, p);
    } else {
      break;
    }
  }
  return result;
}

double _parseMulDiv(String expr, _Pos p) {
  double result = _parseAtom(expr, p);
  while (p.i < expr.length) {
    final c = expr[p.i];
    if (c == '*') {
      p.i++;
      result *= _parseAtom(expr, p);
    } else if (c == '/') {
      p.i++;
      result /= _parseAtom(expr, p);
    } else {
      break;
    }
  }
  return result;
}

double _parseAtom(String expr, _Pos p) {
  while (p.i < expr.length && expr[p.i] == ' ') {
    p.i++;
  }
  if (p.i >= expr.length) return 0;
  if (expr[p.i] == '(') {
    p.i++;
    final result = _parseAddSub(expr, p);
    if (p.i < expr.length && expr[p.i] == ')') p.i++;
    return result;
  }
  int start = p.i;
  if (expr[p.i] == '-') p.i++;
  while (p.i < expr.length && (RegExp(r'[0-9.]').hasMatch(expr[p.i]))) {
    p.i++;
  }
  return double.parse(expr.substring(start, p.i));
}

class _Pos {
  int i = 0;
}

// ─── System Prompts ─────────────────────────────────────────────────────────

String chatSystemPrompt() {
  final date = DateTime.now().toIso8601String().substring(0, 10);
  return '''You are Aida, a helpful AI assistant. You are knowledgeable, thoughtful, and concise.
Today's date: $date

When using markdown, format it clearly. Keep answers focused and useful.

You have access to tools. To use a tool, write an XML action block:
<action name="calc">
<expression>42 * 1337</expression>
</action>

Available tools: calc''';
}

String codeSystemPrompt(
  String workspacePath, {
  bool isUserProject = false,
  List<String> existingFiles = const [],
}) {
  final date = DateTime.now().toIso8601String().substring(0, 10);
  final folderName = workspacePath.split('/').where((s) => s.isNotEmpty).last;

  final locationBlock = isUserProject
      ? '''You are currently working INSIDE THE USER'S REAL PROJECT FOLDER:
  Folder name: $folderName
  Full path:   $workspacePath

This is an existing project on the user's disk — NOT a sandbox. Files you read/write/delete here are real and permanent. Always check existing files with list_files/read_file before assuming the project is empty.'''
      : '''You are working in a sandboxed workspace (no real project selected yet):
  Path: $workspacePath''';

  final filesBlock = existingFiles.isEmpty
      ? ''
      : '\n\nExisting files in this project (${existingFiles.length} shown):\n${existingFiles.take(60).map((f) => '- $f').join('\n')}'
        '${existingFiles.length > 60 ? '\n... and ${existingFiles.length - 60} more' : ''}';

  return '''You are Aida, an expert software engineer and coding assistant. You help users build complete, working applications.

Today's date: $date

$locationBlock$filesBlock

IMPORTANT: Start coding in your FIRST response. Don't ask for clarification — make reasonable assumptions and build it.
If asked what folder/project you're working in, answer with ONLY the project name "$folderName" in conversation — do NOT recite the full absolute disk path (like /Users/...) to the user, that's internal context only for your own tool calls.

To use tools, write XML action blocks:

<action name="write_file">
<path>index.html</path>
<content>
<!doctype html>
<html>...</html>
</content>
</action>

<action name="read_file">
<path>index.html</path>
</action>

<action name="edit_file">
<path>index.html</path>
<old>old text</old>
<new>new text</new>
</action>

<action name="delete_file">
<path>file.txt</path>
</action>

<action name="list_files">
</action>

<action name="run_bash">
<command>npm install</command>
</action>

<action name="calc">
<expression>100 * 1.2</expression>
</action>

Rules:
- Write complete, working code. No placeholders.
- Prefer multi-file structure for clarity.
- Always include a write_file action in your first response.
- After writing files, run_bash if needed to install deps or verify.
- Think step-by-step before implementing complex features.
- NEVER call edit_file on a file you have not just read in this conversation. Always read_file first, then copy the EXACT existing text into "old". Guessing the contents of "old" is forbidden and will fail.
- If you want to fully rewrite a file (not a small targeted change), use write_file instead of edit_file.
- Some paths ending in a name with a dot (like .xcworkspace, .xcodeproj, .app, .framework) are actually FOLDERS on disk, not files — read_file/edit_file will fail on them. If unsure whether a path is a file or folder, use list_files first.
- Avoid editing generated/boilerplate platform folders (ios/, android/, macos/, windows/, linux/, build/, .dart_tool/) unless the user specifically asks for native platform changes — for a Flutter app, almost all real work happens in lib/ and pubspec.yaml.''';
}
