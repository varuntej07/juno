import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../core/config/environment.dart';
import '../../core/errors/app_exception.dart';
import '../../core/logging/app_logger.dart';
import '../../core/network/api_response.dart';

class FirebaseAuthService {
  final FirebaseAuth? _auth;
  final GoogleSignIn _googleSignIn;
  Future<void>? _initialization;

  FirebaseAuthService({
    FirebaseAuth? auth,
    GoogleSignIn? googleSignIn,
  }) : _auth = auth ?? _resolveAuth(),
       _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  static FirebaseAuth? _resolveAuth() {
    try {
      if (Firebase.apps.isEmpty) return null;
      return FirebaseAuth.instance;
    } catch (_) {
      return null;
    }
  }

  Stream<User?> get authStateStream =>
      _auth?.authStateChanges() ?? const Stream<User?>.empty();

  User? get currentUser => _auth?.currentUser;

  Future<void> _ensureInitialized() {
    final existing = _initialization;
    if (existing != null) return existing;

    final future = _googleSignIn
        .initialize(serverClientId: Environment.current.googleServerClientId)
        .then((_) {
          AppLogger.info(
            'Google Sign-In initialized',
            tag: 'FirebaseAuthService',
          );
        }).catchError((Object error, StackTrace stackTrace) {
          AppLogger.error(
            'Google Sign-In initialization failed',
            error: error,
            stackTrace: stackTrace,
            tag: 'FirebaseAuthService',
          );
          throw error;
        });

    _initialization = future;
    return future;
  }

  Future<String?> getIdToken({bool forceRefresh = false}) async {
    final auth = _auth;
    if (auth == null) return null;

    try {
      return await auth.currentUser?.getIdToken(forceRefresh);
    } catch (e) {
      AppLogger.error(
        'Failed to get ID token',
        error: e,
        tag: 'FirebaseAuthService',
      );
      return null;
    }
  }

  Future<Result<User>> signInWithGoogle() async {
    final auth = _auth;
    if (auth == null) {
      return Result.failure(
        AppException.unexpected(
          'Firebase authentication is not configured for this build.',
        ),
      );
    }

    try {
      await _ensureInitialized();
      final googleUser = await _googleSignIn.authenticate();
      final googleAuth = googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );

      final userCredential = await auth.signInWithCredential(credential);
      final user = userCredential.user;
      if (user == null) {
        return Result.failure(
          AppException.authFailed(Exception('No user after sign-in')),
        );
      }

      AppLogger.info(
        'Google sign-in successful',
        tag: 'FirebaseAuthService',
        metadata: {'uid': user.uid},
      );
      return Result.success(user);
    } on GoogleSignInException catch (e, st) {
      AppLogger.error(
        'Google sign-in failed',
        error: e,
        stackTrace: st,
        tag: 'FirebaseAuthService',
      );
      if (e.code.name.toLowerCase().contains('canceled')) {
        return Result.failure(AppException.authCancelled());
      }
      return Result.failure(AppException.authFailed(e, st));
    } catch (e, st) {
      AppLogger.error(
        'Google sign-in failed',
        error: e,
        stackTrace: st,
        tag: 'FirebaseAuthService',
      );
      return Result.failure(AppException.authFailed(e, st));
    }
  }

  Future<Result<String>> requestServerAuthCode(List<String> scopes) async {
    try {
      await _ensureInitialized();
      final googleUser = await _googleSignIn.authenticate();

      final currentGrant = await googleUser.authorizationClient
          .authorizationForScopes(scopes);
      if (currentGrant == null) {
        await googleUser.authorizationClient.authorizeScopes(scopes);
      }

      final serverAuth = await googleUser.authorizationClient.authorizeServer(
        scopes,
      );
      final serverAuthCode = serverAuth?.serverAuthCode ?? '';
      if (serverAuthCode.isEmpty) {
        return Result.failure(
          AppException.unexpected(
            'Google Calendar server authorization code was not returned.',
          ),
        );
      }

      return Result.success(serverAuthCode);
    } on GoogleSignInException catch (e, st) {
      AppLogger.error(
        'Google server auth code request failed',
        error: e,
        stackTrace: st,
        tag: 'FirebaseAuthService',
      );
      if (e.code.name.toLowerCase().contains('canceled')) {
        return Result.failure(AppException.authCancelled());
      }
      return Result.failure(AppException.authFailed(e, st));
    } catch (e, st) {
      AppLogger.error(
        'Google server auth code request failed',
        error: e,
        stackTrace: st,
        tag: 'FirebaseAuthService',
      );
      return Result.failure(
        AppException.unexpected(
          'Unable to authorize Google Calendar access.',
          error: e,
          stackTrace: st,
        ),
      );
    }
  }

  Future<Result<void>> signOut() async {
    final auth = _auth;
    try {
      final signOuts = <Future<void>>[_googleSignIn.signOut()];
      if (auth != null) {
        signOuts.add(auth.signOut());
      }
      await Future.wait(signOuts).timeout(const Duration(seconds: 8));
      AppLogger.info('Sign-out successful', tag: 'FirebaseAuthService');
      return const Result.success(null);
    } catch (e, st) {
      AppLogger.error(
        'Sign-out failed',
        error: e,
        stackTrace: st,
        tag: 'FirebaseAuthService',
      );
      return Result.failure(
        AppException.unexpected(e.toString(), error: e, stackTrace: st),
      );
    }
  }

  bool get isSignedIn => _auth?.currentUser != null;
}
