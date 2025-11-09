import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:wallet_mobile/ui/dialog_dispatcher.dart';

typedef PopupBuilder = Widget Function(BuildContext context);

class PopupCoordinator with WidgetsBindingObserver {
  PopupCoordinator._();

  static final PopupCoordinator I = PopupCoordinator._();

  final Queue<PopupBuilder> _queue = Queue<PopupBuilder>();
  bool _showing = false;
  AppLifecycleState _state = AppLifecycleState.resumed;

  void init() {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _state = state;
    _drain();
  }

  void enqueue(PopupBuilder builder) {
    _queue.add(builder);
    _drain();
  }

  Future<void> _drain() async {
    if (_showing) return;
    if (_state != AppLifecycleState.resumed) return;
    final next = _queue.isEmpty ? null : _queue.removeFirst();
    if (next == null) return;
    _showing = true;
    SchedulerBinding.instance.addPostFrameCallback((_) async {
      try {
        await dialogDispatcher.enqueue(next);
      } finally {
        _showing = false;
        _drain();
      }
    });
  }

  void log(String msg) {
    // ignore: avoid_print
    print('[PopupCoordinator] $msg @${DateTime.now().toIso8601String()}');
  }
}
