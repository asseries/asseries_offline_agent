import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../../models/message.dart';
import '../app_theme.dart';
import 'tool_card.dart';

class MessageBubble extends StatefulWidget {
  final Message message;
  final bool isLast;
  final VoidCallback? onRegenerate;

  const MessageBubble({
    super.key,
    required this.message,
    this.isLast = false,
    this.onRegenerate,
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  bool _hovered = false;
  bool _thinkingExpanded = false;

  @override
  Widget build(BuildContext context) {
    final msg = widget.message;

    if (msg.role == MessageRole.user) {
      return _UserBubble(message: msg);
    }

    if (msg.role == MessageRole.system || msg.role == MessageRole.tool) {
      return const SizedBox.shrink();
    }

    // Assistant message
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Aida avatar
            Container(
              width: 28,
              height: 28,
              margin: const EdgeInsets.only(top: 2, right: 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.accent, Color(0xFF8b5cf6)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.auto_awesome, size: 14, color: Colors.white),
            ),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Activity indicator
                  if (msg.activity != null) _ActivityBar(activity: msg.activity!),

                  // Thinking block
                  if (msg.thinkingContent != null && msg.thinkingContent!.isNotEmpty)
                    _ThinkingBlock(
                      content: msg.thinkingContent!,
                      expanded: _thinkingExpanded,
                      onToggle: () =>
                          setState(() => _thinkingExpanded = !_thinkingExpanded),
                    ),

                  // Main content
                  if (msg.content.isNotEmpty)
                    MarkdownBody(
                      data: msg.content,
                      styleSheet: _mdStyle(),
                      selectable: true,
                    ),

                  // Streaming caret
                  if (!msg.done && msg.content.isNotEmpty)
                    Container(
                      width: 2,
                      height: 16,
                      margin: const EdgeInsets.only(top: 2),
                      decoration: BoxDecoration(
                        color: AppColors.text,
                        borderRadius: BorderRadius.circular(1),
                      ),
                    ),

                  // Tool calls
                  for (final tc in msg.toolCalls) ToolCard(toolCall: tc),

                  // Action buttons (visible on hover for last done message)
                  if (_hovered && msg.done && widget.isLast)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        children: [
                          _IconBtn(
                            icon: Icons.copy_outlined,
                            tooltip: 'Copy',
                            onTap: () => Clipboard.setData(
                                ClipboardData(text: msg.content)),
                          ),
                          if (widget.onRegenerate != null) ...[
                            const SizedBox(width: 4),
                            _IconBtn(
                              icon: Icons.refresh,
                              tooltip: 'Regenerate',
                              onTap: widget.onRegenerate!,
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  MarkdownStyleSheet _mdStyle() {
    const mono = TextStyle(fontFamily: 'monospace', fontSize: 13);
    return MarkdownStyleSheet(
      p: const TextStyle(color: AppColors.text, fontSize: 14, height: 1.7),
      h1: const TextStyle(color: AppColors.textBright, fontSize: 22, fontWeight: FontWeight.w700),
      h2: const TextStyle(color: AppColors.textBright, fontSize: 18, fontWeight: FontWeight.w600),
      h3: const TextStyle(color: AppColors.textBright, fontSize: 15, fontWeight: FontWeight.w600),
      code: mono.copyWith(
        color: const Color(0xFFa78bfa),
        backgroundColor: AppColors.surface,
      ),
      codeblockDecoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      codeblockPadding: const EdgeInsets.all(12),
      blockquoteDecoration: const BoxDecoration(
        border: Border(left: BorderSide(color: AppColors.border, width: 3)),
      ),
      blockquotePadding: const EdgeInsets.only(left: 12),
      listBullet: const TextStyle(color: AppColors.textDim),
      tableHead: const TextStyle(color: AppColors.textBright, fontWeight: FontWeight.w600),
      tableBody: const TextStyle(color: AppColors.text),
      tableBorder: TableBorder.all(color: AppColors.border),
      horizontalRuleDecoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
    );
  }
}

class _UserBubble extends StatelessWidget {
  final Message message;
  const _UserBubble({required this.message});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Flexible(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 560),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.userBubble,
                border: Border.all(color: AppColors.border),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(14),
                  topRight: Radius.circular(14),
                  bottomLeft: Radius.circular(14),
                  bottomRight: Radius.circular(4),
                ),
              ),
              child: SelectableText(
                message.content,
                style: const TextStyle(
                  color: AppColors.textBright,
                  fontSize: 14,
                  height: 1.6,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityBar extends StatelessWidget {
  final AgentActivity activity;
  const _ActivityBar({required this.activity});

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (activity.type) {
      ActivityType.thinking => ('Thinking…', AppColors.textDim),
      ActivityType.writing => ('Writing…', AppColors.accent),
      ActivityType.running => ('Running ${activity.label ?? ''}…', AppColors.green),
      ActivityType.searching => ('Searching…', AppColors.yellow),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: color,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ),
    );
  }
}

class _ThinkingBlock extends StatelessWidget {
  final String content;
  final bool expanded;
  final VoidCallback onToggle;

  const _ThinkingBlock({
    required this.content,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(8),
              bottom: expanded ? Radius.zero : const Radius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.psychology_outlined, size: 14, color: AppColors.textDim),
                  const SizedBox(width: 6),
                  const Text(
                    'Thinking',
                    style: TextStyle(fontSize: 12, color: AppColors.textDim),
                  ),
                  const Spacer(),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 14,
                    color: AppColors.textDim,
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                content,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textDim,
                  height: 1.6,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _IconBtn({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(icon, size: 14, color: AppColors.textDim),
        ),
      ),
    );
  }
}
