import 'dart:collection';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../navigation/navigator_key.dart';

typedef PopupBuilder = Widget Function(BuildContext context);

class PopupCoordinator with WidgetsBindingObserver {
  PopupCoordinator._();

  static final PopupCoordinator I = PopupCoordinator._();

  final Queue<PopupBuilder> _queue = Queue<PopupBuilder>();
  bool _showing = false;
  AppLifecycleState _state = AppLifecycleState.resumed;
  bool _drainScheduled = false;

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
    _scheduleDrainAfterFrame();
    _drain();
  }

  void _scheduleDrainAfterFrame() {
    if (_drainScheduled) return;
    _drainScheduled = true;
    WidgetsBinding.instance.ensureVisualUpdate();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _drainScheduled = false;
      _drain();
    });
  }

  Future<void> _drain() async {
    if (_showing) return;
    if (_state != AppLifecycleState.resumed) {
      _scheduleDrainAfterFrame();
      return;
    }
    final nav = rootNavigatorKey.currentState;
    final ctx = rootNavigatorKey.currentContext;
    if (nav == null || ctx == null) {
      _scheduleDrainAfterFrame();
      return;
    }
    final next = _queue.isEmpty ? null : _queue.removeFirst();
    if (next == null) return;
    _showing = true;
    WidgetsBinding.instance.ensureVisualUpdate();
    SchedulerBinding.instance.addPostFrameCallback((_) async {
      await showDialog<void>(
        context: ctx,
        barrierDismissible: false,
        builder: next,
      );
      _showing = false;
      _drain();
    });
  }

  void log(String msg) {
    // ignore: avoid_print
    print('[PopupCoordinator] $msg @${DateTime.now().toIso8601String()}');
  }
}
