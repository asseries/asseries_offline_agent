import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/conversation.dart';
import '../../models/message.dart';
import '../../providers/chat_provider.dart';
import '../app_theme.dart';
import 'message_bubble.dart';

class ChatView extends ConsumerStatefulWidget {
  const ChatView({super.key});

  @override
  ConsumerState<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends ConsumerState<ChatView> {
  final _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(chatProvider);
    final notifier = ref.read(chatProvider.notifier);
    final settings = ref.watch(settingsProvider);

    final convo = state.active;
    if (convo == null) {
      return const _EmptyState();
    }

    final messages = convo.messages
        .where((m) => m.role != MessageRole.system)
        .toList();

    // Auto-scroll on new messages
    if (state.isStreaming) _scrollToBottom();

    if (messages.isEmpty) {
      return const _WelcomeState();
    }

    return Scrollbar(
      controller: _scrollCtrl,
      child: ListView.builder(
        controller: _scrollCtrl,
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        itemCount: messages.length,
        itemBuilder: (ctx, i) {
          final msg = messages[i];
          final isLast = i == messages.length - 1;
          return MessageBubble(
            key: ValueKey(msg.id),
            message: msg,
            isLast: isLast && msg.role == MessageRole.assistant,
            onRegenerate: isLast && msg.role == MessageRole.assistant && msg.done
                ? () => notifier.regenerateLastMessage(settings.model)
                : null,
          );
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.accent, Color(0xFF8b5cf6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.auto_awesome, size: 28, color: Colors.white),
          ),
          const SizedBox(height: 16),
          const Text(
            'Aida',
            style: TextStyle(
              color: AppColors.textBright,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your offline AI coding assistant',
            style: TextStyle(color: AppColors.textDim, fontSize: 14),
          ),
          const SizedBox(height: 24),
          const _SuggestionChips(),
        ],
      ),
    );
  }
}

class _WelcomeState extends StatelessWidget {
  const _WelcomeState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AppColors.accent, Color(0xFF8b5cf6)],
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.auto_awesome, size: 24, color: Colors.white),
          ),
          const SizedBox(height: 16),
          const Text(
            'How can I help you today?',
            style: TextStyle(
              color: AppColors.textBright,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          const _SuggestionChips(),
        ],
      ),
    );
  }
}

class _SuggestionChips extends ConsumerWidget {
  const _SuggestionChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestions = [
      ('Build a todo app', Icons.check_box_outlined),
      ('Create a landing page', Icons.web_outlined),
      ('Write a Python script', Icons.terminal),
      ('Explain async/await', Icons.help_outline),
    ];

    final notifier = ref.read(chatProvider.notifier);
    final settings = ref.read(settingsProvider);

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: suggestions.map((s) {
        return InkWell(
          onTap: () {
            if (ref.read(chatProvider).active == null) {
              notifier.newConversation(
                s.$1.contains('app') || s.$1.contains('page') || s.$1.contains('script')
                    ? AgentMode.code
                    : AgentMode.chat,
              );
            }
            notifier.sendMessage(text: s.$1, model: settings.model);
          },
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.surface,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(s.$2, size: 14, color: AppColors.textDim),
                const SizedBox(width: 6),
                Text(
                  s.$1,
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
