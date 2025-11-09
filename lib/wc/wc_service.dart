import 'dart:async';
import 'dart:developer' as dev;

import 'package:flutter/foundation.dart';
import 'package:walletconnect_flutter_v2/apis/core/pairing/utils/pairing_models.dart';
import 'package:walletconnect_flutter_v2/apis/sign_api/models/session_models.dart';
import 'package:walletconnect_flutter_v2/apis/utils/walletconnect_utils.dart'
    as wc_utils;
import 'package:walletconnect_flutter_v2/walletconnect_flutter_v2.dart' as wc;

import '../core/wallet/wc_utils.dart';

const Duration _defaultPairingTimeout = Duration(seconds: 20);
const String _logTag = 'WcService';

enum WcStatus { idle, pairing, proposed, connected, error }

class WcState {
  const WcState({
    required this.status,
    this.topic,
    this.message,
  });

  final WcStatus status;
  final String? topic;
  final String? message;

  WcState copyWith({
    WcStatus? status,
    String? topic,
    String? message,
    bool clearMessage = false,
  }) {
    return WcState(
      status: status ?? this.status,
      topic: topic ?? this.topic,
      message: clearMessage ? null : (message ?? this.message),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is WcState &&
        other.status == status &&
        other.topic == topic &&
        other.message == message;
  }

  @override
  int get hashCode => Object.hash(status, topic, message);
}

abstract class WcUiEvent {}

class WcSessionProposalEvent extends WcUiEvent {
  WcSessionProposalEvent(this.event);

  final wc.SessionProposalEvent event;
}

class WcSessionConnectEvent extends WcUiEvent {
  WcSessionConnectEvent(this.event);

  final wc.SessionConnect event;
}

class WcSessionUpdateEvent extends WcUiEvent {
  WcSessionUpdateEvent(this.event);

  final wc.SessionUpdate event;
}

class WcSessionDeleteEvent extends WcUiEvent {
  WcSessionDeleteEvent(this.event);

  final wc.SessionDelete event;
}

class WcSessionEventEvent extends WcUiEvent {
  WcSessionEventEvent(this.event);

  final wc.SessionEvent event;
}

class WcService {
  WcService({Duration pairingTimeout = _defaultPairingTimeout})
      : _pairingTimeout = pairingTimeout;

  final Duration _pairingTimeout;
  final ValueNotifier<WcState> state =
      ValueNotifier<WcState>(const WcState(status: WcStatus.idle));
  final StreamController<WcUiEvent> _uiEvents =
      StreamController<WcUiEvent>.broadcast();

  wc.SignClient? _client;
  Timer? _pairTimer;
  String? _pendingTopic;
  bool _disposed = false;

  Stream<WcUiEvent> get uiEvents => _uiEvents.stream;

  void attachClient(wc.SignClient client) {
    if (_disposed) {
      return;
    }

    if (identical(_client, client)) {
      return;
    }

    _detachClient();
    _client = client;

    dev.log('attachClient', name: _logTag);

    client.onSessionProposal.subscribe(_handleSessionProposal);
    client.onSessionConnect.subscribe(_handleSessionConnect);
    client.onSessionUpdate.subscribe(_handleSessionUpdate);
    client.onSessionDelete.subscribe(_handleSessionDelete);
    client.onSessionEvent.subscribe(_handleSessionEvent);

    _syncSessionState();
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _cancelPairTimer();
    _detachClient();
    _pendingTopic = null;
    state.dispose();
    await _uiEvents.close();
  }

  Future<void> connectFromUri(String wcUri) async {
    if (_disposed) {
      throw StateError('WcService has been disposed');
    }

    final wc.SignClient? client = _client;
    if (client == null) {
      _setState(
        status: WcStatus.error,
        message: 'WalletConnect client not ready',
        clearMessage: false,
      );
      return;
    }

    final String trimmed = wcUri.trim();
    if (trimmed.isEmpty) {
      _setState(
        status: WcStatus.error,
        message: 'WalletConnect URI is empty',
        clearMessage: false,
      );
      return;
    }

    dev.log('connectFromUri uri=$trimmed', name: _logTag);

    final String? topic = _extractTopic(trimmed);
    _pendingTopic = topic;

    Uri parsed;
    try {
      parsed = Uri.parse(trimmed);
    } catch (error, stackTrace) {
      dev.log(
        'Invalid WalletConnect URI',
        name: _logTag,
        error: error,
        stackTrace: stackTrace,
      );
      _setState(
        status: WcStatus.error,
        topic: topic,
        message: 'Invalid WalletConnect URI',
        clearMessage: false,
      );
      _pendingTopic = null;
      return;
    }

    _setState(
      status: WcStatus.pairing,
      topic: topic,
      clearMessage: true,
    );
    _startPairTimer();

    final bool hasExisting = await _hasActivePairing(client, topic);
    if (hasExisting) {
      dev.log(
        'Existing active pairing for topic $topic, waiting for proposal',
        name: _logTag,
      );
      return;
    }

    Future.microtask(() async {
      try {
        await client.pair(uri: parsed);
      } catch (error, stackTrace) {
        dev.log(
          'pair() failed',
          name: _logTag,
          error: error,
          stackTrace: stackTrace,
        );
        if (_pendingTopic == topic) {
          _cancelPairTimer();
          _pendingTopic = null;
          _setState(
            status: WcStatus.error,
            topic: topic,
            message: '$error',
            clearMessage: false,
          );
        }
      }
    });
  }

  void _handleSessionProposal(wc.SessionProposalEvent? event) {
    if (event == null) {
      return;
    }

    final String? topic = event.params.pairingTopic;
    dev.log('onSessionProposal topic=$topic', name: _logTag);

    if (_isMatchingTopic(topic)) {
      _pendingTopic = topic ?? _pendingTopic;
      _cancelPairTimer();
      _setState(
        status: WcStatus.proposed,
        topic: _pendingTopic,
        clearMessage: true,
      );
    }

    if (!_uiEvents.isClosed) {
      _uiEvents.add(WcSessionProposalEvent(event));
    }
  }

  void _handleSessionConnect(wc.SessionConnect? event) {
    if (event == null) {
      return;
    }
    final String? topic = sessionTopic(event);
    dev.log('onSessionConnect topic=$topic', name: _logTag);

    if (_isMatchingTopic(topic)) {
      _cancelPairTimer();
      _pendingTopic = null;
      _setState(
        status: WcStatus.connected,
        topic: topic ?? state.value.topic,
        clearMessage: true,
      );
    } else {
      _syncSessionState();
    }

    if (!_uiEvents.isClosed) {
      _uiEvents.add(WcSessionConnectEvent(event));
    }
  }

  void _handleSessionUpdate(wc.SessionUpdate? event) {
    if (event == null) {
      return;
    }
    dev.log('onSessionUpdate', name: _logTag);
    _syncSessionState();
    if (!_uiEvents.isClosed) {
      _uiEvents.add(WcSessionUpdateEvent(event));
    }
  }

  void _handleSessionDelete(wc.SessionDelete? event) {
    dev.log('onSessionDelete', name: _logTag);
    _pendingTopic = null;
    _cancelPairTimer();
    _syncSessionState();
    if (event != null && !_uiEvents.isClosed) {
      _uiEvents.add(WcSessionDeleteEvent(event));
    }
  }

  void _handleSessionEvent(wc.SessionEvent? event) {
    if (event == null) {
      return;
    }
    if (!_uiEvents.isClosed) {
      _uiEvents.add(WcSessionEventEvent(event));
    }
  }

  void _setState({
    required WcStatus status,
    String? topic,
    String? message,
    bool clearMessage = false,
  }) {
    final WcState current = state.value;
    final WcState next = current.copyWith(
      status: status,
      topic: topic,
      message: message,
      clearMessage: clearMessage,
    );
    if (next != current) {
      dev.log(
        'state => status=${next.status} topic=${next.topic} message=${next.message}',
        name: _logTag,
      );
      state.value = next;
    }
  }

  void _startPairTimer() {
    _cancelPairTimer();
    _pairTimer = Timer(_pairingTimeout, () {
      if (state.value.status == WcStatus.pairing) {
        dev.log('pair/proposal timeout', name: _logTag);
        _pendingTopic = null;
        _setState(
          status: WcStatus.error,
          topic: state.value.topic,
          message: 'Timeout waiting for WalletConnect proposal',
          clearMessage: false,
        );
      }
    });
  }

  void _cancelPairTimer() {
    _pairTimer?.cancel();
    _pairTimer = null;
  }

  bool _isMatchingTopic(String? topic) {
    final String? expected = _pendingTopic;
    if (expected == null || topic == null) {
      return true;
    }
    return expected == topic;
  }

  void _syncSessionState() {
    final wc.SignClient? client = _client;
    if (client == null) {
      return;
    }
    final sessions = client.sessions.getAll();
    if (sessions.isNotEmpty) {
      _setState(
        status: WcStatus.connected,
        topic: sessions.first.topic,
        clearMessage: true,
      );
    } else {
      if (state.value.status != WcStatus.error) {
        _setState(
          status: WcStatus.idle,
          topic: sessions.isNotEmpty ? sessions.first.topic : null,
          clearMessage: true,
        );
      }
    }
  }

  Future<bool> _hasActivePairing(wc.SignClient client, String? topic) async {
    if (topic == null) {
      return false;
    }
    final List<PairingInfo> pairings = client.core.pairing.getPairings();
    for (final PairingInfo pairing in pairings) {
      if (pairing.topic != topic) {
        continue;
      }
      final bool expired = wc_utils.WalletConnectUtils.isExpired(pairing.expiry);
      if (!expired && pairing.active) {
        return true;
      }
    }
    return false;
  }

  void _detachClient() {
    final wc.SignClient? client = _client;
    if (client == null) {
      return;
    }

    try {
      client.onSessionProposal.unsubscribe(_handleSessionProposal);
    } catch (_) {}
    try {
      client.onSessionConnect.unsubscribe(_handleSessionConnect);
    } catch (_) {}
    try {
      client.onSessionUpdate.unsubscribe(_handleSessionUpdate);
    } catch (_) {}
    try {
      client.onSessionDelete.unsubscribe(_handleSessionDelete);
    } catch (_) {}
    try {
      client.onSessionEvent.unsubscribe(_handleSessionEvent);
    } catch (_) {}

    _client = null;
  }

  String? _extractTopic(String uri) {
    final int colonIndex = uri.indexOf(':');
    final int atIndex = uri.indexOf('@');
    if (colonIndex >= 0 && atIndex > colonIndex) {
      return uri.substring(colonIndex + 1, atIndex);
    }
    return null;
  }
}
