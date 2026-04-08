import 'dart:io';

import '../../core/base/safe_change_notifier.dart';
import '../../core/errors/app_exception.dart';
import '../../core/logging/app_logger.dart';
import '../../data/models/scan_result_model.dart';
import '../../data/services/nutrition_scan_service.dart';

enum NutritionScanState {
  idle,
  scanning,       // image uploaded, waiting for Gemini
  questioning,    // confidence low, showing Q&A
  analyzing,      // user answered, waiting for final verdict
  result,         // analysis complete
  error,
}

class NutritionScanViewModel extends SafeChangeNotifier {
  final NutritionScanService _service;

  NutritionScanState _state = NutritionScanState.idle;
  ScanResultModel? _scanResult;
  NutritionAnalysisModel? _analysis;
  AppException? _error;

  // Q&A state
  int _currentQuestionIndex = 0;
  final Map<String, dynamic> _answers = {};

  NutritionScanViewModel({required NutritionScanService service})
      : _service = service;

  NutritionScanState get state => _state;
  ScanResultModel? get scanResult => _scanResult;
  NutritionAnalysisModel? get analysis => _analysis;
  AppException? get error => _error;
  Map<String, dynamic> get answers => Map.unmodifiable(_answers);

  List<ScanQuestion> get questions => _scanResult?.clarifyingQuestions ?? [];
  int get currentQuestionIndex => _currentQuestionIndex;
  ScanQuestion? get currentQuestion =>
      _currentQuestionIndex < questions.length ? questions[_currentQuestionIndex] : null;
  bool get hasMoreQuestions => _currentQuestionIndex < questions.length - 1;
  double get questionProgress =>
      questions.isEmpty ? 1.0 : (_currentQuestionIndex + 1) / questions.length;

  void _setState(NutritionScanState s) {
    _state = s;
    safeNotifyListeners();
  }

  /// Step 1: Send image to backend for initial scan.
  Future<void> scan(File imageFile) async {
    _state = NutritionScanState.scanning;
    _scanResult = null;
    _analysis = null;
    _error = null;
    _currentQuestionIndex = 0;
    _answers.clear();
    safeNotifyListeners();

    final result = await _service.scanImage(imageFile);
    result.when(
      success: (scan) {
        _scanResult = scan;
        if (scan.needsClarification && scan.clarifyingQuestions.isNotEmpty) {
          _setState(NutritionScanState.questioning);
        } else {
          // High confidence — go straight to analysis
          _runAnalysis();
        }
      },
      failure: (err) {
        _error = err;
        _setState(NutritionScanState.error);
        AppLogger.error('Scan failed', error: err, tag: 'NutritionScanVM');
      },
    );
  }

  /// Step 2a: Record answer for current question and advance.
  void answerCurrent(dynamic value) {
    final q = currentQuestion;
    if (q == null) return;
    _answers[q.id] = value;

    if (hasMoreQuestions) {
      _currentQuestionIndex++;
      safeNotifyListeners();
    } else {
      _runAnalysis();
    }
  }

  /// Step 2b: Skip optional question and advance.
  void skipCurrent() {
    if (hasMoreQuestions) {
      _currentQuestionIndex++;
      safeNotifyListeners();
    } else {
      _runAnalysis();
    }
  }

  /// Step 3: Submit all answers and get verdict.
  Future<void> _runAnalysis() async {
    final sid = _scanResult?.scanId;
    if (sid == null) return;

    _setState(NutritionScanState.analyzing);

    final result = await _service.analyzeFood(sid, _answers);
    result.when(
      success: (analysis) {
        _analysis = analysis;
        _setState(NutritionScanState.result);
      },
      failure: (err) {
        _error = err;
        _setState(NutritionScanState.error);
        AppLogger.error('Analyze failed', error: err, tag: 'NutritionScanVM');
      },
    );
  }

  void reset() {
    _state = NutritionScanState.idle;
    _scanResult = null;
    _analysis = null;
    _error = null;
    _currentQuestionIndex = 0;
    _answers.clear();
    safeNotifyListeners();
  }
}
