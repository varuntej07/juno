import 'dart:convert';
import 'dart:io';

import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exception.dart';
import '../../core/logging/app_logger.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_response.dart';
import '../models/dietary_profile_model.dart';
import '../models/scan_result_model.dart';

class NutritionScanService {
  final ApiClient _apiClient;

  NutritionScanService({required ApiClient apiClient}) : _apiClient = apiClient;

  /// Send image file to backend for VLM scan.
  /// Returns scan result with detected items + clarifying questions if needed.
  Future<Result<ScanResultModel>> scanImage(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final b64 = base64Encode(bytes);
      final mimeType = _mimeType(imageFile.path);

      return _apiClient.post(
        '/nutrition/scan',
        {'image_base64': b64, 'mime_type': mimeType},
        ScanResultModel.fromMap,
        timeout: AppConstants.nutritionScanTimeout,
      );
    } catch (e, st) {
      AppLogger.error(
        'NutritionScanService.scanImage failed',
        error: e,
        stackTrace: st,
        tag: 'NutritionScanService',
      );
      return Result.failure(
        AppException.unexpected(e.toString(), error: e, stackTrace: st),
      );
    }
  }

  /// Submit user answers (after Q&A) to get the full nutrition verdict.
  Future<Result<NutritionAnalysisModel>> analyzeFood(
    String scanId,
    Map<String, dynamic> userAnswers,
  ) async {
    return _apiClient.post(
      '/nutrition/analyze',
      {'scan_id': scanId, 'user_answers': userAnswers},
      NutritionAnalysisModel.fromMap,
      timeout: AppConstants.nutritionScanTimeout,
    );
  }

  /// Fetch stored dietary profile for the current user.
  Future<Result<DietaryProfileModel?>> getDietaryProfile() async {
    return _apiClient.get(
      '/nutrition/profile',
      (json) {
        final profile = json['profile'];
        if (profile == null) return null;
        return DietaryProfileModel.fromMap(profile as Map<String, dynamic>);
      },
    );
  }

  /// Save / update dietary profile.
  Future<Result<DietaryProfileModel>> saveDietaryProfile(
    DietaryProfileModel profile,
  ) async {
    return _apiClient.post(
      '/nutrition/profile',
      {'profile': profile.toMap()},
      (json) => DietaryProfileModel.fromMap(
        json['profile'] as Map<String, dynamic>,
      ),
    );
  }

  static String _mimeType(String path) {
    final ext = path.split('.').last.toLowerCase();
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => 'image/jpeg',
    };
  }
}
