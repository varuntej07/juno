import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'core/theme/app_theme.dart';
import 'presentation/screens/app_shell.dart';
import 'presentation/screens/auth/login_screen.dart';
import 'presentation/viewmodels/auth_viewmodel.dart';
import 'presentation/widgets/loading_indicator.dart';

class JunoApp extends StatelessWidget {
  const JunoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Juno',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const _RootScreen(),
    );
  }
}

class _RootScreen extends StatefulWidget {
  const _RootScreen();

  @override
  State<_RootScreen> createState() => _RootScreenState();
}

class _RootScreenState extends State<_RootScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AuthViewModel>().initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthViewModel>(
      builder: (context, vm, _) {
        if (vm.state == ViewState.loading || vm.state == ViewState.idle) {
          return const Scaffold(
            body: FullScreenLoader(message: 'Starting Juno...'),
          );
        }
        if (vm.isAuthenticated) {
          return const AppShell();
        }
        return const LoginScreen();
      },
    );
  }
}
