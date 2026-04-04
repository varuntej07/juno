import '../../core/constants/app_constants.dart';
import '../../core/network/api_response.dart';
import '../models/memory_model.dart';
import '../services/firestore_service.dart';

class MemoryRepository {
  final FirestoreService _firestoreService;

  MemoryRepository({required FirestoreService firestoreService})
      : _firestoreService = firestoreService;

  String _userCollection(String userId) =>
      '${AppConstants.usersCollection}/$userId/${AppConstants.memoriesCollection}';

  Future<Result<List<MemoryModel>>> getMemories(
    String userId, {
    MemoryCategory? category,
  }) async {
    return _firestoreService.getCollection(
      _userCollection(userId),
      MemoryModel.fromJson,
      queryBuilder: category != null
          ? (ref) => ref.where('category', isEqualTo: category.name)
          : null,
    );
  }

  Future<Result<MemoryModel>> getMemory(String userId, String memoryId) async {
    return _firestoreService.getDocument(
      _userCollection(userId),
      memoryId,
      MemoryModel.fromJson,
    );
  }

  Future<Result<MemoryModel>> saveMemory(
    String userId,
    MemoryModel memory,
  ) async {
    final data = memory.toJson();
    data.remove('id');
    return _firestoreService.setDocument(
      _userCollection(userId),
      memory.id,
      data,
      MemoryModel.fromJson,
    );
  }

  Future<Result<void>> deleteMemory(String userId, String memoryId) async {
    return _firestoreService.deleteDocument(_userCollection(userId), memoryId);
  }

  Future<Result<List<MemoryModel>>> searchMemories(
    String userId,
    String query,
  ) async {
    // Basic prefix search — full-text search via Lambda in a later session
    return _firestoreService.getCollection(
      _userCollection(userId),
      MemoryModel.fromJson,
      queryBuilder: (ref) => ref
          .orderBy('key')
          .startAt([query])
          .endAt(['$query\uf8ff'])
          .limit(20),
    );
  }
}
