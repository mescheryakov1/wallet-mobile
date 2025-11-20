import 'dart:async';
import 'dart:collection';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../wallet_connect_service.dart';
import '../deeplink/android_deeplink.dart' show DeeplinkAndroid;

/// Coordinates WalletConnect deeplink delivery with retry/persistence semantics.
///
/// Protocol summary:
/// - All `wc:` URIs are pushed into an in-memory queue and persisted under
///   [_storageKey] to survive app restarts.
/// - Delivery starts only when the [WalletConnectService] reports the
///   [WalletConnectState.ready] state. Incoming links received while the
///   service is not ready stay queued.
/// - Each link is retried with exponential backoff (starting at
///   [_initialBackoff] and doubling until [_maxBackoff]) when pairing throws
///   or times out. Attempts reset after a successful delivery.
/// - Queue mutations are durably stored so unfinished links resume processing
///   after process restarts.
class _WalletConnectDeeplinkBuffer {
  _WalletConnectDeeplinkBuffer(this._svc);

  static const String _storageKey = 'wc_pending_links';
  static const Duration _initialBackoff = Duration(seconds: 2);
  static const Duration _maxBackoff = Duration(minutes: 2);

  final WalletConnectService _svc;
  final ListQueue<String> _queue = ListQueue<String>();
  final Set<String> _queuedLinks = <String>{};
  final Map<String, int> _attempts = <String, int>{};

  late final VoidCallback _svcListener = _maybeProcessQueue;
  bool _processing = false;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    await _loadPersistedQueue();
    _svc.addListener(_svcListener);
    await DeeplinkAndroid.init();

    DeeplinkAndroid.stream.listen((String link) {
      _onIncomingLink(link);
    });
    _maybeProcessQueue();
  }

  Future<void> _onIncomingLink(String link) async {
    if (!link.startsWith('wc:')) {
      return;
    }
    if (_queuedLinks.contains(link)) {
      return;
    }

    _queue.add(link);
    _queuedLinks.add(link);
    await _persistQueue();
    _maybeProcessQueue();
  }

  Future<void> _loadPersistedQueue() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String> persisted = prefs.getStringList(_storageKey) ?? <String>[];
    if (persisted.isEmpty) {
      return;
    }

    for (final String link in persisted) {
      if (link.startsWith('wc:')) {
        _queue.add(link);
        _queuedLinks.add(link);
      }
    }
  }

  Future<void> _persistQueue() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_storageKey, _queue.toList());
  }

  Duration _backoffForAttempt(int attempt) {
    if (attempt <= 0) {
      return Duration.zero;
    }
    final int multiplier = max(1, min(64, pow(2, attempt - 1).toInt()));
    final int backoffMs = max(
      0,
      min(_initialBackoff.inMilliseconds * multiplier, _maxBackoff.inMilliseconds),
    );
    return Duration(milliseconds: backoffMs);
  }

  void _maybeProcessQueue() {
    if (_processing || _queue.isEmpty) {
      return;
    }
    if (_svc.connectionState != WalletConnectState.ready) {
      return;
    }
    _processing = true;
    _processQueue();
  }

  Future<void> _processQueue() async {
    while (_svc.connectionState == WalletConnectState.ready && _queue.isNotEmpty) {
      final String link = _queue.first;
      final int attempt = _attempts[link] ?? 0;
      final Duration backoff = _backoffForAttempt(attempt);
      if (backoff > Duration.zero) {
        await Future<void>.delayed(backoff);
      }

      try {
        await _svc.connectFromUri(link);
        _queue.removeFirst();
        _queuedLinks.remove(link);
        _attempts.remove(link);
        await _persistQueue();
      } catch (_) {
        _attempts[link] = attempt + 1;
        _processing = false;
        await _persistQueue();
        _scheduleRetry();
        return;
      }
    }

    _processing = false;
  }

  void _scheduleRetry() {
    if (_queue.isEmpty) {
      return;
    }
    final String link = _queue.first;
    final Duration delay = _backoffForAttempt(_attempts[link] ?? 1);
    Future<void>.delayed(delay, _maybeProcessQueue);
  }
}

_WalletConnectDeeplinkBuffer? _buffer;

Future<void> handleInitialUriAndStream(WalletConnectService svc) async {
  _buffer ??= _WalletConnectDeeplinkBuffer(svc);
  await _buffer!.initialize();
}
