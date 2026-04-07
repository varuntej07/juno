import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

// ── Tables ───────────────────────────────────────────────────────────────────

/// One row per app-launch conversation. Title is set lazily from the first
/// user message so the session list can show a meaningful label.
class ChatSessions extends Table {
  TextColumn get id => text()();
  DateTimeColumn get startedAt => dateTime()();
  TextColumn get title => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Individual messages belonging to a session.
/// Cascade-deletes when the parent session is removed.
class ChatMessages extends Table {
  TextColumn get id => text()();
  TextColumn get sessionId => text().references(
        ChatSessions,
        #id,
        onDelete: KeyAction.cascade,
      )();

  /// The message body. Named 'content' to avoid conflict with Table.text().
  TextColumn get content => text()();
  BoolColumn get isUser => boolean()();

  /// 'text' | 'voice' — mirrors ChatMessageChannel.name
  TextColumn get channel => text()();
  DateTimeColumn get timestamp => dateTime()();

  @override
  Set<Column> get primaryKey => {id};
}

// ── Database ─────────────────────────────────────────────────────────────────

@DriftDatabase(tables: [ChatSessions, ChatMessages])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  /// SQLite WAL mode is enabled by drift_flutter by default; no extra setup.
  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'juno_chat');
  }
}
