import 'dart:async';

import '../../core/logging/app_logger.dart';
import '../../core/network/connectivity_service.dart';
import '../../data/repositories/agent_suggestion_pills_repository.dart';
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
  final AgentSuggestionPillsRepository _suggestionPillsRepository;

  List<String> _suggestionPills = const [];

  AgentViewModel({
    required String agentId,
    required BackendApiService backendService,
    required ConnectivityService connectivityService,
    required ChatRepository chatRepository,
    required ChatBackupService chatBackupService,
    required FeedbackService feedbackService,
    required AgentSuggestionPillsRepository suggestionPillsRepository,
  })  : _agentId = agentId,
        _suggestionPillsRepository = suggestionPillsRepository,
        super(
          backendService: backendService,
          connectivityService: connectivityService,
          chatRepository: chatRepository,
          chatBackupService: chatBackupService,
          feedbackService: feedbackService,
        );

  @override
  String get agentId => _agentId;

  List<String> get suggestionPills => _suggestionPills;

  @override
  Future<void> initializeSession() async {
    try {
      final sessionId = await chatRepository.getOrCreateAgentSession(_agentId);
      await switchSession(sessionId);
      unawaited(_fetchAndLoadSuggestionPills());
    } catch (e) {
      AppLogger.error(
        'Failed to init agent session',
        error: e,
        tag: 'AgentViewModel',
        metadata: {'agentId': _agentId},
      );
    }
  }

  Future<void> _fetchAndLoadSuggestionPills() async {
    final uid = userId;
    if (uid == null) return;
    final pills = await _suggestionPillsRepository
        .fetchSuggestionPillsForAgent(uid, _agentId);
    if (pills.isEmpty) return;
    _suggestionPills = pills;
    safeNotifyListeners();
  }
}
