import 'dart:collection';
import 'dart:io';

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
  bool _retryScheduled = false;

  void init() {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    log('Lifecycle changed: $_state -> $state');
    _state = state;
    _drain();
  }

  void enqueue(PopupBuilder builder) {
    _queue.add(builder);
    _drain();
  }

  Future<void> _drain() async {
    log('Drain requested (showing=$_showing, lifecycle=$_state, queue=${_queue.length})');
    if (_showing) return;
    if (!_canProceedWithLifecycleState()) {
      log('Drain aborted: lifecycle state $_state is not ready');
      return;
    }
    final nav = rootNavigatorKey.currentState;
    final ctx = rootNavigatorKey.currentContext;
    if (nav == null || ctx == null) {
      log('Navigator/context unavailable (nav=$nav, ctx=$ctx)');
      if (_queue.isNotEmpty && !_retryScheduled) {
        log('Scheduling retry; queue length=${_queue.length}');
        // On Windows the UI tree may not be ready immediately after navigation
        // changes, so scheduling a post-frame retry prevents missing queued
        // popups when the navigator/context becomes available.
        _retryScheduled = true;
        SchedulerBinding.instance.addPostFrameCallback((_) {
          _retryScheduled = false;
          log('Retrying after post-frame; queue length=${_queue.length}');
          if (_queue.isNotEmpty) {
            _drain();
          }
        });
      }
      return;
    }
    final next = _queue.isEmpty ? null : _queue.removeFirst();
    if (next == null) return;
    _showing = true;
    log('Showing popup; remaining queue length=${_queue.length}');
    SchedulerBinding.instance.addPostFrameCallback((_) async {
      await showDialog<void>(
        context: ctx,
        barrierDismissible: false,
        builder: next,
      );
      _showing = false;
      log('Popup dismissed; draining queue');
      _drain();
    });
  }

  bool _canProceedWithLifecycleState() {
    if (_state == AppLifecycleState.resumed) {
      return true;
    }

    final canResumeWhileVisibleOnWindows = Platform.isWindows &&
        (_state == AppLifecycleState.inactive || _state == AppLifecycleState.hidden);

    if (canResumeWhileVisibleOnWindows) {
      log('Treating lifecycle state $_state as resumable on Windows');
      return true;
    }

    return false;
  }

  void log(String msg) {
    // ignore: avoid_print
    print('[PopupCoordinator] $msg @${DateTime.now().toIso8601String()}');
  }
}
