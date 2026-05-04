import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'core/router/router.dart';
import 'core/theme/app_theme.dart';
import 'presentation/viewmodels/auth_viewmodel.dart';

class JunoApp extends StatefulWidget {
  const JunoApp({super.key});

  @override
  State<JunoApp> createState() => _JunoAppState();
}

class _JunoAppState extends State<JunoApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    // context.read is safe in initState — widget is already in the tree.
    _router = buildRouter(context.read<AuthViewModel>());
    // Kick off auth state resolution; the router's refreshListenable fires once
    // AuthViewModel.state leaves idle/loading, triggering the redirect.
    context.read<AuthViewModel>().initialize();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Juno',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      routerConfig: _router,
    );
  }
}
