import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/conversation.dart';
import '../../providers/chat_provider.dart';
import '../app_theme.dart';

class Sidebar extends ConsumerWidget {
  const Sidebar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(chatProvider);
    final notifier = ref.read(chatProvider.notifier);

    return Container(
      width: 240,
      color: AppColors.sidebarBg,
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
            child: Row(
              children: [
                // Logo
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.accent, Color(0xFF8b5cf6)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.auto_awesome, size: 16, color: Colors.white),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Aida',
                  style: TextStyle(
                    color: AppColors.textBright,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.3,
                  ),
                ),
                const Spacer(),
                // New chat button
                Tooltip(
                  message: 'New chat',
                  child: InkWell(
                    onTap: () => notifier.newConversation(AgentMode.chat),
                    borderRadius: BorderRadius.circular(6),
                    child: const Padding(
                      padding: EdgeInsets.all(4),
                      child: Icon(Icons.edit_outlined, size: 16, color: AppColors.textDim),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Mode buttons
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                _ModeChip(
                  label: 'Chat',
                  icon: Icons.chat_bubble_outline,
                  onTap: () => notifier.newConversation(AgentMode.chat),
                ),
                const SizedBox(width: 6),
                _ModeChip(
                  label: 'Code',
                  icon: Icons.code,
                  onTap: () => notifier.newConversation(AgentMode.code),
                ),
              ],
            ),
          ),

          const Divider(height: 1),
          const SizedBox(height: 4),

          // Conversation list
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              itemCount: state.conversations.length,
              itemBuilder: (ctx, i) {
                final convo = state.conversations[i];
                final isActive = convo.id == state.activeId;
                return _ConversationTile(
                  convo: convo,
                  isActive: isActive,
                  onTap: () => notifier.selectConversation(convo.id),
                  onDelete: () => notifier.deleteConversation(convo.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _ModeChip({required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 13, color: AppColors.textDim),
              const SizedBox(width: 4),
              Text(
                label,
                style: const TextStyle(
                  color: AppColors.textDim,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConversationTile extends StatefulWidget {
  final Conversation convo;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ConversationTile({
    required this.convo,
    required this.isActive,
    required this.onTap,
    required this.onDelete,
  });

  @override
  State<_ConversationTile> createState() => _ConversationTileState();
}

class _ConversationTileState extends State<_ConversationTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          margin: const EdgeInsets.symmetric(vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: widget.isActive
                ? AppColors.surfaceHigh
                : _hovered
                    ? AppColors.surface.withValues(alpha: 0.6)
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(
                widget.convo.mode == AgentMode.code
                    ? Icons.code
                    : Icons.chat_bubble_outline,
                size: 13,
                color: widget.isActive ? AppColors.accent : AppColors.textDim,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.convo.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: widget.isActive ? AppColors.textBright : AppColors.text,
                    fontWeight: widget.isActive ? FontWeight.w500 : FontWeight.normal,
                  ),
                ),
              ),
              if (_hovered || widget.isActive)
                GestureDetector(
                  onTap: widget.onDelete,
                  child: const Icon(
                    Icons.delete_outline,
                    size: 14,
                    color: AppColors.textDim,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
