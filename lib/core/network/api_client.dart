import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../constants/app_constants.dart';
import '../config/environment.dart';
import '../errors/app_exception.dart';
import '../errors/network_exception.dart';
import '../logging/app_logger.dart';
import '../logging/latency_tracker.dart';
import 'api_response.dart';
import 'connectivity_service.dart';

class ApiClient {
  final ConnectivityService _connectivity;
  final Future<String?> Function() _tokenProvider;

  ApiClient({
    required ConnectivityService connectivity,
    required Future<String?> Function() tokenProvider,
  })  : _connectivity = connectivity,
        _tokenProvider = tokenProvider;

  Future<Map<String, String>> _headers() async {
    final token = await _tokenProvider();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<Result<T>> get<T>(
    String path,
    T Function(Map<String, dynamic>) fromJson,
  ) =>
      _execute('GET', path, null, fromJson);

  Future<Result<T>> post<T>(
    String path,
    Map<String, dynamic> body,
    T Function(Map<String, dynamic>) fromJson,
  ) =>
      _execute('POST', path, body, fromJson);

  Future<Result<T>> put<T>(
    String path,
    Map<String, dynamic> body,
    T Function(Map<String, dynamic>) fromJson,
  ) =>
      _execute('PUT', path, body, fromJson);

  Future<Result<T>> delete<T>(
    String path,
    T Function(Map<String, dynamic>) fromJson,
  ) =>
      _execute('DELETE', path, null, fromJson);

  Future<Result<T>> _execute<T>(
    String method,
    String path,
    Map<String, dynamic>? body,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    if (!await _connectivity.isConnected) {
      return Result.failure(AppException.networkUnavailable());
    }

    return LatencyTracker.track('api_${method.toLowerCase()}_$path', () async {
      return _executeWithRetry(method, path, body, fromJson, 0);
    });
  }

  Future<Result<T>> _executeWithRetry<T>(
    String method,
    String path,
    Map<String, dynamic>? body,
    T Function(Map<String, dynamic>) fromJson,
    int attempt,
  ) async {
    final url = Uri.parse('${Environment.current.apiBaseUrl}$path');
    final headers = await _headers();
    final stopwatch = Stopwatch()..start();

    try {
      http.Response response;
      final timeout = AppConstants.apiReadTimeout;

      switch (method) {
        case 'GET':
          response = await http.get(url, headers: headers).timeout(timeout);
        case 'POST':
          response = await http
              .post(url, headers: headers, body: jsonEncode(body))
              .timeout(timeout);
        case 'PUT':
          response = await http
              .put(url, headers: headers, body: jsonEncode(body))
              .timeout(timeout);
        case 'DELETE':
          response = await http.delete(url, headers: headers).timeout(timeout);
        default:
          throw UnsupportedError('Unsupported HTTP method: $method');
      }

      stopwatch.stop();
      AppLogger.network(method, url.toString(), response.statusCode, stopwatch.elapsed);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        return Result.success(fromJson(json));
      }

      final networkEx = NetworkException.fromStatusCode(response.statusCode, response.body);

      if (networkEx.isRetryable && attempt < AppConstants.maxApiRetries - 1) {
        await _backoffDelay(attempt);
        return _executeWithRetry(method, path, body, fromJson, attempt + 1);
      }

      return Result.failure(networkEx);
    } on SocketException {
      return Result.failure(AppException.networkUnavailable());
    } on HttpException catch (e) {
      if (attempt < AppConstants.maxApiRetries - 1) {
        await _backoffDelay(attempt);
        return _executeWithRetry(method, path, body, fromJson, attempt + 1);
      }
      return Result.failure(AppException.unexpected(e.message, error: e));
    } catch (e) {
      return Result.failure(AppException.requestTimeout());
    }
  }

  Future<void> _backoffDelay(int attempt) async {
    final delay = Duration(
      milliseconds: AppConstants.retryBaseDelay.inMilliseconds * (1 << attempt),
    );
    await Future.delayed(delay);
  }
}
