import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/home_viewmodel.dart';
import '../../widgets/error_display.dart';
import '../../widgets/juno_response_bubble.dart';
import '../../widgets/juno_text_field.dart';
import '../../widgets/loading_indicator.dart';
import '../settings/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with TickerProviderStateMixin {
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
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

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

  void _handleSend() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;

    final authVm = context.read<AuthViewModel>();
    final homeVm = context.read<HomeViewModel>();
    final userId = authVm.user?.uid ?? 'anonymous';

    _textController.clear();
    homeVm.sendMessage(text, userId).then((_) => _scrollToBottom());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _AppBar(),
            _OfflineBanner(),
            Expanded(
              child: Consumer<HomeViewModel>(
                builder: (context, vm, _) {
                  if (vm.messages.isEmpty) {
                    return _EmptyState(
                      pulseAnimation: _pulseAnimation,
                      micState: vm.micState,
                      onMicTap: () {},
                    );
                  }
                  return _MessageList(
                    messages: vm.messages,
                    scrollController: _scrollController,
                    isLoading: vm.state == ViewState.loading,
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
              onSend: _handleSend,
              pulseAnimation: _pulseAnimation,
            ),
          ],
        ),
      ),
    );
  }
}

class _AppBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthViewModel>().user;
    final initial = user?.displayName.isNotEmpty == true
        ? user!.displayName[0].toUpperCase()
        : '?';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: AppColors.accent,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
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
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
            child: const Icon(
              Icons.settings_outlined,
              color: AppColors.textSecondary,
              size: 22,
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

class _EmptyState extends StatelessWidget {
  final Animation<double> pulseAnimation;
  final MicState micState;
  final VoidCallback onMicTap;

  const _EmptyState({
    required this.pulseAnimation,
    required this.micState,
    required this.onMicTap,
  });

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
            micState == MicState.idle
                ? 'Tap or say Hey Juno'
                : micState == MicState.listening
                    ? 'Listening...'
                    : 'Processing...',
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
  final List<ChatMessage> messages;
  final ScrollController scrollController;
  final bool isLoading;

  const _MessageList({
    required this.messages,
    required this.scrollController,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: messages.length + (isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == messages.length) {
          return const Padding(
            padding: EdgeInsets.all(12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: LoadingIndicator(size: 20),
            ),
          );
        }
        return JunoResponseBubble(message: messages[index]);
      },
    );
  }
}

class _InputArea extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSend;
  final Animation<double> pulseAnimation;

  const _InputArea({
    required this.controller,
    required this.onSend,
    required this.pulseAnimation,
  });

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<HomeViewModel>();
    final isLoading = vm.state == ViewState.loading;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: JunoTextField(
              controller: controller,
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
