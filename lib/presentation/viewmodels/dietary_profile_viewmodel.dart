import '../../core/base/safe_change_notifier.dart';
import '../../core/errors/app_exception.dart';
import '../../core/logging/app_logger.dart';
import '../../data/models/dietary_profile_model.dart';
import '../../data/services/nutrition_scan_service.dart';
import 'view_state.dart';

export 'view_state.dart';

class DietaryProfileViewModel extends SafeChangeNotifier {
  final NutritionScanService _service;

  ViewState _state = ViewState.idle;
  DietaryProfileModel? _profile;
  AppException? _error;
  bool _nutritionAgentEnabled = false;

  DietaryProfileViewModel({required NutritionScanService service})
      : _service = service;

  ViewState get state => _state;
  DietaryProfileModel? get profile => _profile;
  AppException? get error => _error;
  bool get nutritionAgentEnabled => _nutritionAgentEnabled;
  bool get hasProfile => _profile != null;

  void _setState(ViewState s) {
    _state = s;
    safeNotifyListeners();
  }

  Future<void> load() async {
    _setState(ViewState.loading);
    final result = await _service.getDietaryProfile();
    result.when(
      success: (profile) {
        _profile = profile;
        _nutritionAgentEnabled = profile != null;
        _error = null;
        _setState(ViewState.loaded);
      },
      failure: (err) {
        _error = err;
        _setState(ViewState.error);
        AppLogger.error('Load dietary profile failed', error: err, tag: 'DietaryProfileVM');
      },
    );
  }

  Future<bool> saveProfile(DietaryProfileModel profile) async {
    _setState(ViewState.loading);
    final result = await _service.saveDietaryProfile(profile);
    bool success = false;
    result.when(
      success: (saved) {
        _profile = saved;
        _nutritionAgentEnabled = true;
        _error = null;
        success = true;
        _setState(ViewState.loaded);
      },
      failure: (err) {
        _error = err;
        _setState(ViewState.error);
        AppLogger.error('Save dietary profile failed', error: err, tag: 'DietaryProfileVM');
      },
    );
    return success;
  }

  void disableNutritionAgent() {
    _nutritionAgentEnabled = false;
    _profile = null;
    safeNotifyListeners();
  }

  void clearError() {
    _error = null;
    safeNotifyListeners();
  }
}
