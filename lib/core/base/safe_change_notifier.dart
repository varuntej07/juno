import 'package:flutter/foundation.dart';

abstract class SafeChangeNotifier extends ChangeNotifier {
  bool _isDisposed = false;

  bool get isDisposed => _isDisposed;

  @protected
  void safeNotifyListeners() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}
