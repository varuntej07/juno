import '../../core/constants/app_constants.dart';
import '../../core/network/api_response.dart';
import '../models/reminder_model.dart';
import '../services/firestore_service.dart';

class ReminderRepository {
  final FirestoreService _firestoreService;

  ReminderRepository({required FirestoreService firestoreService})
      : _firestoreService = firestoreService;

  String _userCollection(String userId) =>
      '${AppConstants.usersCollection}/$userId/${AppConstants.remindersCollection}';

  Future<Result<List<ReminderModel>>> getReminders(
    String userId, {
    ReminderStatus? status,
  }) async {
    return _firestoreService.getCollection(
      _userCollection(userId),
      ReminderModel.fromJson,
      queryBuilder: status != null
          ? (ref) => ref
              .where('status', isEqualTo: status.name)
              .orderBy('trigger_at')
          : (ref) => ref.orderBy('trigger_at'),
    );
  }

  Future<Result<ReminderModel>> getReminder(
    String userId,
    String reminderId,
  ) async {
    return _firestoreService.getDocument(
      _userCollection(userId),
      reminderId,
      ReminderModel.fromJson,
    );
  }

  Future<Result<ReminderModel>> saveReminder(
    String userId,
    ReminderModel reminder,
  ) async {
    final data = reminder.toJson();
    data.remove('id');
    return _firestoreService.setDocument(
      _userCollection(userId),
      reminder.id,
      data,
      ReminderModel.fromJson,
    );
  }

  Future<Result<void>> updateStatus(
    String userId,
    String reminderId,
    ReminderStatus status, {
    DateTime? firedAt,
    DateTime? dismissedAt,
  }) async {
    final updates = <String, dynamic>{'status': status.name};
    if (firedAt != null) updates['fired_at'] = firedAt.toUtc().toIso8601String();
    if (dismissedAt != null) {
      updates['dismissed_at'] = dismissedAt.toUtc().toIso8601String();
    }
    return _firestoreService.updateDocument(
      _userCollection(userId),
      reminderId,
      updates,
    );
  }

  Future<Result<void>> deleteReminder(
    String userId,
    String reminderId,
  ) async {
    return _firestoreService.deleteDocument(_userCollection(userId), reminderId);
  }
}
