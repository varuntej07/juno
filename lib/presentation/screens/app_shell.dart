import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';

/// Persistent shell rendered around the Home and Agents tabs.
/// go_router's ShellRoute calls build(context, state, child) and passes the
/// active tab's screen as [child] — we just wrap it with the bottom nav.
class AppShell extends StatelessWidget {
  final Widget child;
  const AppShell({super.key, required this.child});

  static const _tabs = ['/home', '/agents'];

  int _tabIndex(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final i = _tabs.indexWhere((t) => location.startsWith(t));
    return i < 0 ? 0 : i;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: child,
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tabIndex(context),
        onTap: (i) => context.go(_tabs[i]),
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.accent,
        unselectedItemColor: AppColors.textTertiary,
        selectedLabelStyle: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: const TextStyle(fontSize: 11),
        elevation: 0,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.mic_none_rounded),
            activeIcon: Icon(Icons.mic_rounded),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.extension_outlined),
            activeIcon: Icon(Icons.extension_rounded),
            label: 'Agents',
          ),
        ],
      ),
    );
  }
}
