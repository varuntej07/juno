import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/local/app_database.dart';
import '../../../data/models/voice_models.dart';
import '../../../data/repositories/chat_repository.dart';
import '../../viewmodels/auth_viewmodel.dart';
import '../../viewmodels/home_viewmodel.dart';
import '../settings/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late final AnimationController _breathController;
  late final Animation<double> _breathAnimation;
  late final AnimationController _rippleController;
  late final Animation<double> _rippleAnimation;

  @override
  void initState() {
    super.initState();

    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _breathAnimation = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _breathController, curve: Curves.easeInOut),
    );

    _rippleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
    _rippleAnimation = Tween<double>(begin: 1.0, end: 1.5).animate(
      CurvedAnimation(parent: _rippleController, curve: Curves.easeOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final uid = context.read<AuthViewModel>().user?.uid;
      final vm = context.read<HomeViewModel>();

      // Engagement taps → fresh Buddy chat with pre-loaded context
      vm.onEngagementTap = (payload) {
        context.push(
          '/chat/new',
          extra: {
            'engagementId': payload.engagementId,
            'agentContext': payload.agentContext,
            'initialMessage': payload.initialMessage,
          },
        );
      };

      // Agent nudge taps -> the specific agent's chat thread
      vm.onAgentNudgeTap = (payload) {
        context.push(
          '/agents/${payload.agentId}',
          extra: payload.chatOpener.isNotEmpty ? payload.chatOpener : null,
        );
      };

      if (uid != null && uid.isNotEmpty) {
        await vm.initWakeWord(uid);
      }
    });
  }

  @override
  void dispose() {
    _breathController.dispose();
    _rippleController.dispose();
    super.dispose();
  }

  String get _uid => context.read<AuthViewModel>().user?.uid ?? 'anonymous';

  Future<void> _handleMicTap() async {
    final vm = context.read<HomeViewModel>();
    if (vm.hasActiveSession) {
      await vm.endSession();
    } else {
      await vm.startSession(_uid);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: AppColors.background,
      drawer: _ChatDrawer(
        onNewChat: () {
          Navigator.of(context).pop();
          context.push('/chat/new');
        },
        onSelectSession: (sessionId) {
          Navigator.of(context).pop();
          context.push('/chat/$sessionId');
        },
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Top bar — hamburger only
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                children: [
                  _IconButton(
                    icon: Icons.menu_rounded,
                    onTap: () => _scaffoldKey.currentState?.openDrawer(),
                  ),
                  const Spacer(),
                  _IconButton(
                    icon: Icons.settings_outlined,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    ),
                  ),
                ],
              ),
            ),

            // Transcript overlay — only visible during an active voice session
            Consumer<HomeViewModel>(
              builder: (_, vm, __) {
                if (!vm.hasActiveSession) return const SizedBox.shrink();
                return _VoiceStatusCard(vm: vm);
              },
            ),

            const Spacer(),

            // Centered mic button
            Consumer<HomeViewModel>(
              builder: (_, vm, __) => _VoiceButton(
                micState: vm.micState,
                voiceStatus: vm.voiceStatus,
                breathAnimation: _breathAnimation,
                rippleAnimation: _rippleAnimation,
                onTap: _handleMicTap,
              ),
            ),

            const SizedBox(height: 64),
          ],
        ),
      ),
    );
  }
}

// ── Voice button ─────────────────────────────────────────────────────────────

class _VoiceButton extends StatelessWidget {
  final MicState micState;
  final VoiceSessionStatus voiceStatus;
  final Animation<double> breathAnimation;
  final Animation<double> rippleAnimation;
  final VoidCallback onTap;

  const _VoiceButton({
    required this.micState,
    required this.voiceStatus,
    required this.breathAnimation,
    required this.rippleAnimation,
    required this.onTap,
  });

  Color get _color {
    return switch (micState) {
      MicState.idle => AppColors.micIdle,
      MicState.listening => AppColors.micListening,
      MicState.processing => AppColors.micProcessing,
    };
  }

  String get _label {
    return switch (voiceStatus) {
      VoiceSessionStatus.connecting => 'Connecting…',
      VoiceSessionStatus.ready => 'Tap to speak',
      VoiceSessionStatus.listening => 'Listening…',
      VoiceSessionStatus.processing => 'Processing…',
      VoiceSessionStatus.speaking => 'Speaking…',
      _ => 'Tap to talk',
    };
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: Listenable.merge([breathAnimation, rippleAnimation]),
            builder: (_, __) {
              final isActive = micState != MicState.idle;
              final scale = isActive ? 1.0 : breathAnimation.value;
              return Transform.scale(
                scale: scale,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Ripple ring — visible while listening
                    if (micState == MicState.listening)
                      Transform.scale(
                        scale: rippleAnimation.value,
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _color.withValues(
                              alpha: (1 - rippleAnimation.value + 1).clamp(0, 0.25),
                            ),
                          ),
                        ),
                      ),
                    // Main button
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _color,
                        boxShadow: [
                          BoxShadow(
                            color: _color.withValues(alpha: 0.45),
                            blurRadius: 24,
                            spreadRadius: 4,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.mic_rounded,
                        color: Colors.white,
                        size: 36,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              _label,
              key: ValueKey(_label),
              style: const TextStyle(
                color: AppColors.textTertiary,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Voice status card ─────────────────────────────────────────────────────────

class _VoiceStatusCard extends StatelessWidget {
  final HomeViewModel vm;
  const _VoiceStatusCard({required this.vm});

  @override
  Widget build(BuildContext context) {
    final hasTranscript = vm.liveTranscript.trim().isNotEmpty;
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: hasTranscript
          ? Container(
              margin: const EdgeInsets.fromLTRB(20, 4, 20, 0),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: AppColors.accent.withValues(alpha: 0.2)),
              ),
              child: Text(
                vm.liveTranscript,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}

// ── Drawer ────────────────────────────────────────────────────────────────────

class _ChatDrawer extends StatelessWidget {
  final VoidCallback onNewChat;
  final void Function(String sessionId) onSelectSession;

  const _ChatDrawer({required this.onNewChat, required this.onSelectSession});

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: AppColors.surface,
      child: SafeArea(
        child: Column(
          children: [
            // Profile row
            Consumer<AuthViewModel>(
              builder: (_, authVm, __) => Padding(
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
                      child: const Icon(Icons.person_rounded,
                          color: AppColors.accent, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            authVm.user?.displayName ?? 'User',
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if ((authVm.user?.email ?? '').isNotEmpty)
                            Text(
                              authVm.user!.email!,
                              style: const TextStyle(
                                  color: AppColors.textTertiary, fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(color: AppColors.divider, height: 1),
            ListTile(
              leading:
                  const Icon(Icons.add_rounded, color: AppColors.accent),
              title: const Text('New Chat',
                  style: TextStyle(
                      color: AppColors.textPrimary, fontSize: 14)),
              onTap: onNewChat,
            ),
            const Divider(color: AppColors.divider, height: 1),
            // Recent Buddy chat sessions (agentId IS NULL)
            Expanded(
              child: _SessionList(onSelectSession: onSelectSession),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionList extends StatefulWidget {
  final void Function(String sessionId) onSelectSession;
  const _SessionList({required this.onSelectSession});

  @override
  State<_SessionList> createState() => _SessionListState();
}

class _SessionListState extends State<_SessionList> {
  List<ChatSession> _sessions = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = context.read<ChatRepository>();
    final result = await repo.loadMainSessions(limit: 25);
    result.when(
      success: (s) => setState(() {
        _sessions = s;
        _loaded = true;
      }),
      failure: (_) => setState(() => _loaded = true),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_sessions.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Text('No recent chats',
            style: TextStyle(color: AppColors.textTertiary, fontSize: 13)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            'RECENT CHATS',
            style: TextStyle(
              color: AppColors.textTertiary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _sessions.length,
            itemBuilder: (_, i) {
              final s = _sessions[i];
              final label = s.title?.isNotEmpty == true
                  ? s.title!
                  : 'Chat ${i + 1}';
              return ListTile(
                leading: const Icon(Icons.chat_bubble_outline_rounded,
                    color: AppColors.textTertiary, size: 18),
                title: Text(
                  label,
                  style: const TextStyle(
                      color: AppColors.textPrimary, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  _formatDate(s.startedAt),
                  style: const TextStyle(
                      color: AppColors.textTertiary, fontSize: 11),
                ),
                onTap: () => widget.onSelectSession(s.id),
              );
            },
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${dt.month}/${dt.day}/${dt.year}';
  }
}

// ── Reusable icon button ──────────────────────────────────────────────────────

class _IconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _IconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(icon, color: AppColors.textPrimary, size: 22),
      ),
    );
  }
}
