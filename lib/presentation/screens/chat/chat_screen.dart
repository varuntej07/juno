import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/text_chat_viewmodel.dart';
import '../../viewmodels/view_state.dart';
import '../../widgets/chat_message_list.dart';
import '../../widgets/error_display.dart';
import '../../widgets/message_input.dart';
import '../reminders/reminders_screen.dart';

/// Full-screen Buddy text chat. Opened from the home drawer.
/// Scoped [TextChatViewModel] is provided by the router.
class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final uid = context.read<AuthViewModel>().user?.uid;
      await context.read<TextChatViewModel>().init(uid);
      _scrollToBottom();

      // Handle engagement pre-load passed as route extra
      final extra = GoRouterState.of(context).extra;
      if (extra is Map<String, dynamic> &&
          extra.containsKey('engagementId')) {
        await context.read<TextChatViewModel>().loadEngagementContext(
              engagementId: extra['engagementId'] as String,
              agentContext: extra['agentContext'] as String,
              initialMessage: extra['initialMessage'] as String,
            );
        _scrollToBottom();
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  String get _uid => context.read<AuthViewModel>().user?.uid ?? 'anonymous';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: AppColors.textPrimary, size: 20),
          onPressed: context.pop,
        ),
        title: const Text(
          'Buddy',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: SafeArea(
        child: Consumer<TextChatViewModel>(
          builder: (context, vm, _) {
            if (vm.isStreaming) {
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => _scrollToBottom());
            }

            return Column(
              children: [
                Expanded(
                  child: vm.messages.isEmpty && !vm.isStreaming
                      ? const EmptyChatPlaceholder(agentName: 'Buddy')
                      : ChatMessageList(
                          messages: vm.messages,
                          scrollController: _scrollController,
                          isStreaming: vm.isStreaming,
                          streamingText: vm.streamingText,
                          thinkingMessage: vm.thinkingMessage,
                          onRetry: vm.retryLastMessage,
                          onEdit: vm.editAndResend,
                          onFeedback: vm.setFeedback,
                          onViewReminders: () => Navigator.push(
                            context,
                            RemindersScreen.route(context),
                          ),
                          onClarificationSubmit: vm.submitClarification,
                        ),
                ),
                if (vm.error != null)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: ErrorDisplay(
                      error: vm.error!,
                      onDismiss: vm.clearError,
                    ),
                  ),
                MessageInput(
                  isLoading: vm.state == ViewState.loading,
                  hint: 'Ask Buddy anything…',
                  onSend: (text) {
                    vm.sendMessage(text, _uid);
                    _scrollToBottom();
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
