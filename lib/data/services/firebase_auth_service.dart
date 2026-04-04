import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../core/errors/app_exception.dart';
import '../../core/logging/app_logger.dart';
import '../../core/network/api_response.dart';

class FirebaseAuthService {
  final FirebaseAuth _auth;
  final GoogleSignIn _googleSignIn;

  FirebaseAuthService({
    FirebaseAuth? auth,
    GoogleSignIn? googleSignIn,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _googleSignIn = googleSignIn ?? GoogleSignIn();

  Stream<User?> get authStateStream => _auth.authStateChanges();

  User? get currentUser => _auth.currentUser;

  Future<String?> getIdToken({bool forceRefresh = false}) async {
    try {
      return await _auth.currentUser?.getIdToken(forceRefresh);
    } catch (e) {
      AppLogger.error('Failed to get ID token', error: e, tag: 'FirebaseAuthService');
      return null;
    }
  }

  Future<Result<User>> signInWithGoogle() async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        return Result.failure(AppException.authCancelled());
      }

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCredential = await _auth.signInWithCredential(credential);
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
    } catch (e, st) {
      AppLogger.error('Google sign-in failed', error: e, stackTrace: st, tag: 'FirebaseAuthService');
      return Result.failure(AppException.authFailed(e, st));
    }
  }

  Future<Result<void>> signOut() async {
    try {
      await Future.wait([
        _auth.signOut(),
        _googleSignIn.signOut(),
      ]);
      AppLogger.info('Sign-out successful', tag: 'FirebaseAuthService');
      return const Result.success(null);
    } catch (e, st) {
      AppLogger.error('Sign-out failed', error: e, stackTrace: st, tag: 'FirebaseAuthService');
      return Result.failure(AppException.unexpected(e.toString(), error: e, stackTrace: st));
    }
  }

  bool get isSignedIn => _auth.currentUser != null;
}
