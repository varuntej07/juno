import 'dart:async';

import '../../core/logging/app_logger.dart';
import '../../core/network/connectivity_service.dart';
import '../../data/repositories/agent_suggestion_pills_repository.dart';
import '../../data/repositories/chat_repository.dart';
import '../../data/services/backend_api_service.dart';
import '../../data/services/chat_backup_service.dart';
import '../../data/services/chat_session_manager.dart';
import '../../data/services/feedback_service.dart';
import 'chat_viewmodel.dart';

/// ViewModel for a per-agent chat thread.
/// Uses the base session lifecycle: reuse the most recent session if empty,
/// otherwise open a fresh one (same rule as main chat). Adds suggestion pills
/// on top of the shared chat behaviour.
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
    required ChatSessionManager chatSessionManager,
    required AgentSuggestionPillsRepository suggestionPillsRepository,
  })  : _agentId = agentId,
        _suggestionPillsRepository = suggestionPillsRepository,
        super(
          backendService: backendService,
          connectivityService: connectivityService,
          chatRepository: chatRepository,
          chatBackupService: chatBackupService,
          feedbackService: feedbackService,
          chatSessionManager: chatSessionManager,
        );

  @override
  String get agentId => _agentId;

  List<String> get suggestionPills => _suggestionPills;

  @override
  Future<void> initializeSession() async {
    await super.initializeSession();
    unawaited(_fetchAndLoadSuggestionPills());
  }

  Future<void> _fetchAndLoadSuggestionPills() async {
    final uid = userId;
    if (uid == null) return;
    try {
      final pills = await _suggestionPillsRepository
          .fetchSuggestionPillsForAgent(uid, _agentId);
      if (pills.isEmpty) return;
      _suggestionPills = pills;
      safeNotifyListeners();
    } catch (e) {
      AppLogger.error(
        'Failed to load suggestion pills',
        error: e,
        tag: 'AgentViewModel',
        metadata: {'agentId': _agentId},
      );
    }
  }
}
