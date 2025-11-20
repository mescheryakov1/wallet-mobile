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
  bool _navigatorRetryScheduled = false;
  bool _pendingLifecycleResume = false;

  void init() {
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    log('Lifecycle changed: $_state -> $state');
    _state = state;
    if (state == AppLifecycleState.resumed) {
      log('Lifecycle resumed; retrying queued popups (${_queue.length})');
      _drain();
      return;
    }

    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      _pendingLifecycleResume = _queue.isNotEmpty || _showing;
      if (_pendingLifecycleResume) {
        log('Lifecycle inactive/paused; delaying popup processing until resume');
      }
    }
  }

  void enqueue(PopupBuilder builder) {
    log('Enqueue popup; queue length before enqueue=${_queue.length}');
    _queue.add(builder);
    _drain();
  }

  Future<void> _drain() async {
    log('Drain requested (showing=$_showing, lifecycle=$_state, queue=${_queue.length})');
    if (_showing) return;
    if (!_canProceedWithLifecycleState()) {
      log('Drain aborted: lifecycle state $_state is not ready');
      _pendingLifecycleResume = true;
      return;
    }
    final nav = rootNavigatorKey.currentState;
    final ctx = rootNavigatorKey.currentContext;
    if (nav == null || ctx == null) {
      log('Navigator/context unavailable (nav=$nav, ctx=$ctx); scheduling retry');
      if (_queue.isNotEmpty) {
        _scheduleNavigatorAwait();
      }
      return;
    }
    _pendingLifecycleResume = false;
    final next = _queue.isEmpty ? null : _queue.removeFirst();
    if (next == null) {
      log('Drain finished: no queued popups to show');
      return;
    }
    _showing = true;
    log('Showing popup; remaining queue length=${_queue.length}');
    SchedulerBinding.instance.addPostFrameCallback((_) async {
      bool success = false;
      try {
        await showDialog<void>(
          context: ctx,
          barrierDismissible: false,
          builder: next,
        );
        success = true;
      } catch (e, st) {
        log('Popup failed to show: $e\n$st');
      } finally {
        _showing = false;
      }

      log(
        success
            ? 'Popup completed successfully; draining remaining queue (${_queue.length})'
            : 'Popup did not complete; pending queue length=${_queue.length}',
      );
      if (_queue.isNotEmpty) {
        _drain();
      }
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

  void _scheduleNavigatorAwait() {
    if (_navigatorRetryScheduled) {
      log('Navigator retry already scheduled; skipping duplicate request');
      return;
    }
    _navigatorRetryScheduled = true;
    WidgetsBinding.instance.endOfFrame.then((_) {
      _navigatorRetryScheduled = false;
      if (_queue.isEmpty) {
        log('Navigator retry completed but queue is empty; nothing to show');
        return;
      }

      log(
        'Retrying drain after navigator wait; queue length=${_queue.length}, lifecycle=$_state, '
        'pendingLifecycleResume=$_pendingLifecycleResume',
      );
      _drain();
    });
  }

  void log(String msg) {
    // ignore: avoid_print
    print('[PopupCoordinator] $msg @${DateTime.now().toIso8601String()}');
  }
}
