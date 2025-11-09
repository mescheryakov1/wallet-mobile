import 'dart:async';
import 'dart:collection';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:window_manager/window_manager.dart';

import '../core/navigation/navigator_key.dart';

typedef DialogBuilder = Widget Function(BuildContext context);

class _DialogRequest {
  _DialogRequest(this.builder, this.completer);

  final DialogBuilder builder;
  final Completer<void> completer;
}

class DialogDispatcher {
  DialogDispatcher(this.navigatorKey);

  final GlobalKey<NavigatorState> navigatorKey;
  final Queue<_DialogRequest> _queue = Queue<_DialogRequest>();
  bool _showing = false;

  Future<void> enqueue(DialogBuilder builder) {
    final Completer<void> completer = Completer<void>();
    _queue.add(_DialogRequest(builder, completer));
    _pump();
    return completer.future;
  }

  void _pump() {
    if (_showing) {
      return;
    }
    if (_queue.isEmpty) {
      return;
    }

    _showing = true;
    SchedulerBinding.instance.scheduleFrame();
    SchedulerBinding.instance.addPostFrameCallback((_) async {
      final NavigatorState? navigator = navigatorKey.currentState;
      final BuildContext? context = navigatorKey.currentContext;
      if (navigator == null || !navigator.mounted || context == null) {
        _showing = false;
        if (_queue.isNotEmpty) {
          _pump();
        }
        return;
      }

      final _DialogRequest request = _queue.removeFirst();

      try {
        if (!kIsWeb && Platform.isWindows) {
          await windowManager.ensureInitialized();
          await windowManager.focus();
        }

        await showDialog<void>(
          context: navigator.context,
          useRootNavigator: true,
          barrierDismissible: false,
          builder: request.builder,
        );
        if (!request.completer.isCompleted) {
          request.completer.complete();
        }
      } catch (error, stackTrace) {
        if (!request.completer.isCompleted) {
          request.completer.completeError(error, stackTrace);
        }
      } finally {
        _showing = false;
        if (_queue.isNotEmpty) {
          _pump();
        }
      }
    });
  }
}

final DialogDispatcher dialogDispatcher = DialogDispatcher(appNavigatorKey);
