import '../local/app_database.dart';
import '../repositories/chat_repository.dart';

/// Owns the session lifecycle rule: open the most recent session if it is
/// empty, otherwise create a fresh one. This is the single place where
/// "what session should I open?" is decided — not in the ViewModel, not in
/// the repository.
class ChatSessionManager {
  final ChatRepository _repository;

  ChatSessionManager({required ChatRepository repository})
      : _repository = repository;

  /// Returns the session ID to use on app open or explicit "new chat".
  /// Reuses the most recent session when it has no messages (avoids
  /// populating history with empty sessions). Creates a new session otherwise.
  Future<String> getOrCreateFreshSession(String? agentId) async {
    final recent = await _repository.getMostRecentSessionForAgent(agentId);
    if (recent == null || recent.messageCount > 0) {
      return _repository.createSession(agentId: agentId);
    }
    return recent.id;
  }

  /// All sessions for this agent/chat slot, newest first. Returns empty list
  /// on any read failure so callers never need to handle errors.
  Future<List<ChatSession>> getSessionsForAgent(String? agentId) async {
    final result = await _repository.getSessionsForAgent(agentId);
    List<ChatSession> sessions = [];
    result.when(
      success: (s) => sessions = s,
      failure: (_) {},
    );
    return sessions;
  }
}
