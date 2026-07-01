import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/conversation.dart';
import '../../providers/chat_provider.dart';
import '../app_theme.dart';

class Composer extends ConsumerStatefulWidget {
  const Composer({super.key});

  @override
  ConsumerState<Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<Composer> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  bool _hasText = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _send() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;

    final state = ref.read(chatProvider);
    final notifier = ref.read(chatProvider.notifier);
    final settings = ref.read(settingsProvider);

    // If no active conversation, create one
    if (state.active == null) {
      notifier.newConversation(AgentMode.chat);
    }

    _ctrl.clear();
    setState(() => _hasText = false);

    notifier.sendMessage(text: text, model: settings.model);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatProvider);
    final notifier = ref.read(chatProvider.notifier);
    final isStreaming = state.isStreaming;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(
                color: _focus.hasFocus ? AppColors.accent : AppColors.border,
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                // Text field
                KeyboardListener(
                  focusNode: FocusNode(),
                  onKeyEvent: (e) {
                    if (e is KeyDownEvent &&
                        e.logicalKey == LogicalKeyboardKey.enter &&
                        !HardwareKeyboard.instance.isShiftPressed &&
                        !isStreaming) {
                      _send();
                    }
                  },
                  child: TextField(
                    controller: _ctrl,
                    focusNode: _focus,
                    enabled: !isStreaming,
                    maxLines: null,
                    minLines: 1,
                    style: const TextStyle(
                      color: AppColors.textBright,
                      fontSize: 14,
                      height: 1.6,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Message Aida… (Enter to send, Shift+Enter for new line)',
                      hintStyle: TextStyle(color: AppColors.textDim, fontSize: 14),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    onChanged: (v) => setState(() => _hasText = v.isNotEmpty),
                  ),
                ),

                // Bottom toolbar
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                  child: Row(
                    children: [
                      // Model info
                      Consumer(builder: (ctx, ref, _) {
                        final settings = ref.watch(settingsProvider);
                        return GestureDetector(
                          onTap: () => _showModelPicker(context, ref),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceHigh,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: settings.ollamaRunning
                                        ? AppColors.green
                                        : AppColors.red,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  settings.model,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppColors.textDim,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.arrow_drop_down,
                                    size: 14, color: AppColors.textDim),
                              ],
                            ),
                          ),
                        );
                      }),

                      const Spacer(),

                      // Stop / Send button
                      if (isStreaming)
                        _CircleBtn(
                          icon: Icons.stop,
                          color: AppColors.red,
                          tooltip: 'Stop',
                          onTap: notifier.stopStreaming,
                        )
                      else
                        _CircleBtn(
                          icon: Icons.arrow_upward,
                          color: _hasText ? AppColors.accent : AppColors.border,
                          tooltip: 'Send',
                          onTap: _hasText ? _send : null,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 6),
          const Text(
            'Aida can make mistakes. Verify important information.',
            style: TextStyle(fontSize: 11, color: AppColors.textDim),
          ),
        ],
      ),
    );
  }

  void _showModelPicker(BuildContext context, WidgetRef ref) {
    final settings = ref.read(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border),
        ),
        title: const Text('Select Model',
            style: TextStyle(color: AppColors.textBright, fontSize: 16)),
        content: SizedBox(
          width: 300,
          child: settings.availableModels.isEmpty
              ? const Text(
                  'No models found. Make sure Ollama is running.',
                  style: TextStyle(color: AppColors.textDim),
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: settings.availableModels
                      .map((m) => InkWell(
                            onTap: () {
                              notifier.setModel(m);
                              Navigator.pop(ctx);
                            },
                            borderRadius: BorderRadius.circular(6),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              child: Row(
                                children: [
                                  Icon(
                                    settings.model == m
                                        ? Icons.radio_button_checked
                                        : Icons.radio_button_unchecked,
                                    size: 16,
                                    color: settings.model == m
                                        ? AppColors.accent
                                        : AppColors.textDim,
                                  ),
                                  const SizedBox(width: 10),
                                  Text(m,
                                      style: const TextStyle(
                                          color: AppColors.text, fontSize: 13)),
                                ],
                              ),
                            ),
                          ))
                      .toList(),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textDim)),
          ),
        ],
      ),
    );
  }
}

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback? onTap;

  const _CircleBtn({
    required this.icon,
    required this.color,
    required this.tooltip,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: onTap != null ? color : AppColors.surfaceHigh,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 16, color: Colors.white),
        ),
      ),
    );
  }
}
