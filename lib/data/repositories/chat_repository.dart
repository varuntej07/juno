import 'dart:async';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../../core/errors/app_exception.dart';
import '../../core/network/api_response.dart';
import '../local/app_database.dart';
import '../models/chat_message_model.dart';
import '../services/chat_backup_service.dart';

class ChatRepository {
  final AppDatabase _db;
  final ChatBackupService _chatBackupService;

  static const _uuid = Uuid();

  ChatRepository({
    required AppDatabase db,
    required ChatBackupService chatBackupService,
  })  : _db = db,
        _chatBackupService = chatBackupService;

  Future<String> createSession() async {
    final id = _uuid.v4();
    final now = DateTime.now();
    await _db.into(_db.chatSessions).insert(
          ChatSessionsCompanion.insert(
            id: id,
            startedAt: now,
            updatedAt: Value(now),
          ),
        );
    return id;
  }

  Future<Result<List<ChatSession>>> loadRecentSessions({int limit = 10}) async {
    try {
      final rows = await (_db.select(_db.chatSessions)
            ..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])
            ..limit(limit))
          .get();
      return Result.success(rows);
    } catch (e, st) {
      return Result.failure(
        AppException.unexpected(
          'Failed to load sessions',
          error: e,
          stackTrace: st,
        ),
      );
    }
  }

  Future<Result<void>> deleteSession(String sessionId) async {
    try {
      await (_db.delete(_db.chatSessions)..where((t) => t.id.equals(sessionId))).go();
      return const Result.success(null);
    } catch (e, st) {
      return Result.failure(
        AppException.unexpected(
          'Failed to delete session',
          error: e,
          stackTrace: st,
        ),
      );
    }
  }

  Future<Result<void>> saveMessage(
    ChatMessageModel msg, {
    String? userId,
  }) async {
    final sessionId = msg.sessionId;
    if (sessionId == null) {
      return Result.failure(
        AppException.unexpected('Failed to persist message: missing session id.'),
      );
    }

    try {
      await _db.transaction(() async {
        final session = await (_db.select(_db.chatSessions)
              ..where((t) => t.id.equals(sessionId)))
            .getSingleOrNull();
        if (session == null) {
          throw StateError('Chat session $sessionId not found');
        }

        final nextSequence = session.messageCount + 1;
        await _db.into(_db.chatMessages).insertOnConflictUpdate(
              ChatMessagesCompanion.insert(
                id: msg.id,
                sessionId: sessionId,
                content: msg.text,
                isUser: msg.isUser,
                channel: msg.channel.name,
                timestamp: msg.timestamp,
                sequence: Value(nextSequence),
              ),
            );

        await (_db.update(_db.chatSessions)..where((t) => t.id.equals(sessionId))).write(
          ChatSessionsCompanion(
            updatedAt: Value(msg.timestamp),
            lastMessageAt: Value(msg.timestamp),
            lastMessagePreview: Value(_previewText(msg.text)),
            messageCount: Value(nextSequence),
          ),
        );
      });

      if (userId != null && userId.isNotEmpty) {
        unawaited(
          _chatBackupService.enqueueMessageUpsert(
            userId: userId,
            sessionId: sessionId,
            messageId: msg.id,
          ),
        );
      }

      return const Result.success(null);
    } catch (e, st) {
      return Result.failure(
        AppException.unexpected(
          'Failed to persist message',
          error: e,
          stackTrace: st,
        ),
      );
    }
  }

  Future<Result<List<ChatMessageModel>>> loadMessages(
    String sessionId, {
    int limit = 50,
  }) async {
    try {
      final rows = await (_db.select(_db.chatMessages)
            ..where((t) => t.sessionId.equals(sessionId))
            ..orderBy([
              (t) => OrderingTerm.asc(t.sequence),
              (t) => OrderingTerm.asc(t.timestamp),
            ])
            ..limit(limit))
          .get();
      return Result.success(rows.map(_rowToModel).toList());
    } catch (e, st) {
      return Result.failure(
        AppException.unexpected(
          'Failed to load messages',
          error: e,
          stackTrace: st,
        ),
      );
    }
  }

  Future<Result<void>> setSessionTitle(
    String sessionId,
    String title, {
    String? userId,
  }) async {
    try {
      await (_db.update(_db.chatSessions)..where((t) => t.id.equals(sessionId))).write(
        ChatSessionsCompanion(
          title: Value(title),
          updatedAt: Value(DateTime.now()),
        ),
      );

      if (userId != null && userId.isNotEmpty) {
        unawaited(
          _chatBackupService.enqueueSessionUpsert(
            userId: userId,
            sessionId: sessionId,
          ),
        );
      }

      return const Result.success(null);
    } catch (e, st) {
      return Result.failure(
        AppException.unexpected(
          'Failed to update session title',
          error: e,
          stackTrace: st,
        ),
      );
    }
  }

  static String _previewText(String text) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= 160) {
      return normalized;
    }
    return '${normalized.substring(0, 157)}...';
  }

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
