import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../core/logging/app_logger.dart';
import '../models/chat_message_model.dart';

/// Persists like/dislike feedback on assistant messages to Firestore.
///
/// Document path: `users/{uid}/feedback/{messageId}`
/// Feedback removal (un-toggle) deletes the document.
class FeedbackService {
  final FirebaseFirestore? _firestore;

  FeedbackService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? _resolveFirestore();

  static FirebaseFirestore? _resolveFirestore() {
    try {
      if (Firebase.apps.isEmpty) return null;
      return FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  /// Saves or removes feedback for a message.
  ///
  /// When [feedback] is non-null, upserts the document.
  /// When [feedback] is null, deletes the document (user un-toggled).
  Future<void> saveFeedback({
    required String userId,
    required String messageId,
    required String sessionId,
    required MessageFeedback? feedback,
    required String messageContent,
  }) async {
    final firestore = _firestore;
    if (firestore == null) {
      AppLogger.warning(
        'FeedbackService: Firestore unavailable, skipping sync',
        tag: 'FeedbackService',
      );
      return;
    }

    final docRef = firestore
        .collection('users')
        .doc(userId)
        .collection('feedback')
        .doc(messageId);

    try {
      if (feedback == null) {
        await docRef.delete();
        AppLogger.info(
          'FeedbackService: deleted feedback',
          tag: 'FeedbackService',
          metadata: {'messageId': messageId},
        );
      } else {
        await docRef.set({
          'message_id': messageId,
          'session_id': sessionId,
          'feedback': feedback.name,
          'message_content': _truncateContent(messageContent),
          'created_at': FieldValue.serverTimestamp(),
          'updated_at': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
        AppLogger.info(
          'FeedbackService: saved feedback',
          tag: 'FeedbackService',
          metadata: {'messageId': messageId, 'feedback': feedback.name},
        );
      }
    } catch (e) {
      // Fire-and-forget: feedback sync failure should never block the UI.
      AppLogger.error(
        'FeedbackService: failed to sync feedback',
        error: e,
        tag: 'FeedbackService',
        metadata: {'messageId': messageId},
      );
    }
  }

  /// Truncate content for Firestore storage — we don't need the full response,
  /// just enough context to understand what was liked/disliked.
  static String _truncateContent(String content) {
    if (content.length <= 500) return content;
    return '${content.substring(0, 497)}...';
  }
}
