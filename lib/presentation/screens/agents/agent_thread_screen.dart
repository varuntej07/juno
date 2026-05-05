import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/agent.dart';
import '../../viewmodels/agent_viewmodel.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/view_state.dart';
import '../../widgets/chat_message_list.dart';
import '../../widgets/error_display.dart';
import '../../widgets/message_input.dart';
import '../reminders/reminders_screen.dart';

/// Horizontally scrollable row of quick-start suggestion pills shown above the
/// input bar. Tapping a pill writes its text into the input field.
class _SuggestionPillsRow extends StatelessWidget {
  final List<String> pills;
  final void Function(String pill) onTap;

  const _SuggestionPillsRow({required this.pills, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: pills.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final pill = pills[i];
          return GestureDetector(
            onTap: () => onTap(pill),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppColors.divider),
              ),
              child: Text(
                pill,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Full-screen chat thread for a single agent.
/// The [AgentViewModel] is scoped to this route by the router (created on
/// push, disposed on pop) — no global state leaks between agents.
///
/// [chatOpener] is optionally provided when the screen is opened from a
/// push notification tap. If the thread has no messages yet, it is shown
/// in the empty state to surface what the agent wants to discuss.
class AgentThreadScreen extends StatefulWidget {
  final String agentId;
  final String? chatOpener;
  const AgentThreadScreen({super.key, required this.agentId, this.chatOpener});

  @override
  State<AgentThreadScreen> createState() => _AgentThreadScreenState();
}

class _AgentThreadScreenState extends State<AgentThreadScreen> {
  final _scrollController = ScrollController();
  final _inputController = TextEditingController();

  Agent get _agent =>
      kAgents.firstWhere((a) => a.id == widget.agentId,
          orElse: () => Agent(
                id: widget.agentId,
                name: widget.agentId,
                subtitle: '',
                icon: Icons.smart_toy_rounded,
                color: AppColors.accent,
              ));

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final uid = context.read<AuthViewModel>().user?.uid;
      context.read<AgentViewModel>().init(uid).then((_) => _scrollToBottom());
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _inputController.dispose();
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
    final agent = _agent;

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
        title: Row(
          children: [
            // Hero matches the tile on the agents grid — morphs on navigation
            Hero(
              tag: 'agent-icon-${agent.id}',
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: agent.color,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(agent.icon, color: Colors.white, size: 17),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  agent.name,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (agent.subtitle.isNotEmpty)
                  Text(
                    agent.subtitle,
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Consumer<AgentViewModel>(
          builder: (context, vm, _) {
            if (vm.isStreaming) {
              WidgetsBinding.instance
                  .addPostFrameCallback((_) => _scrollToBottom());
            }

            return Column(
              children: [
                Expanded(
                  child: vm.messages.isEmpty && !vm.isStreaming
                      ? EmptyChatPlaceholder(
                          agentName: agent.name,
                          initialMessage: widget.chatOpener,
                        )
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 4),
                    child: ErrorDisplay(
                      error: vm.error!,
                      onDismiss: vm.clearError,
                    ),
                  ),
                if (vm.suggestionPills.isNotEmpty && !vm.isStreaming)
                  _SuggestionPillsRow(
                    pills: vm.suggestionPills,
                    onTap: (pill) {
                      _inputController.text = pill;
                      _inputController.selection = TextSelection.collapsed(
                        offset: pill.length,
                      );
                    },
                  ),
                MessageInput(
                  isLoading: vm.state == ViewState.loading,
                  hint: 'Ask ${agent.name}…',
                  controller: _inputController,
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
