import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/errors/app_exception.dart';
import '../../core/network/api_response.dart';
import '../local/app_database.dart';
import '../models/chat_message_model.dart';

/// All chat persistence goes through this repository.
/// Callers (ViewModels) never touch AppDatabase directly.
///
/// Contract:
/// - Every method returns [Result<T>] — never throws.
/// - Write methods are fire-and-forget friendly: callers may unawaited them.
class ChatRepository {
  final AppDatabase _db;
  static const _uuid = Uuid();

  ChatRepository({required AppDatabase db}) : _db = db;

  // ── Session management ────────────────────────────────────────────────────

  /// Creates a new session and returns its id.
  Future<String> createSession() async {
    final id = _uuid.v4();
    await _db.into(_db.chatSessions).insert(
          ChatSessionsCompanion.insert(
            id: id,
            startedAt: DateTime.now(),
          ),
        );
    return id;
  }

  /// Returns up to [limit] sessions ordered newest-first.
  Future<Result<List<ChatSession>>> loadRecentSessions({int limit = 10}) async {
    try {
      final rows = await (_db.select(_db.chatSessions)
            ..orderBy([(t) => OrderingTerm.desc(t.startedAt)])
            ..limit(limit))
          .get();
      return Result.success(rows);
    } catch (e, st) {
      return Result.failure(
        AppException.unexpected('Failed to load sessions', error: e, stackTrace: st),
      );
    }
  }

  /// Deletes a session and all its messages (cascade).
  Future<Result<void>> deleteSession(String sessionId) async {
    try {
      await (_db.delete(_db.chatSessions)
            ..where((t) => t.id.equals(sessionId)))
          .go();
      return const Result.success(null);
    } catch (e, st) {
      return Result.failure(
        AppException.unexpected('Failed to delete session', error: e, stackTrace: st),
      );
    }
  }

  // ── Message CRUD ──────────────────────────────────────────────────────────

  /// Persists a single message. Safe to call with unawaited.
  Future<void> saveMessage(ChatMessageModel msg) async {
    assert(msg.sessionId != null, 'saveMessage: msg.sessionId must be set before persisting');
    await _db.into(_db.chatMessages).insertOnConflictUpdate(
          ChatMessagesCompanion.insert(
            id: msg.id,
            sessionId: msg.sessionId!,
            content: msg.text,
            isUser: msg.isUser,
            channel: msg.channel.name,
            timestamp: msg.timestamp,
          ),
        );
  }

  /// Returns the latest [limit] messages for a session, oldest-first.
  Future<Result<List<ChatMessageModel>>> loadMessages(
    String sessionId, {
    int limit = 50,
  }) async {
    try {
      final rows = await (_db.select(_db.chatMessages)
            ..where((t) => t.sessionId.equals(sessionId))
            ..orderBy([(t) => OrderingTerm.asc(t.timestamp)])
            ..limit(limit))
          .get();
      return Result.success(rows.map(_rowToModel).toList());
    } catch (e, st) {
      return Result.failure(
        AppException.unexpected('Failed to load messages', error: e, stackTrace: st),
      );
    }
  }

  // ── Session title ─────────────────────────────────────────────────────────

  /// Sets a human-readable title on a session (first user message, trimmed).
  Future<void> setSessionTitle(String sessionId, String title) async {
    await (_db.update(_db.chatSessions)
          ..where((t) => t.id.equals(sessionId)))
        .write(ChatSessionsCompanion(title: Value(title)));
  }

  // ── Private helpers ───────────────────────────────────────────────────────

  static ChatMessageModel _rowToModel(ChatMessage row) {
    return ChatMessageModel(
      id: row.id,
      text: row.content,
      isUser: row.isUser,
      timestamp: row.timestamp,
      channel: ChatMessageChannel.values.firstWhere(
        (c) => c.name == row.channel,
        orElse: () => ChatMessageChannel.text,
      ),
      sessionId: row.sessionId,
    );
  }
}
