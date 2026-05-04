import 'chat_viewmodel.dart';

/// ViewModel for the main Buddy text-chat screen opened from the drawer.
/// Loads an existing session by [initialSessionId], or creates a new one.
class TextChatViewModel extends ChatViewModel {
  final String? initialSessionId;

  TextChatViewModel({
    this.initialSessionId,
    required super.backendService,
    required super.connectivityService,
    required super.chatRepository,
    required super.chatBackupService,
    required super.feedbackService,
  });

  @override
  String? get agentId => null;

  @override
  Future<void> initializeSession() async {
    if (initialSessionId != null) {
      await switchSession(initialSessionId!);
    } else {
      await startNewChat();
    }
  }
}
