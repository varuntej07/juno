import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/errors/error_handler.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/local/app_database.dart';
import '../../../data/models/chat_message_model.dart';
import '../../../data/models/voice_models.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/home_viewmodel.dart';
import '../../widgets/error_display.dart';
import '../../widgets/juno_response_bubble.dart';
import '../../widgets/juno_text_field.dart';
import '../../widgets/loading_indicator.dart';
import '../reminders/reminders_screen.dart';
import '../settings/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Restore chat history and start wake word after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final homeVm = context.read<HomeViewModel>();
        final uid = context.read<AuthViewModel>().user?.uid;
        // Load last session's messages before any network calls.
        await homeVm.initSession(uid);
        if (uid != null && uid.isNotEmpty) {
          await homeVm.initWakeWord(uid);
        }
      } catch (e, st) {
        // Exceptions in postFrameCallback are otherwise silently swallowed.
        ErrorHandler.handle(e, st);
      }
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  String get _userId => context.read<AuthViewModel>().user?.uid ?? 'anonymous';

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: AppConstants.animationDuration,
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleSend() async {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    _textController.clear();
    await context.read<HomeViewModel>().sendMessage(text, _userId);
    _scrollToBottom();
  }

  Future<void> _handleMicTap() async {
    final homeVm = context.read<HomeViewModel>();
    if (!homeVm.hasActiveVoiceSession) {
      await homeVm.startVoiceSession(_userId);
      return;
    }

    if (homeVm.isVoiceCaptureAvailable && homeVm.micState == MicState.listening) {
      await homeVm.stopVoiceSession();
      return;
    }

    await homeVm.cancelVoiceSession();
  }

  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
  }

  Future<void> _handleNewChat() async {
    Navigator.of(context).pop();
    await context.read<HomeViewModel>().createNewChat();
  }

  Future<void> _handleSelectSession(String sessionId) async {
    Navigator.of(context).pop();
    await context.read<HomeViewModel>().switchSession(sessionId);
    _scrollToBottom();
  }

  void _handleRetry(String messageId) {
    final homeVm = context.read<HomeViewModel>();
    homeVm.retryLastResponse(messageId);
    _scrollToBottom();
  }

  void _handleEdit(String messageId, String newText) {
    final homeVm = context.read<HomeViewModel>();
    homeVm.editAndResend(messageId, newText);
    _scrollToBottom();
  }

  void _handleFeedback(String messageId, MessageFeedback? feedback) {
    context.read<HomeViewModel>().setFeedback(messageId, feedback);
  }

  void _handleViewReminders() {
    Navigator.push(context, RemindersScreen.route(context));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: Consumer2<HomeViewModel, AuthViewModel>(
        builder: (context, homeVm, authVm, _) {
          return _HomeDrawer(
            userName: authVm.user?.displayName ?? 'User',
            userEmail: authVm.user?.email ?? '',
            sessions: homeVm.sessions,
            currentSessionId: homeVm.currentSessionId,
            onNewChat: _handleNewChat,
            onSelectSession: _handleSelectSession,
          );
        },
      ),
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _AppBar(
              onMenuTap: () => _scaffoldKey.currentState?.openDrawer(),
              onSettingsTap: _openSettings,
            ),
            _OfflineBanner(),
            const _VoiceStatusBanner(),
            Expanded(
              child: Consumer<HomeViewModel>(
                builder: (context, vm, _) {
                  if (vm.messages.isEmpty && vm.streamingAssistantText.isEmpty) {
                    return _EmptyState(
                      pulseAnimation: _pulseAnimation,
                      micState: vm.micState,
                      voiceStatus: vm.voiceStatus,
                      onMicTap: () {
                        _handleMicTap();
                      },
                    );
                  }
                  return _MessageList(
                    messages: vm.messages,
                    streamingAssistantText: vm.streamingAssistantText,
                    scrollController: _scrollController,
                    isLoading: vm.state == ViewState.loading,
                    onRetry: _handleRetry,
                    onEdit: _handleEdit,
                    onFeedback: _handleFeedback,
                    onViewReminders: _handleViewReminders,
                  );
                },
              ),
            ),
            Consumer<HomeViewModel>(
              builder: (context, vm, _) {
                if (vm.error != null) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: ErrorDisplay(
                      error: vm.error!,
                      onDismiss: vm.clearError,
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
            _InputArea(
              controller: _textController,
              onSend: () {
                _handleSend();
              },
              onMicTap: () {
                _handleMicTap();
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _AppBar extends StatelessWidget {
  final VoidCallback onMenuTap;
  final VoidCallback onSettingsTap;

  const _AppBar({
    required this.onMenuTap,
    required this.onSettingsTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          InkWell(
            onTap: onMenuTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(
                Icons.menu_rounded,
                color: AppColors.textPrimary,
                size: 22,
              ),
            ),
          ),
          const Expanded(
            child: Center(
              child: Text(
                'Juno',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          InkWell(
            onTap: onSettingsTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: const Icon(
                Icons.settings_outlined,
                color: AppColors.textSecondary,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final isOffline = context.watch<HomeViewModel>().isOffline;
    if (!isOffline) return const SizedBox.shrink();
    return InlineErrorBanner(message: 'No internet connection');
  }
}

class _VoiceStatusBanner extends StatelessWidget {
  const _VoiceStatusBanner();

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<HomeViewModel>();
    if (!vm.hasActiveVoiceSession) return const SizedBox.shrink();

    final title = switch (vm.voiceStatus) {
      VoiceSessionStatus.connecting => 'Connecting live voice session…',
      VoiceSessionStatus.ready => 'Live voice session ready',
      VoiceSessionStatus.listening => 'Listening for live audio…',
      VoiceSessionStatus.processing => 'Nova Sonic is processing…',
      VoiceSessionStatus.speaking => 'Nova Sonic is responding…',
      _ => 'Live voice session active',
    };

    final subtitle = vm.isVoiceCaptureAvailable
        ? 'Mic capture is active for this session.'
        : 'Type into the input field to exercise the live Nova Sonic path.';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final Animation<double> pulseAnimation;
  final MicState micState;
  final VoiceSessionStatus voiceStatus;
  final VoidCallback onMicTap;

  const _EmptyState({
    required this.pulseAnimation,
    required this.micState,
    required this.voiceStatus,
    required this.onMicTap,
  });

  String get _label {
    if (voiceStatus == VoiceSessionStatus.connecting) {
      return 'Connecting…';
    }
    if (voiceStatus == VoiceSessionStatus.ready) {
      return 'Live session ready';
    }
    return switch (micState) {
      MicState.idle => 'Tap to start a live Nova Sonic session',
      MicState.listening => 'Listening…',
      MicState.processing => 'Processing…',
    };
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MicButton(
            animation: pulseAnimation,
            micState: micState,
            onTap: onMicTap,
          ),
          const SizedBox(height: 20),
          Text(
            _label,
            style: const TextStyle(
              color: AppColors.textTertiary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _MicButton extends StatelessWidget {
  final Animation<double> animation;
  final MicState micState;
  final VoidCallback onTap;

  const _MicButton({
    required this.animation,
    required this.micState,
    required this.onTap,
  });

  Color get _buttonColor {
    switch (micState) {
      case MicState.idle:
        return AppColors.micIdle;
      case MicState.listening:
        return AppColors.micListening;
      case MicState.processing:
        return AppColors.micProcessing;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, child) {
          final scale = micState == MicState.listening ? animation.value : 1.0;
          return Transform.scale(
            scale: scale,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (micState != MicState.idle)
                  Container(
                    width: AppConstants.micButtonSize + 24,
                    height: AppConstants.micButtonSize + 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _buttonColor.withValues(
                        alpha: micState == MicState.listening
                            ? 0.15 * animation.value
                            : 0.1,
                      ),
                    ),
                  ),
                Container(
                  width: AppConstants.micButtonSize,
                  height: AppConstants.micButtonSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _buttonColor,
                    boxShadow: [
                      BoxShadow(
                        color: _buttonColor.withValues(alpha: 0.4),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.mic_rounded,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  final List<ChatMessageModel> messages;
  final String streamingAssistantText;
  final ScrollController scrollController;
  final bool isLoading;
  final OnRetry onRetry;
  final OnEdit onEdit;
  final OnFeedback onFeedback;
  final VoidCallback onViewReminders;

  const _MessageList({
    required this.messages,
    required this.streamingAssistantText,
    required this.scrollController,
    required this.isLoading,
    required this.onRetry,
    required this.onEdit,
    required this.onFeedback,
    required this.onViewReminders,
  });

  @override
  Widget build(BuildContext context) {
    final draftVisible = streamingAssistantText.trim().isNotEmpty;
    final totalItems = messages.length + (isLoading ? 1 : 0) + (draftVisible ? 1 : 0);

    // Find the index of the last assistant message for retry visibility
    int lastAssistantIndex = -1;
    for (var i = messages.length - 1; i >= 0; i--) {
      if (!messages[i].isUser) {
        lastAssistantIndex = i;
        break;
      }
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: totalItems,
      itemBuilder: (context, index) {
        if (index < messages.length) {
          final msg = messages[index];
          return JunoResponseBubble(
            message: msg,
            isLastAssistantMessage: index == lastAssistantIndex,
            onRetry: onRetry,
            onEdit: onEdit,
            onFeedback: onFeedback,
            onViewReminders: onViewReminders,
          );
        }

        final afterMessagesIndex = index - messages.length;
        if (draftVisible && afterMessagesIndex == 0) {
          return JunoResponseBubble(
            message: ChatMessageModel(
              id: 'draft',
              text: streamingAssistantText,
              isUser: false,
              timestamp: DateTime.now(),
              channel: ChatMessageChannel.voice,
            ),
          );
        }

        return const Padding(
          padding: EdgeInsets.all(12),
          child: Align(
            alignment: Alignment.centerLeft,
            child: LoadingIndicator(size: 20),
          ),
        );
      },
    );
  }
}

class _HomeDrawer extends StatelessWidget {
  final String userName;
  final String userEmail;
  final List<ChatSession> sessions;
  final String? currentSessionId;
  final VoidCallback onNewChat;
  final void Function(String sessionId) onSelectSession;

  const _HomeDrawer({
    required this.userName,
    required this.userEmail,
    required this.sessions,
    required this.currentSessionId,
    required this.onNewChat,
    required this.onSelectSession,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.surface,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.person_rounded,
                      color: AppColors.accent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          userName,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (userEmail.isNotEmpty)
                          Text(
                            userEmail,
                            style: const TextStyle(
                              color: AppColors.textTertiary,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const Divider(color: AppColors.divider, height: 1),
            ListTile(
              leading: const Icon(Icons.add_rounded, color: AppColors.accent),
              title: const Text(
                'New Chat',
                style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
              ),
              onTap: onNewChat,
            ),
            const Divider(color: AppColors.divider, height: 1),
            if (sessions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Recent Chats',
                    style: const TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            Expanded(
              child: ListView.builder(
                itemCount: sessions.length,
                itemBuilder: (context, index) {
                  final session = sessions[index];
                  final isSelected = session.id == currentSessionId;
                  final label = session.title?.isNotEmpty == true
                      ? session.title!
                      : 'Chat ${index + 1}';
                  return ListTile(
                    selected: isSelected,
                    selectedTileColor: AppColors.accent.withValues(alpha: 0.08),
                    leading: Icon(
                      Icons.chat_bubble_outline_rounded,
                      color: isSelected ? AppColors.accent : AppColors.textTertiary,
                      size: 18,
                    ),
                    title: Text(
                      label,
                      style: TextStyle(
                        color: isSelected ? AppColors.accent : AppColors.textPrimary,
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      _formatDate(session.startedAt),
                      style: const TextStyle(
                        color: AppColors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                    onTap: () => onSelectSession(session.id),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${dt.month}/${dt.day}/${dt.year}';
  }
}

class _InputArea extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onMicTap;

  const _InputArea({
    required this.controller,
    required this.onSend,
    required this.onMicTap,
  });

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<HomeViewModel>();
    final isLoading = vm.state == ViewState.loading;
    final micDisabled = isLoading && !vm.hasActiveVoiceSession;
    final hint = vm.hasActiveVoiceSession
        ? 'Send text into the live Nova Sonic session...'
        : 'Ask Juno anything...';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: micDisabled ? null : onMicTap,
            child: Opacity(
              opacity: micDisabled ? 0.4 : 1.0,
              child: Container(
                width: 48,
                height: 48,
                margin: const EdgeInsets.only(right: 12),
                decoration: BoxDecoration(
                  color: vm.hasActiveVoiceSession
                      ? AppColors.micProcessing
                      : AppColors.surface,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: vm.hasActiveVoiceSession
                        ? AppColors.micProcessing.withValues(alpha: 0.5)
                        : AppColors.border,
                  ),
                ),
                child: Icon(
                  vm.hasActiveVoiceSession ? Icons.stop_rounded : Icons.mic_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ),
          Expanded(
            child: JunoTextField(
              controller: controller,
              hint: hint,
              enabled: !isLoading,
              onSend: onSend,
              onSubmitted: (_) => onSend(),
            ),
          ),
        ],
      ),
    );
  }
}
