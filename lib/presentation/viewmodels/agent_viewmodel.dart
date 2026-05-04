import '../../core/logging/app_logger.dart';
import '../../core/network/connectivity_service.dart';
import '../../data/repositories/chat_repository.dart';
import '../../data/services/backend_api_service.dart';
import '../../data/services/chat_backup_service.dart';
import '../../data/services/feedback_service.dart';
import 'chat_viewmodel.dart';

/// ViewModel for a per-agent chat thread.
/// Each agent has exactly one persistent session; this ViewModel loads or
/// creates it on init. [agentId] is injected into every API request so
/// the backend applies the correct persona and memory context.
class AgentViewModel extends ChatViewModel {
  final String _agentId;

  AgentViewModel({
    required String agentId,
    required BackendApiService backendService,
    required ConnectivityService connectivityService,
    required ChatRepository chatRepository,
    required ChatBackupService chatBackupService,
    required FeedbackService feedbackService,
  })  : _agentId = agentId,
        super(
          backendService: backendService,
          connectivityService: connectivityService,
          chatRepository: chatRepository,
          chatBackupService: chatBackupService,
          feedbackService: feedbackService,
        );

  @override
  String get agentId => _agentId;

  @override
  Future<void> initializeSession() async {
    try {
      final sessionId = await chatRepository.getOrCreateAgentSession(_agentId);
      await switchSession(sessionId);
    } catch (e) {
      AppLogger.error(
        'Failed to init agent session',
        error: e,
        tag: 'AgentViewModel',
        metadata: {'agentId': _agentId},
      );
    }
  }
}
