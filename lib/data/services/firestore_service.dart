import 'package:cloud_firestore/cloud_firestore.dart';
import '../../core/errors/app_exception.dart';
import '../../core/logging/app_logger.dart';
import '../../core/logging/latency_tracker.dart';
import '../../core/network/api_response.dart';

class FirestoreService {
  final FirebaseFirestore _firestore;

  FirestoreService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance {
    _firestore.settings = const Settings(persistenceEnabled: true);
  }

  Future<Result<T>> getDocument<T>(
    String collection,
    String docId,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    return LatencyTracker.track('firestore_get_${collection}_$docId', () async {
      try {
        final doc = await _firestore.collection(collection).doc(docId).get();
        if (!doc.exists || doc.data() == null) {
          return Result.failure(
            AppException(
              code: ErrorCode.documentNotFound,
              message: 'Document $docId not found in $collection',
            ),
          );
        }
        final data = {'id': doc.id, ...doc.data()!};
        return Result.success(fromJson(data));
      } catch (e, st) {
        AppLogger.error('Firestore get failed', error: e, stackTrace: st, tag: 'FirestoreService');
        return Result.failure(AppException.firestoreRead(e, st));
      }
    });
  }

  Future<Result<List<T>>> getCollection<T>(
    String collection,
    T Function(Map<String, dynamic>) fromJson, {
    Query<Map<String, dynamic>> Function(CollectionReference<Map<String, dynamic>>)? queryBuilder,
  }) async {
    return LatencyTracker.track('firestore_collection_$collection', () async {
      try {
        final ref = _firestore.collection(collection);
        final query = queryBuilder != null ? queryBuilder(ref) : ref;
        final snapshot = await query.get();
        final items = snapshot.docs
            .map((doc) => fromJson({'id': doc.id, ...doc.data()}))
            .toList();
        return Result.success(items);
      } catch (e, st) {
        AppLogger.error('Firestore collection read failed', error: e, stackTrace: st, tag: 'FirestoreService');
        return Result.failure(AppException.firestoreRead(e, st));
      }
    });
  }

  Future<Result<T>> setDocument<T>(
    String collection,
    String docId,
    Map<String, dynamic> data,
    T Function(Map<String, dynamic>) fromJson, {
    bool merge = true,
  }) async {
    return LatencyTracker.track('firestore_set_${collection}_$docId', () async {
      try {
        await _firestore
            .collection(collection)
            .doc(docId)
            .set(data, SetOptions(merge: merge));
        final result = await getDocument(collection, docId, fromJson);
        return result;
      } catch (e, st) {
        AppLogger.error('Firestore set failed', error: e, stackTrace: st, tag: 'FirestoreService');
        return Result.failure(AppException.firestoreWrite(e, st));
      }
    });
  }

  Future<Result<void>> updateDocument(
    String collection,
    String docId,
    Map<String, dynamic> data,
  ) async {
    return LatencyTracker.track('firestore_update_${collection}_$docId', () async {
      try {
        await _firestore.collection(collection).doc(docId).update(data);
        return const Result.success(null);
      } catch (e, st) {
        AppLogger.error('Firestore update failed', error: e, stackTrace: st, tag: 'FirestoreService');
        return Result.failure(AppException.firestoreWrite(e, st));
      }
    });
  }

  Future<Result<void>> deleteDocument(String collection, String docId) async {
    return LatencyTracker.track('firestore_delete_${collection}_$docId', () async {
      try {
        await _firestore.collection(collection).doc(docId).delete();
        return const Result.success(null);
      } catch (e, st) {
        AppLogger.error('Firestore delete failed', error: e, stackTrace: st, tag: 'FirestoreService');
        return Result.failure(AppException.firestoreWrite(e, st));
      }
    });
  }

  Future<Result<void>> batchWrite(
    List<({String collection, String docId, Map<String, dynamic> data})> writes,
  ) async {
    return LatencyTracker.track('firestore_batch_write', () async {
      try {
        final batch = _firestore.batch();
        for (final write in writes) {
          final ref = _firestore.collection(write.collection).doc(write.docId);
          batch.set(ref, write.data, SetOptions(merge: true));
        }
        await batch.commit();
        return const Result.success(null);
      } catch (e, st) {
        AppLogger.error('Firestore batch write failed', error: e, stackTrace: st, tag: 'FirestoreService');
        return Result.failure(AppException.firestoreWrite(e, st));
      }
    });
  }

  Stream<T?> documentStream<T>(
    String collection,
    String docId,
    T Function(Map<String, dynamic>) fromJson,
  ) {
    return _firestore
        .collection(collection)
        .doc(docId)
        .snapshots()
        .map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      return fromJson({'id': snap.id, ...snap.data()!});
    });
  }
}
