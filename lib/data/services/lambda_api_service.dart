import '../../core/errors/app_exception.dart';
import '../../core/logging/app_logger.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_response.dart';

class ChatResponse {
  final String text;
  final String? intent;
  final Map<String, dynamic>? metadata;

  const ChatResponse({
    required this.text,
    this.intent,
    this.metadata,
  });

  factory ChatResponse.fromJson(Map<String, dynamic> json) {
    return ChatResponse(
      text: json['text'] as String? ?? '',
      intent: json['intent'] as String?,
      metadata: json['metadata'] as Map<String, dynamic>?,
    );
  }

  factory ChatResponse.stub(String message) {
    return ChatResponse(
      text: message,
      intent: 'stub',
    );
  }
}

class LambdaApiService {
  final ApiClient? _apiClient;
  final bool _useStub;

  LambdaApiService({ApiClient? apiClient, bool useStub = false})
      : _apiClient = apiClient,
        _useStub = useStub;

  Future<Result<ChatResponse>> sendMessage(
    String message,
    String userId, {
    List<Map<String, String>> history = const [],
  }) async {
    if (_useStub || _apiClient == null) {
      AppLogger.info(
        'LambdaApiService stub: sendMessage',
        tag: 'LambdaApiService',
        metadata: {'message': message, 'history_len': history.length},
      );
      await Future.delayed(const Duration(milliseconds: 800));
      return Result.success(
        ChatResponse.stub(
          'Not connected — Lambda endpoint not configured yet. '
          'Your message: "$message"',
        ),
      );
    }

    return _apiClient.post(
      '/chat',
      {
        'message': message,
        'user_id': userId,
        if (history.isNotEmpty) 'history': history,
      },
      ChatResponse.fromJson,
    );
  }

  Future<Result<Map<String, dynamic>>> analyzeNutrition(
    String ocrText,
    String userId,
  ) async {
    if (_useStub || _apiClient == null) {
      AppLogger.info('LambdaApiService stub: analyzeNutrition', tag: 'LambdaApiService');
      return Result.failure(
        AppException(
          code: ErrorCode.unexpected,
          message: 'Nutrition analysis not yet available.',
        ),
      );
    }

    return _apiClient.post(
      '/nutrition/analyze',
      {'ocr_text': ocrText, 'user_id': userId},
      (json) => json,
    );
  }
}
