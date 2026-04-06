import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../core/config/environment.dart';
import '../core/network/api_client.dart';
import '../core/network/connectivity_service.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/memory_repository.dart';
import '../data/repositories/reminder_repository.dart';
import '../data/services/firebase_auth_service.dart';
import '../data/services/firestore_service.dart';
import '../data/services/lambda_api_service.dart';
import '../data/services/voice_capture_service.dart';
import '../data/services/voice_playback_service.dart';
import '../data/services/voice_session_service.dart';
import '../data/services/wake_word_service.dart';
import '../presentation/viewmodels/auth_viewmodel.dart';
import '../presentation/viewmodels/home_viewmodel.dart';
import '../presentation/viewmodels/settings_viewmodel.dart';

List<SingleChildWidget> buildProviders() {
  final firebaseAuthService = FirebaseAuthService();
  final firestoreService = FirestoreService();
  final connectivityService = ConnectivityService();
  final apiClient = ApiClient(
    connectivity: connectivityService,
    tokenProvider: firebaseAuthService.getIdToken,
  );
  final lambdaApiService = LambdaApiService(
    apiClient: apiClient,
    useStub: !Environment.hasConfiguredApi,
  );
  final voiceSessionService = VoiceSessionService(
    tokenProvider: firebaseAuthService.getIdToken,
  );

  // Real audio services — PCM streaming via flutter_sound
  final voiceCaptureService = FlutterSoundCaptureService();
  final voicePlaybackService = FlutterSoundPlaybackService();
  final wakeWordService = WakeWordService();

  final authRepository = AuthRepository(
    authService: firebaseAuthService,
    firestoreService: firestoreService,
  );
  final memoryRepository = MemoryRepository(firestoreService: firestoreService);
  final reminderRepository = ReminderRepository(firestoreService: firestoreService);

  return [
    Provider<FirebaseAuthService>.value(value: firebaseAuthService),
    Provider<FirestoreService>.value(value: firestoreService),
    Provider<ConnectivityService>.value(value: connectivityService),
    Provider<ApiClient>.value(value: apiClient),
    Provider<LambdaApiService>.value(value: lambdaApiService),
    Provider<VoiceSessionService>.value(value: voiceSessionService),
    Provider<VoiceCaptureService>.value(value: voiceCaptureService),
    Provider<VoicePlaybackService>.value(value: voicePlaybackService),
    Provider<WakeWordService>.value(value: wakeWordService),
    Provider<AuthRepository>.value(value: authRepository),
    Provider<MemoryRepository>.value(value: memoryRepository),
    Provider<ReminderRepository>.value(value: reminderRepository),
    ChangeNotifierProvider<AuthViewModel>(
      create: (_) => AuthViewModel(authRepository: authRepository),
    ),
    ChangeNotifierProvider<HomeViewModel>(
      create: (_) => HomeViewModel(
        lambdaService: lambdaApiService,
        connectivityService: connectivityService,
        voiceSessionService: voiceSessionService,
        voiceCaptureService: voiceCaptureService,
        voicePlaybackService: voicePlaybackService,
        wakeWordService: wakeWordService,
      ),
    ),
    ChangeNotifierProvider<SettingsViewModel>(
      create: (_) => SettingsViewModel(firestoreService: firestoreService),
    ),
  ];
}
