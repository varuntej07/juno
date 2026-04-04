enum ErrorCode {
  // Network
  networkUnavailable,
  requestTimeout,
  serverError,
  unauthorized,
  forbidden,
  notFound,
  // Auth
  authFailed,
  authCancelled,
  authTokenExpired,
  // Firestore
  firestoreReadFailed,
  firestoreWriteFailed,
  documentNotFound,
  // Generic
  unexpected,
  unknown,
}

class AppException implements Exception {
  final ErrorCode code;
  final String message;
  final Object? originalError;
  final StackTrace? stackTrace;

  const AppException({
    required this.code,
    required this.message,
    this.originalError,
    this.stackTrace,
  });

  factory AppException.unexpected(String message, {Object? error, StackTrace? stackTrace}) {
    return AppException(
      code: ErrorCode.unexpected,
      message: message,
      originalError: error,
      stackTrace: stackTrace,
    );
  }

  factory AppException.networkUnavailable() {
    return const AppException(
      code: ErrorCode.networkUnavailable,
      message: 'No internet connection. Please check your network.',
    );
  }

  factory AppException.unauthorized() {
    return const AppException(
      code: ErrorCode.unauthorized,
      message: 'Authentication required. Please sign in again.',
    );
  }

  factory AppException.serverError(int statusCode, String body) {
    return AppException(
      code: ErrorCode.serverError,
      message: 'Server error ($statusCode): $body',
    );
  }

  factory AppException.requestTimeout() {
    return const AppException(
      code: ErrorCode.requestTimeout,
      message: 'Request timed out. Please try again.',
    );
  }

  factory AppException.firestoreRead(Object error, [StackTrace? st]) {
    return AppException(
      code: ErrorCode.firestoreReadFailed,
      message: 'Failed to read data.',
      originalError: error,
      stackTrace: st,
    );
  }

  factory AppException.firestoreWrite(Object error, [StackTrace? st]) {
    return AppException(
      code: ErrorCode.firestoreWriteFailed,
      message: 'Failed to save data.',
      originalError: error,
      stackTrace: st,
    );
  }

  factory AppException.authFailed(Object error, [StackTrace? st]) {
    return AppException(
      code: ErrorCode.authFailed,
      message: 'Sign-in failed. Please try again.',
      originalError: error,
      stackTrace: st,
    );
  }

  factory AppException.authCancelled() {
    return const AppException(
      code: ErrorCode.authCancelled,
      message: 'Sign-in cancelled.',
    );
  }

  @override
  String toString() => 'AppException(${code.name}): $message';
}
