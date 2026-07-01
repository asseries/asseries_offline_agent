import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/conversation.dart';
import '../../providers/chat_provider.dart';
import '../../services/ollama_service.dart';
import '../app_theme.dart';
import '../widgets/canvas_panel.dart';
import '../widgets/chat_view.dart';
import '../widgets/composer.dart';
import '../widgets/settings_dialog.dart';
import '../widgets/sidebar.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(chatProvider);
    final notifier = ref.read(chatProvider.notifier);
    final settings = ref.watch(settingsProvider);
    final convo = state.active;

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Row(
        children: [
          // Sidebar
          const Sidebar(),
          const VerticalDivider(width: 1),

          // Main content
          Expanded(
            child: Column(
              children: [
                // Header
                _ChatHeader(convo: convo, notifier: notifier, settings: settings),
                const Divider(height: 1),

                // Body (messages + optional canvas)
                Expanded(
                  child: Row(
                    children: [
                      // Chat area
                      Expanded(
                        child: Column(
                          children: [
                            const Expanded(child: ChatView()),
                            const Composer(),
                          ],
                        ),
                      ),

                      // Canvas panel
                      if (convo?.canvasOpen == true) ...[
                        const VerticalDivider(width: 1),
                        const CanvasPanel(),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatHeader extends StatelessWidget {
  final Conversation? convo;
  final ChatNotifier notifier;
  final AppSettings settings;

  const _ChatHeader({
    required this.convo,
    required this.notifier,
    required this.settings,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          // Title + tanlangan papka nomi
          Expanded(
            child: Row(
              children: [
                Flexible(
                  flex: 2,
                  child: Text(
                    convo?.title ?? 'Aida — Offline AI Agent',
                    style: const TextStyle(
                      color: AppColors.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (convo?.customWorkspacePath != null) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Tooltip(
                      message: convo!.customWorkspacePath!,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.12),
                          border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.folder, size: 11, color: AppColors.accent),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                convo!.customWorkspacePath!.split('/').where((s) => s.isNotEmpty).last,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.accent,
                                  fontWeight: FontWeight.w500,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Mode toggle (only when conversation is active)
          if (convo != null) ...[
            _ModeToggle(convo: convo!, notifier: notifier),
            const SizedBox(width: 8),

            // Canvas toggle (only in code mode)
            if (convo!.mode == AgentMode.code)
              Tooltip(
                message: convo!.canvasOpen ? 'Close files' : 'Open files',
                child: InkWell(
                  onTap: notifier.toggleCanvas,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: convo!.canvasOpen
                          ? AppColors.accent.withValues(alpha: 0.15)
                          : Colors.transparent,
                      border: Border.all(
                        color: convo!.canvasOpen
                            ? AppColors.accent.withValues(alpha: 0.4)
                            : AppColors.border,
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.folder_outlined,
                          size: 13,
                          color: convo!.canvasOpen
                              ? AppColors.accent
                              : AppColors.textDim,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          'Files',
                          style: TextStyle(
                            fontSize: 12,
                            color: convo!.canvasOpen
                                ? AppColors.accent
                                : AppColors.textDim,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            const SizedBox(width: 8),
          ],

          // Backend status + settings
          Consumer(builder: (ctx, ref, _) {
            final s = ref.watch(settingsProvider);
            final backendLabel = s.backendType == BackendType.ollama ? 'Ollama' : 'MLX';
            return Row(
              children: [
                // Status chip
                Tooltip(
                  message: s.ollamaRunning
                      ? '$backendLabel ulandi — ${s.model}'
                      : '$backendLabel offline',
                  child: InkWell(
                    onTap: () => ref.read(settingsProvider.notifier).refresh(),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceHigh,
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: s.ollamaRunning ? AppColors.green : AppColors.red,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            s.ollamaRunning
                                ? '$backendLabel • ${s.model}'
                                : '$backendLabel offline',
                            style: const TextStyle(
                                fontSize: 11, color: AppColors.textDim),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // Settings button
                Tooltip(
                  message: 'Sozlamalar',
                  child: InkWell(
                    onTap: () => showDialog(
                      context: ctx,
                      builder: (_) => const SettingsDialog(),
                    ),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceHigh,
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.settings_outlined,
                          size: 14, color: AppColors.textDim),
                    ),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  final Conversation convo;
  final ChatNotifier notifier;

  const _ModeToggle({required this.convo, required this.notifier});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _toggle('Chat', Icons.chat_bubble_outline, AgentMode.chat),
          _toggle('Code', Icons.code, AgentMode.code),
        ],
      ),
    );
  }

  Widget _toggle(String label, IconData icon, AgentMode mode) {
    final isActive = convo.mode == mode;
    return GestureDetector(
      onTap: () => notifier.setMode(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isActive ? AppColors.surfaceHigh : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            Icon(icon, size: 13,
                color: isActive ? AppColors.text : AppColors.textDim),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: isActive ? AppColors.text : AppColors.textDim,
                fontWeight: isActive ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
