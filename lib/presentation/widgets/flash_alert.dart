import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Shows a lightweight flash alert at the top of the screen that
/// auto-dismisses after 2 seconds. Not a SnackBar, uses an Overlay.
void showFlashAlert(BuildContext context, String message) {
  final overlay = Overlay.of(context);

  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _FlashAlertWidget(
      message: message,
      onDismiss: () => entry.remove(),
    ),
  );

  overlay.insert(entry);
}

class _FlashAlertWidget extends StatefulWidget {
  final String message;
  final VoidCallback onDismiss;

  const _FlashAlertWidget({
    required this.message,
    required this.onDismiss,
  });

  @override
  State<_FlashAlertWidget> createState() => _FlashAlertWidgetState();
}

class _FlashAlertWidgetState extends State<_FlashAlertWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    );

    _controller.forward();

    _dismissTimer = Timer(const Duration(seconds: 2), () {
      _controller.reverse().then((_) {
        if (mounted) widget.onDismiss();
      });
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.of(context).padding.top;
    return Positioned(
      top: topPadding + 12,
      left: 0,
      right: 0,
      child: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: AppColors.border,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                widget.message,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
