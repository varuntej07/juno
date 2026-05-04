import 'app_exception.dart';

class NetworkException extends AppException {
  final int? statusCode;

  const NetworkException({
    required super.code,
    required super.message,
    this.statusCode,
    super.originalError,
    super.stackTrace,
  });

  factory NetworkException.fromStatusCode(int statusCode, String body) {
    if (statusCode == 401) {
      return NetworkException(
        code: ErrorCode.unauthorized,
        message: 'Unauthorized (401)',
        statusCode: statusCode,
      );
    } else if (statusCode == 403) {
      return NetworkException(
        code: ErrorCode.forbidden,
        message: 'Forbidden (403)',
        statusCode: statusCode,
      );
    } else if (statusCode == 404) {
      return NetworkException(
        code: ErrorCode.notFound,
        message: 'Not found (404)',
        statusCode: statusCode,
      );
    } else if (statusCode == 408) {
      return NetworkException(
        code: ErrorCode.requestTimeout,
        message: 'Request timeout (408)',
        statusCode: statusCode,
      );
    } else if (statusCode == 429) {
      return NetworkException(
        code: ErrorCode.serverError,
        message: 'Too many requests (429)',
        statusCode: statusCode,
      );
    } else if (statusCode >= 500) {
      return NetworkException(
        code: ErrorCode.serverError,
        message: 'Server error ($statusCode): $body',
        statusCode: statusCode,
      );
    }
    return NetworkException(
      code: ErrorCode.unknown,
      message: 'HTTP error ($statusCode): $body',
      statusCode: statusCode,
    );
  }

  bool get isRetryable {
    final status = statusCode;
    return status == 408 ||
        status == 429 ||
        (status != null && status >= 500) ||
        code == ErrorCode.networkUnavailable ||
        code == ErrorCode.requestTimeout;
  }
}
