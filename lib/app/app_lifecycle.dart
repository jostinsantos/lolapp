import 'package:flutter/widgets.dart';

/// Application lifecycle observer helper.
class AppLifecycle {
  AppLifecycle._();
  static final observer = _AppLifecycleObserver();
}

class _AppLifecycleObserver with WidgetsBindingObserver {}
