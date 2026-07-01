import 'package:flutter/material.dart';
import '../../models/tool_call.dart';
import '../app_theme.dart';

class ToolCard extends StatefulWidget {
  final ToolCall toolCall;

  const ToolCard({super.key, required this.toolCall});

  @override
  State<ToolCard> createState() => _ToolCardState();
}

class _ToolCardState extends State<ToolCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final tc = widget.toolCall;
    final isDone = tc.result != null;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: AppColors.toolBg,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  _toolIcon(tc.name),
                  const SizedBox(width: 8),
                  Text(
                    _toolLabel(tc.name),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                  if (tc.args['path'] != null) ...[
                    const SizedBox(width: 6),
                    Text(
                      tc.args['path']!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textDim,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (!isDone)
                    const SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        valueColor: AlwaysStoppedAnimation(AppColors.accent),
                      ),
                    )
                  else
                    Icon(
                      Icons.check_circle_outline,
                      size: 14,
                      color: AppColors.green,
                    ),
                  const SizedBox(width: 6),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 14,
                    color: AppColors.textDim,
                  ),
                ],
              ),
            ),
          ),

          // Expanded content
          if (_expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (tc.args.isNotEmpty) ...[
                    const Text(
                      'Input',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textDim,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    for (final e in tc.args.entries)
                      _argRow(e.key, e.value),
                  ],
                  if (tc.result != null) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Output',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textDim,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.bg,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        tc.result!.length > 500
                            ? '${tc.result!.substring(0, 500)}...'
                            : tc.result!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.text,
                          fontFamily: 'monospace',
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _argRow(String key, String value) {
    final displayValue = value.length > 200 ? '${value.substring(0, 200)}…' : value;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              key,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textDim,
                fontFamily: 'monospace',
              ),
            ),
          ),
          Expanded(
            child: Text(
              displayValue,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.text,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _toolIcon(String name) {
    final (icon, color) = switch (name) {
      'write_file' => (Icons.edit_document, AppColors.accent),
      'read_file' => (Icons.description_outlined, AppColors.textDim),
      'edit_file' => (Icons.find_replace, AppColors.yellow),
      'delete_file' => (Icons.delete_outline, AppColors.red),
      'list_files' => (Icons.folder_outlined, AppColors.textDim),
      'run_bash' => (Icons.terminal, AppColors.green),
      'calc' => (Icons.calculate_outlined, AppColors.textDim),
      _ => (Icons.build_outlined, AppColors.textDim),
    };
    return Icon(icon, size: 14, color: color);
  }

  String _toolLabel(String name) {
    return switch (name) {
      'write_file' => 'Write File',
      'read_file' => 'Read File',
      'edit_file' => 'Edit File',
      'delete_file' => 'Delete File',
      'list_files' => 'List Files',
      'run_bash' => 'Run Command',
      'calc' => 'Calculate',
      _ => name,
    };
  }
}
