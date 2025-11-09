import 'package:flutter/widgets.dart';

class AppLifecycleLogger with WidgetsBindingObserver {
  AppLifecycleLogger() {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // ignore: avoid_print
    print('[Lifecycle] $state @${DateTime.now().toIso8601String()}');
  }
}
