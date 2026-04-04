import 'package:firebase_auth/firebase_auth.dart';
import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/logging/app_logger.dart';
import '../../core/network/api_response.dart';
import '../models/user_model.dart';
import '../services/firebase_auth_service.dart';
import '../services/firestore_service.dart';

class AuthRepository {
  final FirebaseAuthService _authService;
  final FirestoreService _firestoreService;

  AuthRepository({
    required FirebaseAuthService authService,
    required FirestoreService firestoreService,
  })  : _authService = authService,
        _firestoreService = firestoreService;

  Stream<User?> get authStateStream => _authService.authStateStream;

  User? get currentFirebaseUser => _authService.currentUser;

  Future<Result<UserModel>> signInWithGoogle() async {
    final authResult = await _authService.signInWithGoogle();
    return authResult.when(
      success: (user) async {
        return _getOrCreateUser(user);
      },
      failure: (error) => Future.value(Result.failure(error)),
    );
  }

  Future<Result<UserModel>> _getOrCreateUser(User firebaseUser) async {
    final existingResult = await _firestoreService.getDocument(
      AppConstants.usersCollection,
      firebaseUser.uid,
      UserModel.fromJson,
    );

    return existingResult.when(
      success: (user) async {
        final updated = user.copyWith(lastActiveAt: DateTime.now());
        await _firestoreService.updateDocument(
          AppConstants.usersCollection,
          firebaseUser.uid,
          {'last_active_at': DateTime.now().toUtc().toIso8601String()},
        );
        return Result.success(updated);
      },
      failure: (error) async {
        if (error.code == ErrorCode.documentNotFound) {
          return _createUser(firebaseUser);
        }
        return Result.failure(error);
      },
    );
  }

  Future<Result<UserModel>> _createUser(User firebaseUser) async {
    final now = DateTime.now();
    final user = UserModel(
      uid: firebaseUser.uid,
      displayName: firebaseUser.displayName ?? 'User',
      email: firebaseUser.email ?? '',
      photoUrl: firebaseUser.photoURL,
      settings: UserSettings.defaults(),
      createdAt: now,
      lastActiveAt: now,
    );

    AppLogger.info(
      'Creating new user document',
      tag: 'AuthRepository',
      metadata: {'uid': firebaseUser.uid},
    );

    final json = user.toJson();
    json.remove('id'); // Firestore uses doc ID separately

    final result = await _firestoreService.setDocument(
      AppConstants.usersCollection,
      firebaseUser.uid,
      json,
      UserModel.fromJson,
    );

    return result;
  }

  Future<Result<UserModel?>> getCurrentUser() async {
    final firebaseUser = _authService.currentUser;
    if (firebaseUser == null) return const Result.success(null);

    final result = await _firestoreService.getDocument(
      AppConstants.usersCollection,
      firebaseUser.uid,
      UserModel.fromJson,
    );

    return result.when(
      success: (user) => Result.success(user),
      failure: (error) {
        if (error.code == ErrorCode.documentNotFound) {
          return const Result.success(null);
        }
        return Result.failure(error);
      },
    );
  }

  Future<Result<void>> signOut() async {
    return _authService.signOut();
  }

  Future<String?> getIdToken() => _authService.getIdToken();
}
