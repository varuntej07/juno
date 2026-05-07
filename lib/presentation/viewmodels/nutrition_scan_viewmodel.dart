import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';

import '../../core/base/safe_change_notifier.dart';
import '../../core/errors/app_exception.dart';
import '../../core/logging/app_logger.dart';
import '../../data/models/scan_result_model.dart';
import '../../data/services/notification_service.dart';
import '../../data/services/nutrition_scan_service.dart';

enum NutritionScanState {
  idle,
  scanning,       // image uploaded, waiting for Gemini
  questioning,    // confidence low, showing Q&A
  analyzing,      // user answered, waiting for final verdict
  result,         // analysis complete
  error,
}

// Scanning phrases fire before the food is identified — interesting observations,
// not task descriptions. Mix of science facts and personality to make the wait feel shorter.
const _scanningPhrases = [
  'Most people underestimate their portions by about 30%...',
  'Every food has a story. Reading yours...',
  'Some foods are sneaky in ways you\'d never guess...',
  'The real calories are almost always in the details...',
  'Huberman would tell you: timing matters too. Checking...',
  'The label never tells you the whole truth...',
  'What you see and what you eat are often very different...',
  'Your gut microbiome is already curious about this one...',
  'Food quality and food quantity — both matter here...',
  'Buddy\'s nutritionist brain is fully online...',
];

// Analyzing phrases fire after the food is known — they reference the specific food
// and make the wait feel personal, not generic.
List<String> _analyzingPhrasesForFood(String food) => [
  'Running the full breakdown on your $food...',
  'What does $food actually do to your goals? Checking...',
  'Buddy\'s seen a lot of $food. The verdict\'s almost ready...',
  'Getting real with you about those $food...',
  'Did you know most people eat $food more often than they think?',
  'Cross-checking your $food against your profile...',
  'The science on $food is actually interesting. One sec...',
  'Almost there — Buddy\'s forming an honest take on your $food...',
  'Final call on your $food incoming...',
  'Okay. Here\'s what Buddy actually thinks about your $food...',
];

const _loadingPhraseCycleDuration = Duration(milliseconds: 2500);

class NutritionScanViewModel extends SafeChangeNotifier {
  final NutritionScanService _service;
  final NotificationService _notificationService;

  NutritionScanState _state = NutritionScanState.idle;
  ScanResultModel? _scanResult;
  NutritionAnalysisModel? _analysis;
  AppException? _error;

  // Q&A state
  int _currentQuestionIndex = 0;
  final Map<String, dynamic> _answers = {};

  // Loading phrase rotation
  int _loadingPhraseIndex = 0;
  Timer? _loadingPhraseTimer;

  // Set to true when the app goes to background during scanning/analyzing.
  // Triggers a local notification once the result arrives.
  bool _appWentToBackground = false;

  NutritionScanViewModel({
    required NutritionScanService service,
    required NotificationService notificationService,
  })  : _service = service,
        _notificationService = notificationService;

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

  String get _detectedFoodName =>
      _scanResult?.detectedItems.firstOrNull ?? 'this';

  String get currentLoadingPhrase {
    if (_state == NutritionScanState.scanning) {
      return _scanningPhrases[_loadingPhraseIndex % _scanningPhrases.length];
    }
    final phrases = _analyzingPhrasesForFood(_detectedFoodName);
    return phrases[_loadingPhraseIndex % phrases.length];
  }

  void _setState(NutritionScanState s) {
    _state = s;

    if (s == NutritionScanState.scanning || s == NutritionScanState.analyzing) {
      _startLoadingPhraseCycle(s);
    } else {
      _stopLoadingPhraseCycle();
    }

    safeNotifyListeners();
  }

  void _startLoadingPhraseCycle(NutritionScanState phase) {
    _stopLoadingPhraseCycle();
    _loadingPhraseIndex = 0;
    _loadingPhraseTimer = Timer.periodic(_loadingPhraseCycleDuration, (_) {
      final len = phase == NutritionScanState.scanning
          ? _scanningPhrases.length
          : _analyzingPhrasesForFood(_detectedFoodName).length;
      _loadingPhraseIndex = (_loadingPhraseIndex + 1) % len;
      safeNotifyListeners();
    });
  }

  void _stopLoadingPhraseCycle() {
    _loadingPhraseTimer?.cancel();
    _loadingPhraseTimer = null;
  }

  /// Called by the screen when the app lifecycle changes.
  /// Fires a local notification if the user backgrounds during an active scan.
  void onAppLifecycleChanged(AppLifecycleState state) {
    if (state != AppLifecycleState.paused) return;

    if (_state == NutritionScanState.questioning) {
      // Q&A is waiting — nudge immediately so they come back and finish.
      _notificationService.showNutritionScanLocalNotification(
        title: 'Buddy needs a few answers',
        body: 'Tap to finish your nutrition scan.',
      );
    } else if (_state == NutritionScanState.scanning ||
        _state == NutritionScanState.analyzing) {
      _appWentToBackground = true;
    }
  }

  /// Step 1: Send image to backend for initial scan.
  Future<void> scan(File imageFile) async {
    _state = NutritionScanState.scanning;
    _scanResult = null;
    _analysis = null;
    _error = null;
    _currentQuestionIndex = 0;
    _appWentToBackground = false;
    _answers.clear();
    _startLoadingPhraseCycle(NutritionScanState.scanning);
    safeNotifyListeners();

    final result = await _service.scanImage(imageFile);
    result.when(
      success: (scan) {
        _scanResult = scan;
        if (scan.needsClarification && scan.clarifyingQuestions.isNotEmpty) {
          _setState(NutritionScanState.questioning);
        } else {
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

        if (_appWentToBackground) {
          _notificationService.showNutritionScanLocalNotification(
            title: 'Nutrition scan complete',
            body: 'Your ${analysis.foodName} analysis is ready.',
          );
        }
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
    _appWentToBackground = false;
    _answers.clear();
    _stopLoadingPhraseCycle();
    safeNotifyListeners();
  }

  @override
  void dispose() {
    _stopLoadingPhraseCycle();
    super.dispose();
  }
}
