import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';
import '../core/network/connectivity_service.dart';
import '../data/repositories/auth_repository.dart';
import '../data/repositories/memory_repository.dart';
import '../data/repositories/reminder_repository.dart';
import '../data/services/firebase_auth_service.dart';
import '../data/services/firestore_service.dart';
import '../data/services/lambda_api_service.dart';
import '../presentation/viewmodels/auth_viewmodel.dart';
import '../presentation/viewmodels/home_viewmodel.dart';
import '../presentation/viewmodels/settings_viewmodel.dart';

List<SingleChildWidget> buildProviders() {
  // Services
  final firebaseAuthService = FirebaseAuthService();
  final firestoreService = FirestoreService();
  final connectivityService = ConnectivityService();

  // Lambda service — stub until endpoints are configured
  final lambdaApiService = LambdaApiService(useStub: true);

  // Repositories
  final authRepository = AuthRepository(
    authService: firebaseAuthService,
    firestoreService: firestoreService,
  );
  final memoryRepository = MemoryRepository(firestoreService: firestoreService);
  final reminderRepository = ReminderRepository(firestoreService: firestoreService);

  return [
    // Services
    Provider<FirebaseAuthService>.value(value: firebaseAuthService),
    Provider<FirestoreService>.value(value: firestoreService),
    Provider<ConnectivityService>.value(value: connectivityService),
    Provider<LambdaApiService>.value(value: lambdaApiService),

    // Repositories
    Provider<AuthRepository>.value(value: authRepository),
    Provider<MemoryRepository>.value(value: memoryRepository),
    Provider<ReminderRepository>.value(value: reminderRepository),

    // ViewModels
    ChangeNotifierProvider<AuthViewModel>(
      create: (_) => AuthViewModel(authRepository: authRepository),
    ),
    ChangeNotifierProvider<HomeViewModel>(
      create: (_) => HomeViewModel(lambdaService: lambdaApiService),
    ),
    ChangeNotifierProvider<SettingsViewModel>(
      create: (_) => SettingsViewModel(firestoreService: firestoreService),
    ),
  ];
}
