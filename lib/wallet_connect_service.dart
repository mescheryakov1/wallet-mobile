import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:walletconnect_flutter_v2/apis/sign_api/models/session_models.dart';
import 'package:walletconnect_flutter_v2/walletconnect_flutter_v2.dart';
import 'package:web3dart/web3dart.dart';

import 'core/ui/popup_coordinator.dart';
import 'core/wallet/wc_utils.dart';
import 'local_wallet_api.dart';
import 'network_config.dart';
import 'wallet_connect_models.dart';
import 'nonce_manager.dart';

const String _defaultWalletConnectProjectId =
    'ac79370327e3526ba018428bc44831f1';
const String _sessionsStorageKey = 'wc_sessions';

const List<String> _supportedMethods = <String>[
  'personal_sign',
  'eth_sendTransaction',
];

const List<String> _supportedEvents = <String>[
  'accountsChanged',
  'chainChanged',
];

final List<String> _supportedChains = walletConnectSupportedChainIds();
final Set<String> _supportedChainSet =
    _supportedChains.map((chain) => chain.toLowerCase()).toSet();
final Set<String> _supportedMethodSet =
    _supportedMethods.map((method) => method.toLowerCase()).toSet();
final Set<String> _supportedEventSet =
    _supportedEvents.map((event) => event.toLowerCase()).toSet();

class _RequestExtraction {
  const _RequestExtraction({
    required this.requestId,
    required this.params,
    this.chainId,
  });

  final int requestId;
  final dynamic params;
  final String? chainId;
}

class _RequestValidationResult {
  const _RequestValidationResult({
    required this.allowed,
    required this.methodAllowed,
    required this.chainAllowed,
  });

  final bool allowed;
  final bool methodAllowed;
  final bool chainAllowed;
}

enum WalletConnectState {
  disconnected,
  initializing,
  ready,
  reconnecting,
  failed,
}

class _QueuedRequest {
  _QueuedRequest(this.request) : completer = Completer<String>();

  final WalletConnectPendingRequest request;
  final Completer<String> completer;
}

class _NamespaceConfig {
  _NamespaceConfig({required this.isRequired});

  bool isRequired;
  final Set<String> chains = <String>{};
  final Set<String> methods = <String>{};
  final Set<String> events = <String>{};
}

class WalletConnectRequestException implements Exception {
  WalletConnectRequestException(
    this.message, {
    this.isRejected = false,
  });

  final String message;
  final bool isRejected;

  @override
  String toString() => message;
}

class WalletConnectService extends ChangeNotifier with WidgetsBindingObserver {
  WalletConnectService({
    required this.walletApi,
    String? projectId,
    Duration? sessionProposalTimeout,
    Duration? androidSessionProposalTimeout,
    int maxPairingAttempts = 3,
    Duration? initialPairingBackoff,
    int clientInitMaxAttempts = 3,
    Duration? initialClientBackoff,
  })  : projectId = projectId ?? _defaultWalletConnectProjectId,
        sessionProposalTimeout = sessionProposalTimeout ?? Duration.zero,
        androidSessionProposalTimeout =
            androidSessionProposalTimeout ?? const Duration(seconds: 25),
        maxPairingAttempts = maxPairingAttempts,
        initialPairingBackoff =
            initialPairingBackoff ?? const Duration(seconds: 2),
        clientInitMaxAttempts = clientInitMaxAttempts,
        initialClientBackoff =
            initialClientBackoff ?? const Duration(seconds: 2) {
    _attachWalletListenerIfNeeded();
    _attachLifecycleObserver();
  }

  final LocalWalletApi walletApi;
  final String projectId;
  final Duration sessionProposalTimeout;
  final Duration androidSessionProposalTimeout;
  final int maxPairingAttempts;
  final Duration initialPairingBackoff;
  final int clientInitMaxAttempts;
  final Duration initialClientBackoff;

  final List<String> activeSessions = [];
  final List<WalletConnectSessionInfo> _sessionInfos = [];

  SignClient? _client;
  WalletConnectState _connectionState = WalletConnectState.disconnected;
  String _status = 'disconnected';
  Future<void>? _initializationFuture;
  String debugLastProposalLog = '';
  String debugLastError = '';
  bool _handlersRegistered = false;
  String? _lastRequestDebug;
  String? _lastErrorDebug;
  bool _pairingInProgress = false;
  String? _pairingError;
  DateTime? _pairingStartTime;
  String? lastError;
  Completer<void>? _sessionProposalCompleter;
  WalletConnectPendingRequest? _pendingSessionProposal;
  WalletConnectPendingRequest? _pendingRequest;
  WalletConnectSessionInfo? _activeSession;
  Completer<String>? _pendingRequestCompleter;
  final ListQueue<_QueuedRequest> _pendingRequestQueue = ListQueue<_QueuedRequest>();
  WalletConnectActivityEntry? _lastActivityEntry;
  final Set<int> _processingRequestIds = <int>{};
  final Set<int> _handledRequestIds = <int>{};
  final ListQueue<int> _handledRequestOrder = ListQueue<int>();
  bool _walletListenerAttached = false;
  bool _lifecycleObserverAttached = false;
  final StreamController<WalletConnectRequestEvent>
      _requestEventsController =
      StreamController<WalletConnectRequestEvent>.broadcast();

  String get status => _status;
  WalletConnectState get connectionState => _connectionState;
  String? get lastRequestDebug => _lastRequestDebug;
  String? get lastErrorDebug => _lastErrorDebug;
  bool get pairingInProgress => _pairingInProgress;
  bool get isPairing => _pairingInProgress;
  String? get pairingError => _pairingError;
  WalletConnectPendingRequest? get pendingSessionProposal =>
      _pendingSessionProposal;
  WalletConnectPendingRequest? get pendingRequest => _pendingRequest;
  @visibleForTesting
  List<WalletConnectPendingRequest> get queuedRequests =>
      List<WalletConnectPendingRequest>.unmodifiable(
        _pendingRequestQueue.map((request) => request.request),
      );
  @visibleForTesting
  Future<String> enqueueRequestForTesting(
    WalletConnectPendingRequest request,
  ) {
    return _enqueuePendingRequest(request);
  }
  @visibleForTesting
  void setTestingClient(SignClient client) {
    _client = client;
  }

  List<WalletConnectSessionInfo> getActiveSessions() =>
      List<WalletConnectSessionInfo>.unmodifiable(_sessionInfos);
  bool get isConnected => _sessionInfos.isNotEmpty;
  WalletConnectSessionInfo? get activeSession => _activeSession;
  bool get hasActiveSession => _activeSession != null;
  WalletConnectSessionInfo? get primarySessionInfo =>
      _sessionInfos.isEmpty ? null : _sessionInfos.first;
  List<String> getApprovedChains() {
    final session = primarySessionInfo;
    if (session == null) {
      return const <String>[];
    }
    return List<String>.from(session.chains);
  }

  List<String> getApprovedMethods() {
    final session = primarySessionInfo;
    if (session == null) {
      return const <String>[];
    }
    return List<String>.from(session.methods);
  }

  WalletConnectActivityEntry? get lastActivityEntry => _lastActivityEntry;
  Stream<WalletConnectRequestEvent> get requestEvents =>
      _requestEventsController.stream;

  Future<void> init() async {
    await initWalletConnect();
  }

  void _attachLifecycleObserver() {
    if (_lifecycleObserverAttached) {
      return;
    }
    final binding = WidgetsBinding.instance;
    if (binding != null) {
      binding.addObserver(this);
      _lifecycleObserverAttached = true;
    }
  }

  void _attachWalletListenerIfNeeded() {
    if (_walletListenerAttached) {
      return;
    }
    final api = walletApi;
    if (api is ChangeNotifier) {
      api.addListener(_handleWalletUpdated);
      _walletListenerAttached = true;
    }
  }

  void _handleWalletUpdated() {
    if (!_handlersRegistered && walletApi.getAddress() != null) {
      _registerAccountAndHandlers();
    }
  }

  void _setConnectionState(
    WalletConnectState newState, {
    String? reason,
  }) {
    final previous = _connectionState;
    final hasReason = reason != null && reason.isNotEmpty;
    _connectionState = newState;
    _status = hasReason ? '${newState.name}: $reason' : newState.name;
    final transitionLog =
        'state $previous -> $newState${hasReason ? ' ($reason)' : ''}';
    PopupCoordinator.I.log('WC:$transitionLog');
    debugPrint('WC:$transitionLog');
    if (newState == WalletConnectState.disconnected ||
        newState == WalletConnectState.failed) {
      _cancelPendingCompleterIfActive(
        reason: reason ?? 'Connection closed.',
        clearQueued: true,
      );
    }
    notifyListeners();
  }

  Future<void> initWalletConnect() async {
    _attachWalletListenerIfNeeded();

    if (projectId.isEmpty) {
      _setConnectionState(WalletConnectState.failed,
          reason: 'missing project id');
      return;
    }

    await _initializeClientWithBackoff(reason: 'init');
  }

  Future<void> _initializeClientWithBackoff({
    bool forceReconnect = false,
    String? reason,
  }) {
    _initializationFuture ??= _doInitializeClient(
      forceReconnect: forceReconnect,
      reason: reason,
    ).whenComplete(() {
      _initializationFuture = null;
    });

    return _initializationFuture!;
  }

  Future<void> _doInitializeClient({
    required bool forceReconnect,
    String? reason,
  }) async {
    if (_client != null && !forceReconnect) {
      return;
    }

    if (forceReconnect && _client != null) {
      _detachClient(_client!);
      _client = null;
    }

    _setConnectionState(
      forceReconnect
          ? WalletConnectState.reconnecting
          : WalletConnectState.initializing,
      reason: reason,
    );

    final int attempts = clientInitMaxAttempts < 1 ? 1 : clientInitMaxAttempts;
    Object? lastError;

    for (int attempt = 1; attempt <= attempts; attempt++) {
      try {
        PopupCoordinator.I.log('WC:init attempt $attempt/$attempts');
        final metadata = PairingMetadata(
          name: 'Wallet Mobile',
          description: 'Flutter wallet',
          url: 'https://example.com',
          icons: const ['https://example.com/icon.png'],
        );

        final client = await SignClient.createInstance(
          projectId: projectId,
          metadata: metadata,
        );

        _client = client;
        _attachClientSubscriptions(client);
        _handlersRegistered = false;
        _registerAccountAndHandlers();
        await _loadPersistedSessions();
        await _refreshActiveSessions();
        _setConnectionState(WalletConnectState.ready, reason: reason);
        PopupCoordinator.I.log('WC:init done');
        return;
      } catch (error, stackTrace) {
        lastError = error;
        debugPrint('WalletConnect init failed (attempt $attempt): $error\n$stackTrace');
        if (attempt >= attempts) {
          break;
        }
        final Duration delay = _clientInitRetryBackoff(attempt);
        await Future<void>.delayed(delay);
        _setConnectionState(
          WalletConnectState.reconnecting,
          reason: 'retrying after error: $error',
        );
      }
    }

    _setConnectionState(
      WalletConnectState.failed,
      reason: lastError?.toString(),
    );
  }

  _RequestExtraction _extractRequestDetails(
    String topic,
    String method,
    dynamic params,
  ) {
    final client = _client;
    SessionRequest? matchedRequest;

    if (client != null) {
      try {
        final pending = client.pendingRequests.getAll();
        for (final request in pending.reversed) {
          if (request.topic == topic && request.method == method) {
            matchedRequest = request;
            break;
          }
        }
      } catch (error) {
        _lastErrorDebug = 'pending request lookup failed: $error';
      }
    } else {
      _lastErrorDebug = 'handler error: client not ready';
    }

    final requestId =
        matchedRequest?.id ?? DateTime.now().millisecondsSinceEpoch;
    final requestParams = matchedRequest?.params ?? params;
    final extractedChain = matchedRequest?.chainId ??
        _deriveChainIdFromParams(method, requestParams);
    final inferredChain = extractedChain ??
        _inferChainIdFromSession(topic, method, requestParams);
    final normalizedChain = _normalizeChainId(inferredChain);

    if (matchedRequest == null &&
        (_lastErrorDebug == null || _lastErrorDebug!.isEmpty)) {
      _lastErrorDebug = 'pending request not found, using fallback id';
    }

    return _RequestExtraction(
      requestId: requestId,
      params: requestParams,
      chainId: normalizedChain,
    );
  }

  bool isRequestAllowed({
    required String topic,
    required String method,
    String? chainId,
  }) {
    final session = _getSessionByTopic(topic);
    if (session == null) {
      return false;
    }
    final normalizedChain = _normalizeChainId(chainId);
    final result = _evaluateSessionPermissions(
      session,
      method,
      normalizedChain,
    );
    return result.allowed;
  }

  void _validateBeforePrompt({
    required String topic,
    required String method,
    String? chainId,
  }) {
    final client = _client;
    if (client == null) {
      throw WalletConnectError(
        code: 5000,
        message: 'WalletConnect not initialized',
      );
    }

    final session = _getSessionByTopic(topic);
    if (session == null) {
      throw WalletConnectError(
        code: 5000,
        message: 'Session not found',
      );
    }

    final normalizedChain = _normalizeChainId(chainId);
    final result = _evaluateSessionPermissions(
      session,
      method,
      normalizedChain,
    );

    if (result.allowed) {
      return;
    }

    if (!result.chainAllowed && normalizedChain != null) {
      throw WalletConnectError(
        code: 5100,
        message: 'Chain not approved for this session.',
      );
    }

    if (!result.methodAllowed) {
      throw WalletConnectError(
        code: 5101,
        message: 'Method not approved for this session.',
      );
    }

    throw WalletConnectError(
      code: 5101,
      message: 'Method not approved for this session.',
    );
  }

  SessionData? _getSessionByTopic(String topic) {
    final client = _client;
    if (client == null) {
      return null;
    }

    try {
      return client.sessions.get(topic);
    } catch (_) {
      // ignored, fall back to scanning all sessions
    }

    try {
      final sessions = client.sessions.getAll();
      for (final session in sessions) {
        if (session.topic == topic) {
          return session;
        }
      }
    } catch (_) {
      // ignore lookup errors
    }
    return null;
  }

  _RequestValidationResult _evaluateSessionPermissions(
    SessionData session,
    String method,
    String? normalizedChain,
  ) {
    final normalizedMethod = method.toLowerCase();
    final bool methodSupported = _supportedMethodSet.contains(normalizedMethod);
    final bool chainSupported =
        normalizedChain == null || _supportedChainSet.contains(normalizedChain);

    bool methodPresent = false;
    bool chainPresent = normalizedChain == null;
    bool allowed = false;

    session.namespaces.forEach((_, namespace) {
      if (allowed) {
        return;
      }
      final namespaceMethods = namespace.methods
          .map((value) => value.toLowerCase())
          .where(_supportedMethodSet.contains)
          .toSet();
      final namespaceChains = _extractChainsFromNamespace(namespace)
          .map(_normalizeChainId)
          .whereType<String>()
          .where(_supportedChainSet.contains)
          .toSet();

      if (namespaceMethods.contains(normalizedMethod)) {
        methodPresent = true;
      }

      if (normalizedChain != null && namespaceChains.contains(normalizedChain)) {
        chainPresent = true;
      }

      final chainMatches = normalizedChain == null ||
          namespaceChains.contains(normalizedChain);
      if (namespaceMethods.contains(normalizedMethod) && chainMatches) {
        allowed = true;
      }
    });

    final bool methodAllowed = methodSupported && methodPresent;
    final bool chainAllowed = chainSupported && chainPresent;
    final bool finalAllowed = methodAllowed &&
        (normalizedChain == null || chainAllowed);

    return _RequestValidationResult(
      allowed: finalAllowed,
      methodAllowed: methodAllowed,
      chainAllowed: chainAllowed,
    );
  }

  String? _normalizeChainId(String? chainId) {
    if (chainId == null) {
      return null;
    }
    var value = chainId.trim();
    if (value.isEmpty) {
      return null;
    }
    value = value.toLowerCase();
    if (value.startsWith('0x')) {
      final parsed = int.tryParse(value.substring(2), radix: 16);
      if (parsed != null) {
        return 'eip155:$parsed';
      }
    }
    if (!value.contains(':')) {
      final parsed = int.tryParse(value);
      if (parsed != null) {
        return 'eip155:$parsed';
      }
      return value;
    }

    final parts = value.split(':');
    if (parts.length == 2 && parts[1].startsWith('0x')) {
      final parsed = int.tryParse(parts[1].substring(2), radix: 16);
      if (parsed != null) {
        return '${parts[0]}:$parsed';
      }
    }
    return value;
  }

  String? _deriveChainIdFromParams(String method, dynamic params) {
    if (method == 'eth_sendTransaction') {
      final list = _asList(params);
      if (list.isNotEmpty && list.first is Map) {
        final tx = Map<String, dynamic>.from(list.first as Map);
        final chainValue = tx['chainId'];
        if (chainValue is String) {
          return _normalizeChainId(chainValue);
        }
        if (chainValue is int) {
          return _normalizeChainId(chainValue.toString());
        }
      }
    }
    return null;
  }

  String? _inferChainIdFromSession(
    String topic,
    String method,
    dynamic params,
  ) {
    final session = _getSessionByTopic(topic);
    if (session == null) {
      return null;
    }

    final direct = _deriveChainIdFromParams(method, params);
    if (direct != null) {
      return _normalizeChainId(direct);
    }

    final fromAddress =
        method == 'eth_sendTransaction' ? _extractFromAddress(params) : null;
    final normalizedFrom =
        fromAddress != null ? _normalizeAddress(fromAddress) : null;

    String? fallback;
    for (final namespace in session.namespaces.values) {
      for (final account in namespace.accounts) {
        final parts = account.split(':');
        if (parts.length < 3) {
          continue;
        }
        final normalizedChain =
            _normalizeChainId('${parts[0]}:${parts[1]}');
        if (normalizedChain == null) {
          continue;
        }
        fallback ??= normalizedChain;
        if (normalizedFrom != null &&
            _normalizeAddress(parts[2]) == normalizedFrom) {
          return normalizedChain;
        }
      }
    }

    return fallback;
  }

  String? _extractFromAddress(dynamic params) {
    final list = _asList(params);
    if (list.isEmpty) {
      return null;
    }
    final first = list.first;
    if (first is Map) {
      final tx = Map<String, dynamic>.from(first as Map);
      final fromValue = tx['from'];
      if (fromValue is String && fromValue.isNotEmpty) {
        return fromValue;
      }
    }
    return null;
  }

  Future<String> _enqueuePendingRequest(
    WalletConnectPendingRequest request,
  ) {
    final queued = _QueuedRequest(request);
    _pendingRequestQueue.addLast(queued);
    if (_pendingRequestQueue.length == 1) {
      _syncActiveRequestFromQueue();
    }
    notifyListeners();
    return queued.completer.future;
  }

  void _syncActiveRequestFromQueue() {
    if (_pendingRequestQueue.isEmpty) {
      _pendingRequest = null;
      _pendingSessionProposal = null;
      _pendingRequestCompleter = null;
      return;
    }
    final _QueuedRequest active = _pendingRequestQueue.first;
    _pendingRequest = active.request;
    _pendingRequestCompleter = active.completer;
    _pendingSessionProposal =
        active.request.method == 'session_proposal' ? active.request : null;
  }

  void _advanceRequestQueue({bool clearRemainingQueue = false}) {
    if (_pendingRequestQueue.isNotEmpty) {
      _pendingRequestQueue.removeFirst();
    }
    _pendingRequestCompleter = null;
    _pendingRequest = null;
    _pendingSessionProposal = null;
    if (clearRemainingQueue) {
      while (_pendingRequestQueue.isNotEmpty) {
        final _QueuedRequest queued = _pendingRequestQueue.removeFirst();
        if (!queued.completer.isCompleted) {
          queued.completer.completeError(
            WalletConnectError(
              code: 4001,
              message: 'Request cancelled.',
            ),
          );
        }
      }
    }
    _syncActiveRequestFromQueue();
    notifyListeners();
  }

  void _markRequestHandled(int requestId) {
    if (_handledRequestIds.add(requestId)) {
      _handledRequestOrder.addLast(requestId);
      if (_handledRequestOrder.length > 50) {
        final int oldest = _handledRequestOrder.removeFirst();
        _handledRequestIds.remove(oldest);
      }
    }
  }

  bool _isRequestHandled(int requestId) => _handledRequestIds.contains(requestId);

  Future<void> _loadPersistedSessions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_sessionsStorageKey);
      if (raw == null || raw.isEmpty) {
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return;
      }
      final infos = decoded
          .whereType<Map<String, dynamic>>()
          .map(WalletConnectSessionInfo.fromJson)
          .toList(growable: false);
      _setSessionInfos(infos);
    } catch (error) {
      debugPrint('Failed to load persisted WC sessions: $error');
    }
  }

  Future<void> _persistSessions() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(
        _sessionInfos.map((info) => info.toJson()).toList(growable: false),
      );
      await prefs.setString(_sessionsStorageKey, encoded);
    } catch (error) {
      debugPrint('Failed to persist WC sessions: $error');
    }
  }

  void _setSessionInfos(List<WalletConnectSessionInfo> infos) {
    _sessionInfos
      ..clear()
      ..addAll(infos);
    _activeSession = infos.isNotEmpty ? infos.first : null;
    activeSessions
      ..clear()
      ..addAll(
        infos
            .map((info) => info.dappName)
            .whereType<String>()
            .where((name) => name.isNotEmpty),
      );
    if (infos.isEmpty) {
      _lastActivityEntry = null;
    }
    _resetNonceCacheForSessions(infos);
    notifyListeners();
  }

  void _resetNonceCacheForSessions(List<WalletConnectSessionInfo> infos) {
    final NonceManager manager = NonceManager.instance;
    if (infos.isEmpty) {
      final EthereumAddress? address = walletApi.getAddress();
      if (address == null) {
        return;
      }
      for (final NetworkConfig config in walletConnectSupportedNetworks) {
        manager.resetChainAddress(
          chainId: config.chainIdCaip2,
          address: address.hexEip55,
        );
      }
      return;
    }

    for (final WalletConnectSessionInfo info in infos) {
      for (final String account in info.accounts) {
        final List<String> parts = account.split(':');
        if (parts.length < 3) {
          continue;
        }
        final String chain = '${parts[0]}:${parts[1]}'.toLowerCase();
        final String addressPart = parts.sublist(2).join(':');
        final String normalizedAddress = addressPart.startsWith('0x')
            ? addressPart
            : '0x$addressPart';
        manager.resetChainAddress(
          chainId: chain,
          address: normalizedAddress,
        );
      }
    }
  }

  void _recordActivity({
    required String method,
    required WalletConnectRequestStatus status,
    required String summary,
    String? chainId,
    int? requestId,
    String? result,
    String? error,
  }) {
    _lastActivityEntry = WalletConnectActivityEntry(
      requestId: requestId,
      method: method,
      summary: summary,
      status: status,
      chainId: chainId,
      result: result,
      error: error,
    );
  }

  void _emitRequestEvent({
    required WalletConnectRequestStatus status,
    required WalletConnectPendingRequest request,
    String? result,
    String? error,
  }) {
    if (_requestEventsController.isClosed) {
      return;
    }
    _requestEventsController.add(
      WalletConnectRequestEvent(
        request: request,
        status: status,
        result: result,
        error: error,
      ),
    );
  }

  Duration _resolveSessionProposalTimeout() {
    if (Platform.isAndroid) {
      return androidSessionProposalTimeout;
    }
    return sessionProposalTimeout;
  }

  Duration _pairingRetryBackoff(int attempt) {
    final int multiplier = 1 << (attempt - 1);
    return Duration(
      milliseconds: initialPairingBackoff.inMilliseconds * multiplier,
    );
  }

  Duration _clientInitRetryBackoff(int attempt) {
    final int multiplier = 1 << (attempt - 1);
    return Duration(
      milliseconds: initialClientBackoff.inMilliseconds * multiplier,
    );
  }

  void _attachClientSubscriptions(SignClient client) {
    try {
      client.onSessionProposal.unsubscribe(_onSessionProposal);
    } catch (_) {
      // ignored
    }
    try {
      client.onSessionRequest.unsubscribe(_onSessionRequest);
    } catch (_) {}
    try {
      client.onSessionConnect.unsubscribe(_onSessionConnect);
    } catch (_) {}
    try {
      client.onSessionDelete.unsubscribe(_onSessionDelete);
    } catch (_) {}

    client.onSessionProposal.subscribe(_onSessionProposal);
    client.onSessionRequest.subscribe(_onSessionRequest);
    client.onSessionConnect.subscribe(_onSessionConnect);
    client.onSessionDelete.subscribe(_onSessionDelete);
  }

  void _detachClient(SignClient client) {
    try {
      client.onSessionProposal.unsubscribe(_onSessionProposal);
    } catch (_) {}
    try {
      client.onSessionRequest.unsubscribe(_onSessionRequest);
    } catch (_) {}
    try {
      client.onSessionConnect.unsubscribe(_onSessionConnect);
    } catch (_) {}
    try {
      client.onSessionDelete.unsubscribe(_onSessionDelete);
    } catch (_) {}
  }

  Future<void> _restartHandlersAndSubscriptions({String? reason}) async {
    final client = _client;
    if (client == null) {
      await _initializeClientWithBackoff(
        forceReconnect: true,
        reason: reason,
      );
      return;
    }

    _attachClientSubscriptions(client);
    _handlersRegistered = false;
    _registerAccountAndHandlers();
  }

  void _logPairingStage(String message) {
    PopupCoordinator.I.log('WC:$message');
    debugPrint('WC:$message');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _initializeClientWithBackoff(
        forceReconnect: true,
        reason: 'app resumed',
      );
    }
  }

  Future<void> connectFromUri(String uri) async {
    if (_client == null) {
      await _initializeClientWithBackoff(reason: 'pairing start');
    }

    final client = _client;
    if (client == null) {
      _setConnectionState(
        WalletConnectState.failed,
        reason: 'client unavailable for pairing',
      );
      throw StateError('WalletConnect not initialized');
    }

    final String trimmed = uri.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError('WalletConnect URI is empty');
    }
    if (!trimmed.startsWith('wc:')) {
      throw ArgumentError('Invalid WalletConnect URI');
    }

    Uri parsed;
    try {
      parsed = Uri.parse(trimmed);
    } catch (error) {
      throw ArgumentError('Invalid WalletConnect URI: $error');
    }

    _pairingError = null;
    lastError = null;
    _pendingSessionProposal = null;
    _pairingStartTime = DateTime.now();
    _logPairingStage(
      'pair start uri=$trimmed at=${_pairingStartTime!.toIso8601String()}',
    );
    if (Platform.isAndroid) {
      debugPrint('WC: starting pair flow, preparing to set pairingInProgress');
    }
    _pairingInProgress = true;
    _status = 'pairing';
    notifyListeners();

    // Ensure the proposal listener is attached before pairing to avoid missing
    // events on platforms that deliver them immediately.
    try {
      client.onSessionProposal.unsubscribe(_onSessionProposal);
    } catch (_) {
      // Ignored: unsubscribe may throw if the handler was not yet attached.
    }
    client.onSessionProposal.subscribe(_onSessionProposal);
    _sessionProposalCompleter = Completer<void>();
    final Completer<void>? sessionProposalCompleter = _sessionProposalCompleter;

    final Duration proposalTimeout = _resolveSessionProposalTimeout();
    final int retries = maxPairingAttempts < 1 ? 1 : maxPairingAttempts;

    try {
      int attempt = 0;
      while (attempt < retries && (sessionProposalCompleter?.isCompleted ?? false) == false) {
        attempt += 1;
        final DateTime attemptStart = DateTime.now();
        _logPairingStage(
          'pair attempt $attempt/$retries started at ${attemptStart.toIso8601String()} timeout=${proposalTimeout.inMilliseconds}ms',
        );
        await client.pair(uri: parsed);
        _logPairingStage('pair attempt $attempt invoked client.pair');

        if (proposalTimeout == Duration.zero) {
          await sessionProposalCompleter!.future;
          break;
        }

        try {
          await sessionProposalCompleter!.future
              .timeout(proposalTimeout, onTimeout: () {
            throw TimeoutException(
              'Timed out waiting for session proposal',
            );
          });
          break;
        } on TimeoutException catch (error) {
          _logPairingStage(
            'pair attempt $attempt timed out at ${DateTime.now().toIso8601String()} error=${error.message}',
          );
          _status = 'waiting for proposal';
          _pairingError = error.message;
          lastError = _pairingError;
          notifyListeners();
          await _restartHandlersAndSubscriptions(
            reason: 'session proposal timeout',
          );
          if (attempt >= retries) {
            _pairingInProgress = false;
            _status = 'error: ${error.message}';
            _sessionProposalCompleter = null;
            break;
          }

          final Duration delay = _pairingRetryBackoff(attempt);
          _logPairingStage('scheduling retry in ${delay.inMilliseconds}ms');
          await Future<void>.delayed(delay);
          _pairingInProgress = true;
          _status = 'pairing retry';
          notifyListeners();
        }
      }
    } catch (error, stackTrace) {
      _pairingInProgress = false;
      _pairingError = '$error';
      lastError = _pairingError;
      _status = 'error: $error';
      _sessionProposalCompleter = null;
      _pairingStartTime = null;
      debugPrint('WalletConnect pair failed: $error\n$stackTrace');
      notifyListeners();
      await _restartHandlersAndSubscriptions(reason: 'pairing error');
      rethrow;
    }

    if (!_pairingInProgress &&
        (_sessionProposalCompleter == null ||
            (_sessionProposalCompleter?.isCompleted ?? false))) {
      _pairingStartTime = null;
    }
  }

  Future<void> startPairing(String uri) => connectFromUri(uri);

  Future<void> disconnectSession(String topic) async {
    final client = _client;
    if (client == null) {
      return;
    }

    try {
      await client.disconnect(
        topic: topic,
        reason: Errors.getSdkError(Errors.USER_DISCONNECTED),
      );
      _lastErrorDebug = '';
    } catch (error, stackTrace) {
      _lastErrorDebug = 'disconnect failed: $error';
      debugPrint('WalletConnect disconnect failed: $error\n$stackTrace');
    }

    await _refreshActiveSessions();
  }

  Future<void> _onSessionProposal(SessionProposalEvent? event) async {
    final client = _client;
    if (client == null || event == null) {
      return;
    }

    if (Platform.isAndroid) {
      debugPrint('WC: _onSessionProposal invoked');
    }

    _pairingInProgress = false;
    _sessionProposalCompleter?.complete();
    _sessionProposalCompleter = null;
    _pairingError = null;
    lastError = null;

    final DateTime now = DateTime.now();
    final String startedAt = _pairingStartTime?.toIso8601String() ?? '<unknown>';
    _logPairingStage(
      'session proposal received at ${now.toIso8601String()} startedAt=$startedAt',
    );
    _pairingStartTime = null;

    debugLastProposalLog =
        'RAW event=${event.toString()} | params=${event.params.toString()}';
    debugLastError = '';
    notifyListeners();

    final proposal = event.params;
    final proposerName = proposal.proposer.metadata.name ?? 'unknown dApp';
    PopupCoordinator.I.log('WC:event session_proposal from $proposerName');
    final address = walletApi.getAddress();
    if (address == null) {
      debugLastError = 'reject: no address available';
      _lastErrorDebug = 'reject: no wallet address for proposal';
      notifyListeners();
      await client.reject(
        id: event.id,
        reason: Errors.getSdkError(Errors.USER_REJECTED_CHAINS),
      );
      return;
    }

    final addressHex = address.hexEip55;
    final requiredNamespaces = proposal.requiredNamespaces;
    final optionalNamespaces =
        proposal.optionalNamespaces ?? <String, RequiredNamespace>{};

    Future<void> rejectProposal({
      required WalletConnectError reason,
      required String debugMessage,
    }) async {
      debugLastError = debugMessage;
      _lastErrorDebug = debugMessage;
      _pairingError = debugMessage;
      notifyListeners();
      await client.reject(id: event.id, reason: reason);
    }

    if (requiredNamespaces.isEmpty && optionalNamespaces.isEmpty) {
      await rejectProposal(
        reason: Errors.getSdkError(Errors.USER_REJECTED_CHAINS),
        debugMessage: 'reject proposal: no namespaces provided',
      );
      return;
    }

    final Map<String, _NamespaceConfig> aggregated =
        <String, _NamespaceConfig>{};

    void mergeNamespace(
      String namespaceKey,
      RequiredNamespace namespace, {
      required bool isRequired,
    }) {
      final normalizedKey = namespaceKey.toLowerCase();
      if (!normalizedKey.startsWith('eip155')) {
        if (isRequired) {
          throw WalletConnectError(
            code: 5100,
            message: 'Namespace not supported for this session.',
          );
        }
        return;
      }

      final config = aggregated.putIfAbsent(
        normalizedKey,
        () => _NamespaceConfig(isRequired: isRequired),
      );
      if (isRequired) {
        config.isRequired = true;
      }

      final chains = namespace.chains ?? const <String>[];
      for (final chain in chains) {
        final normalized = _normalizeChainId(chain);
        if (normalized != null) {
          config.chains.add(normalized);
        }
      }

      final methods = namespace.methods ?? const <String>[];
      for (final method in methods) {
        config.methods.add(method.toLowerCase());
      }

      final events = namespace.events ?? const <String>[];
      for (final eventName in events) {
        config.events.add(eventName.toLowerCase());
      }
    }

    try {
      requiredNamespaces.forEach(
        (key, value) => mergeNamespace(key, value, isRequired: true),
      );
      optionalNamespaces.forEach(
        (key, value) => mergeNamespace(key, value, isRequired: false),
      );
    } on WalletConnectError catch (error) {
      await rejectProposal(
        reason: error,
        debugMessage: 'reject proposal: ${error.message}',
      );
      return;
    }

    if (aggregated.isEmpty) {
      await rejectProposal(
        reason: Errors.getSdkError(Errors.USER_REJECTED_CHAINS),
        debugMessage: 'reject proposal: no supported namespaces after merge',
      );
      return;
    }

    final namespaces = <String, Namespace>{};
    final List<String> approvedDetails = <String>[];

    for (final entry in aggregated.entries) {
      final namespaceKey = entry.key;
      final config = entry.value;

      final filteredChains = config.chains
          .where(_supportedChainSet.contains)
          .toList(growable: false);

      if (filteredChains.isEmpty) {
        if (config.isRequired) {
          await rejectProposal(
            reason: Errors.getSdkError(Errors.USER_REJECTED_CHAINS),
            debugMessage:
                'reject proposal: no supported chains for $namespaceKey',
          );
          return;
        }
        continue;
      }

      final List<String> allowedMethods;
      if (config.methods.isEmpty) {
        allowedMethods = List<String>.from(_supportedMethods);
      } else {
        allowedMethods = _supportedMethods
            .where((method) => config.methods.contains(method.toLowerCase()))
            .toList(growable: false);
        if (allowedMethods.isEmpty) {
          if (config.isRequired) {
            await rejectProposal(
              reason: WalletConnectError(
                code: 5101,
                message: 'Method not approved for this session.',
              ),
              debugMessage:
                  'reject proposal: unsupported methods requested=${config.methods.toList()}',
            );
            return;
          }
          continue;
        }
      }

      final List<String> allowedEvents;
      if (config.events.isEmpty) {
        allowedEvents = List<String>.from(_supportedEvents);
      } else {
        allowedEvents = _supportedEvents
            .where((eventName) => config.events.contains(eventName.toLowerCase()))
            .toList(growable: false);
        if (allowedEvents.isEmpty) {
          if (config.isRequired) {
            await rejectProposal(
              reason: WalletConnectError(
                code: 5101,
                message: 'Events not approved for this session.',
              ),
              debugMessage:
                  'reject proposal: unsupported events requested=${config.events.toList()}',
            );
            return;
          }
          continue;
        }
      }

      final accounts = filteredChains
          .map((chain) => '$chain:$addressHex')
          .toSet()
          .toList(growable: false);

      if (accounts.isEmpty) {
        if (config.isRequired) {
          await rejectProposal(
            reason: Errors.getSdkError(Errors.USER_REJECTED_CHAINS),
            debugMessage: 'reject proposal: failed to build accounts',
          );
          return;
        }
        continue;
      }

      namespaces[namespaceKey] = Namespace(
        accounts: accounts,
        methods: allowedMethods,
        events: allowedEvents,
      );

      approvedDetails.add('$namespaceKey:${filteredChains.join(',')}');
    }

    if (namespaces.isEmpty) {
      await rejectProposal(
        reason: Errors.getSdkError(Errors.USER_REJECTED_CHAINS),
        debugMessage: 'reject proposal: no namespaces after filtering',
      );
      return;
    }

    _pairingInProgress = false;

    final metadata = proposal.proposer.metadata;
    final Set<String> chainSet = <String>{};
    final Set<String> accountSet = <String>{};
    final Set<String> methodSet = <String>{};
    final Set<String> eventSet = <String>{};

    namespaces.forEach((_, namespace) {
      methodSet.addAll(namespace.methods.map((m) => m.toLowerCase()));
      eventSet.addAll(namespace.events.map((e) => e.toLowerCase()));
      for (final String account in namespace.accounts) {
        accountSet.add(account);
        final List<String> parts = account.split(':');
        if (parts.length >= 2) {
          chainSet.add('${parts[0]}:${parts[1]}');
        }
      }
    });

    final Map<String, Object?> proposalDetails = <String, Object?>{
      'proposalId': event.id,
      'namespaces': namespaces,
      'metadata': <String, Object?>{
        'name': metadata.name,
        'description': metadata.description,
        'url': metadata.url,
        'icons': metadata.icons,
      },
      'chains': chainSet.toList(growable: false),
      'methods': methodSet.toList(growable: false),
      'events': eventSet.toList(growable: false),
      'accounts': accountSet.toList(growable: false),
      'approvedDetails': approvedDetails,
      'pairingTopic': proposal.pairingTopic,
    };

    final WalletConnectPendingRequest request = WalletConnectPendingRequest(
      topic: proposal.pairingTopic ?? '',
      requestId: event.id,
      method: 'session_proposal',
      params: proposalDetails,
      chainId: chainSet.isNotEmpty ? chainSet.first : null,
    );

    await _enqueuePendingRequest(request);
    lastError = null;
    _lastRequestDebug =
        'session_proposal from ${metadata.name} chains=${chainSet.join(', ')}';
    debugLastProposalLog =
        'proposal pending namespaces=${approvedDetails.join(' | ')}';
    debugLastError = '';
    _lastErrorDebug = '';

    _emitRequestEvent(
      status: WalletConnectRequestStatus.pending,
      request: request,
    );
    _recordActivity(
      method: 'session_proposal',
      status: WalletConnectRequestStatus.pending,
      summary: 'Connection request from ${metadata.name}',
      chainId: request.chainId,
      requestId: request.requestId,
    );

    _status = 'proposal received';
    notifyListeners();
  }

  void _onSessionConnect(SessionConnect? event) {
    if (event == null) {
      return;
    }
    final t = sessionTopic(event) ?? '<unknown>';
    PopupCoordinator.I.log('WC:event session_connect topic:$t');
    _setConnectionState(WalletConnectState.ready, reason: 'session connect');
    unawaited(_refreshActiveSessions());
  }

  void _onSessionDelete(SessionDelete? event) {
    _status = 'ready';
    _cancelPendingCompleterIfActive(
      reason: 'Session deleted.',
      clearQueued: true,
    );
    _setConnectionState(WalletConnectState.ready, reason: 'session deleted');
    unawaited(_refreshActiveSessions());
  }

  Future<void> _refreshActiveSessions() async {
    final client = _client;
    if (client == null) {
      return;
    }

    final previous = <String, WalletConnectSessionInfo>{
      for (final info in _sessionInfos) info.topic: info,
    };
    final sessions = client.sessions.getAll();
    final infos = sessions
        .map(
          (session) => _sessionDataToInfo(
            session,
            previousInfo: previous[session.topic],
          ),
        )
        .toList(growable: false);
    _setSessionInfos(infos);
    await _persistSessions();
  }

  WalletConnectSessionInfo _sessionDataToInfo(
    SessionData session, {
    WalletConnectSessionInfo? previousInfo,
  }) {
    final info = WalletConnectSessionInfo.fromSessionData(session);
    if (previousInfo == null) {
      return info;
    }
    return info.copyWith(
      updatedAt: DateTime.now(),
    );
  }

  @override
  void dispose() {
    final client = _client;
    if (client != null) {
      client.onSessionProposal.unsubscribe(_onSessionProposal);
      client.onSessionRequest.unsubscribe(_onSessionRequest);
      client.onSessionConnect.unsubscribe(_onSessionConnect);
      client.onSessionDelete.unsubscribe(_onSessionDelete);
    }
    if (_walletListenerAttached) {
      final api = walletApi;
      if (api is ChangeNotifier) {
        api.removeListener(_handleWalletUpdated);
      }
      _walletListenerAttached = false;
    }
    if (!_requestEventsController.isClosed) {
      _requestEventsController.close();
    }
    if (_lifecycleObserverAttached) {
      WidgetsBinding.instance.removeObserver(this);
      _lifecycleObserverAttached = false;
    }
    _setConnectionState(
      WalletConnectState.disconnected,
      reason: 'service disposed',
    );
    super.dispose();
  }

  void _registerAccountAndHandlers() {
    final client = _client;
    if (client == null) {
      return;
    }

    final walletAddress = walletApi.getAddress()?.hexEip55;

    if (walletAddress == null) {
      _lastErrorDebug = 'registerAccount skipped: no wallet address';
      notifyListeners();
      return;
    }

    final errors = <String>[];

    for (final chainId in _supportedChains) {
      try {
        client.registerAccount(
          chainId: chainId,
          accountAddress: walletAddress,
        );
      } catch (error) {
        errors.add('registerAccount($chainId) failed: $error');
      }

      for (final eventName in _supportedEvents) {
        try {
          client.registerEventEmitter(
            chainId: chainId,
            event: eventName,
          );
        } catch (error) {
          errors.add('registerEventEmitter($chainId/$eventName) failed: $error');
        }
      }

      for (final methodName in _supportedMethods) {
        try {
          final handler = methodName == 'personal_sign'
              ? _handlePersonalSign
              : _handleEthSendTransaction;
          client.registerRequestHandler(
            chainId: chainId,
            method: methodName,
            handler: handler,
          );
        } catch (error) {
          errors.add('registerRequestHandler($chainId/$methodName) failed: $error');
        }
      }
    }

    if (errors.isNotEmpty) {
      _lastErrorDebug = errors.join(' | ');
    } else {
      _lastErrorDebug = '';
    }
    notifyListeners();

    _handlersRegistered = true;
  }

  void _onSessionRequest(SessionRequestEvent? event) {
    if (event == null) {
      return;
    }
    final method = event.params.request.method;
    PopupCoordinator.I.log('WC:event session_request $method');
    final t = sessionTopic(event) ?? '<unknown>';
    debugPrint(
      'WC session_request topic=$t method=$method',
    );
  }

  Future<String> _handlePersonalSign(String topic, dynamic params) async {
    final extraction = _extractRequestDetails(topic, 'personal_sign', params);
    final request = WalletConnectPendingRequest(
      topic: topic,
      requestId: extraction.requestId,
      method: 'personal_sign',
      params: extraction.params,
      chainId: extraction.chainId,
    );

    try {
      _validateBeforePrompt(
        topic: topic,
        method: 'personal_sign',
        chainId: extraction.chainId,
      );
    } on WalletConnectError catch (error) {
      _lastRequestDebug =
          'auto-reject personal_sign on ${extraction.chainId ?? 'unknown chain'}: ${error.message}';
      _lastErrorDebug = 'auto reject ${error.code}: ${error.message}';
      _emitRequestEvent(
        status: WalletConnectRequestStatus.rejected,
        request: request,
        error: error.message,
      );
      _recordActivity(
        method: 'personal_sign',
        status: WalletConnectRequestStatus.rejected,
        summary: error.message,
        chainId: extraction.chainId,
        requestId: request.requestId,
        error: error.message,
      );
      _markRequestHandled(request.requestId);
      notifyListeners();
      throw error;
    }

    final chainLabel = extraction.chainId ?? 'unknown';
    _lastRequestDebug =
        'personal_sign chain=$chainLabel topic=$topic params=${extraction.params}';
    _lastErrorDebug = '';
    final Future<String> requestFuture = _enqueuePendingRequest(request);
    _emitRequestEvent(
      status: WalletConnectRequestStatus.pending,
      request: request,
    );
    notifyListeners();

    return requestFuture;
  }

  Future<String> _handleEthSendTransaction(String topic, dynamic params) async {
    final extraction =
        _extractRequestDetails(topic, 'eth_sendTransaction', params);
    final request = WalletConnectPendingRequest(
      topic: topic,
      requestId: extraction.requestId,
      method: 'eth_sendTransaction',
      params: extraction.params,
      chainId: extraction.chainId,
    );

    try {
      _validateBeforePrompt(
        topic: topic,
        method: 'eth_sendTransaction',
        chainId: extraction.chainId,
      );
    } on WalletConnectError catch (error) {
      _lastRequestDebug =
          'auto-reject eth_sendTransaction on ${extraction.chainId ?? 'unknown chain'}: ${error.message}';
      _lastErrorDebug = 'auto reject ${error.code}: ${error.message}';
      _emitRequestEvent(
        status: WalletConnectRequestStatus.rejected,
        request: request,
        error: error.message,
      );
      _recordActivity(
        method: 'eth_sendTransaction',
        status: WalletConnectRequestStatus.rejected,
        summary: error.message,
        chainId: extraction.chainId,
        requestId: request.requestId,
        error: error.message,
      );
      _markRequestHandled(request.requestId);
      notifyListeners();
      throw error;
    }

    final chainLabel = extraction.chainId ?? 'unknown';
    _lastRequestDebug =
        'eth_sendTransaction chain=$chainLabel topic=$topic params=${extraction.params}';
    _lastErrorDebug = '';
    final Future<String> requestFuture = _enqueuePendingRequest(request);
    _emitRequestEvent(
      status: WalletConnectRequestStatus.pending,
      request: request,
    );
    notifyListeners();

    return requestFuture;
  }

  void _cancelPendingCompleterIfActive({
    String? reason,
    bool clearQueued = false,
  }) {
    if (_pendingRequestQueue.isEmpty) {
      return;
    }

    final _QueuedRequest active = _pendingRequestQueue.first;
    final WalletConnectPendingRequest request = active.request;
    final Completer<String> completer = active.completer;
    final String message =
        reason ?? 'Request cancelled because the session is no longer active.';

    if (!completer.isCompleted) {
      completer.completeError(
        WalletConnectError(
          code: 4001,
          message: message,
        ),
      );
    }

    _processingRequestIds.remove(request.requestId);
    _markRequestHandled(request.requestId);
    _emitRequestEvent(
      status: WalletConnectRequestStatus.rejected,
      request: request,
      error: message,
    );
    _recordActivity(
      method: request.method,
      status: WalletConnectRequestStatus.rejected,
      summary: message,
      chainId: request.chainId,
      requestId: request.requestId,
      error: message,
    );
    _advanceRequestQueue(clearRemainingQueue: clearQueued);
  }

  int _parseRequestId(String requestId) {
    final int? parsed = int.tryParse(requestId);
    if (parsed == null) {
      throw ArgumentError.value(
        requestId,
        'requestId',
        'Must be a valid integer',
      );
    }
    return parsed;
  }

  Future<void> rejectRequest(
    String requestId, {
    String? reason,
  }) async {
    final int id = _parseRequestId(requestId);
    final WalletConnectPendingRequest? request = _pendingRequest;
    if (request != null &&
        request.requestId == id &&
        request.method == 'session_proposal') {
      throw StateError('Use rejectSessionProposal for session proposals');
    }
    await _rejectPendingRequest(id, reason: reason);
  }

  Future<void> rejectSessionProposal(
    String requestId, {
    String? reason,
  }) async {
    final int id = _parseRequestId(requestId);
    await _rejectPendingRequest(id, reason: reason);
  }

  Future<void> _rejectPendingRequest(int requestId, {String? reason}) async {
    if (_isRequestHandled(requestId)) {
      return;
    }
    final WalletConnectPendingRequest? request = _pendingRequest;
    final Completer<String>? completer = _pendingRequestCompleter;
    if (request == null || request.requestId != requestId || completer == null) {
      if (_processingRequestIds.contains(requestId)) {
        return;
      }
      throw StateError('Request $requestId is not currently pending');
    }

    if (_processingRequestIds.contains(requestId)) {
      return;
    }
    _processingRequestIds.add(requestId);

    if (request.method == 'session_proposal') {
      final client = _client;
      if (client != null) {
        final Map<String, dynamic> data = _asStringKeyedMap(request.params);
        final int proposalId =
            (data['proposalId'] as int?) ?? request.requestId;
        try {
          await client.reject(
            id: proposalId,
            reason: Errors.getSdkError(Errors.USER_REJECTED_CHAINS),
          );
        } catch (error, stackTrace) {
          debugPrint('WalletConnect proposal reject failed: $error\n$stackTrace');
        }
      }
      _pairingInProgress = false;
      _pairingError = reason ?? 'User rejected the request.';
      _pendingSessionProposal = null;
      lastError = _pairingError;
    }

    final String message = reason ?? 'User rejected the request.';
    if (!completer.isCompleted) {
      completer.completeError(
        WalletConnectError(
          code: 4001,
          message: message,
        ),
      );
    }
    _lastRequestDebug =
        'rejected ${request.method} id=${request.requestId} via completer';
    _lastErrorDebug = 'error 4001: $message';
    _emitRequestEvent(
      status: WalletConnectRequestStatus.rejected,
      request: request,
      error: message,
    );
    _recordActivity(
      method: request.method,
      status: WalletConnectRequestStatus.rejected,
      summary: message,
      chainId: request.chainId,
      requestId: request.requestId,
      error: message,
    );
    _markRequestHandled(requestId);
    _pendingRequestCompleter = null;
    _processingRequestIds.remove(requestId);
    _advanceRequestQueue();
  }

  Future<void> approveRequest(String requestId) async {
    final int id = _parseRequestId(requestId);
    final WalletConnectPendingRequest? request = _pendingRequest;
    if (request != null &&
        request.requestId == id &&
        request.method == 'session_proposal') {
      throw StateError('Use approveSessionProposal for session proposals');
    }
    await _approvePendingRequest(id);
  }

  Future<void> approveSessionProposal(String requestId) async {
    final int id = _parseRequestId(requestId);
    await _approvePendingRequest(id);
  }

  Future<void> _approvePendingRequest(int requestId) async {
    if (_isRequestHandled(requestId)) {
      return;
    }
    final WalletConnectPendingRequest? request = _pendingRequest;
    final Completer<String>? completer = _pendingRequestCompleter;
    if (request == null || request.requestId != requestId || completer == null) {
      if (_processingRequestIds.contains(requestId)) {
        return;
      }
      throw StateError('Request $requestId is not currently pending');
    }

    if (_processingRequestIds.contains(requestId)) {
      return;
    }
    _processingRequestIds.add(requestId);

    _emitRequestEvent(
      status: WalletConnectRequestStatus.broadcasting,
      request: request,
    );
    _recordActivity(
      method: request.method,
      status: WalletConnectRequestStatus.broadcasting,
      summary: 'Processing request…',
      chainId: request.chainId,
      requestId: request.requestId,
    );

    try {
      final result = await _resolvePendingRequest(request);
      if (!completer.isCompleted) {
        completer.complete(result);
      }
      _lastRequestDebug =
          'approved ${request.method} id=${request.requestId} result=${_summarizeResult(result)}';
      _lastErrorDebug = '';
      _emitRequestEvent(
        status: WalletConnectRequestStatus.done,
        request: request,
        result: result,
      );
      _recordActivity(
        method: request.method,
        status: WalletConnectRequestStatus.done,
        summary: result,
        chainId: request.chainId,
        requestId: request.requestId,
        result: result,
      );
      _markRequestHandled(requestId);
      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint('WalletConnect approve error: $error\n$stackTrace');
      final WalletConnectRequestException wrappedError =
          error is WalletConnectRequestException
              ? error
              : WalletConnectRequestException('$error');
      if (!completer.isCompleted) {
        completer.completeError(wrappedError);
      }
      _lastErrorDebug = 'approve failed: ${wrappedError.message}';
      final WalletConnectRequestStatus failureStatus =
          wrappedError.isRejected
              ? WalletConnectRequestStatus.rejected
              : WalletConnectRequestStatus.error;
      _emitRequestEvent(
        status: failureStatus,
        request: request,
        error: wrappedError.message,
      );
      _recordActivity(
        method: request.method,
        status: failureStatus,
        summary: wrappedError.message,
        chainId: request.chainId,
        requestId: request.requestId,
        error: wrappedError.message,
      );
      _markRequestHandled(requestId);
      notifyListeners();
      throw wrappedError;
    } finally {
      _pendingRequestCompleter = null;
      _processingRequestIds.remove(requestId);
      _advanceRequestQueue();
    }
  }

  Future<String> _resolvePendingRequest(WalletConnectPendingRequest request) {
    switch (request.method) {
      case 'session_proposal':
        return _approveSessionProposal(request);
      case 'personal_sign':
        return _signPersonalMessage(request);
      case 'eth_sendTransaction':
        return _sendAndBroadcastTransaction(request);
      default:
        throw WalletConnectRequestException(
          'Unsupported method ${request.method}',
        );
    }
  }

  Future<String> _signPersonalMessage(WalletConnectPendingRequest request) async {
    final params = _asList(request.params);
    if (params.isEmpty) {
      throw WalletConnectRequestException('personal_sign params are empty');
    }

    final walletAddress = walletApi.getAddress();
    if (walletAddress == null) {
      throw WalletConnectRequestException('Wallet address unavailable');
    }

    String? messageParam;
    String? addressParam;

    if (params.length >= 2) {
      final first = params[0];
      final second = params[1];
      if (first is String && _looksLikeAddress(first)) {
        addressParam = first;
        if (second is String) {
          messageParam = second;
        }
      } else {
        if (first is String) {
          messageParam = first;
        }
        if (second is String && _looksLikeAddress(second)) {
          addressParam = second;
        }
      }
    }

    messageParam ??= params
        .whereType<String>()
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    if (messageParam.isEmpty) {
      throw WalletConnectRequestException('personal_sign message is missing');
    }

    addressParam ??= params.whereType<String>().firstWhere(
          (value) => _looksLikeAddress(value),
          orElse: () => walletAddress.hexEip55,
        );

    if (!_sameAddress(addressParam, walletAddress.hexEip55)) {
      debugPrint(
        'WalletConnect personal_sign address mismatch: requested=$addressParam wallet=${walletAddress.hexEip55}',
      );
    }

    final messageBytes = _messageToBytes(messageParam);
    final signature = await walletApi.signMessage(messageBytes);
    if (signature == null || signature.isEmpty) {
      throw WalletConnectRequestException('Failed to sign message');
    }

    return signature;
  }

  Future<String> _approveSessionProposal(
    WalletConnectPendingRequest request,
  ) async {
    final client = _client;
    if (client == null) {
      throw WalletConnectRequestException('WalletConnect not initialized');
    }

    final Map<String, dynamic> data = _asStringKeyedMap(request.params);
    final Map<String, Namespace>? namespaces =
        (data['namespaces'] as Map?)?.cast<String, Namespace>();
    if (namespaces == null || namespaces.isEmpty) {
      throw WalletConnectRequestException('Missing namespaces for proposal');
    }

    final int proposalId =
        (data['proposalId'] as int?) ?? request.requestId;

    try {
      await client.approve(
        id: proposalId,
        namespaces: namespaces,
      );
    } catch (error, stackTrace) {
      debugPrint('approve proposal failed: $error\n$stackTrace');
      throw WalletConnectRequestException('Failed to approve proposal: $error');
    }

    _pairingInProgress = false;
    _pairingError = null;
    _pendingSessionProposal = null;
    lastError = null;
    debugLastProposalLog =
        'approved namespaces=${namespaces.keys.join(' | ')} accounts=${namespaces.values.map((ns) => ns.accounts).toList()}';
    debugLastError = '';
    _lastErrorDebug = '';
    _status = 'connected';
    _setConnectionState(WalletConnectState.ready, reason: 'proposal approved');
    notifyListeners();
    await _refreshActiveSessions();
    return 'session approved';
  }

  Future<String> _sendAndBroadcastTransaction(
    WalletConnectPendingRequest request,
  ) async {
    final params = _asList(request.params);
    if (params.isEmpty || params.first is! Map) {
      throw WalletConnectRequestException(
        'eth_sendTransaction params must include transaction object',
      );
    }

    final walletAddress = walletApi.getAddress();
    if (walletAddress == null) {
      throw WalletConnectRequestException('Wallet address unavailable');
    }

    final txParams = Map<String, dynamic>.from(params.first as Map);
    final fromValue = txParams['from'];
    if (fromValue is String &&
        !_sameAddress(fromValue, walletAddress.hexEip55)) {
      throw WalletConnectRequestException('Transaction from does not match wallet');
    }

    final chainId = request.chainId ??
        _inferChainIdFromSession(request.topic, request.method, request.params);
    final normalizedChain = _normalizeChainId(chainId);
    if (normalizedChain == null) {
      throw WalletConnectRequestException('Unable to determine chain for request');
    }

    final network = findNetworkByCaip2(normalizedChain);
    if (network == null) {
      throw WalletConnectRequestException('Unsupported chain $normalizedChain');
    }

    txParams['chainId'] ??=
        '0x${network.chainIdNumeric.toRadixString(16)}';

    final Map<String, dynamic> baseTx = Map<String, dynamic>.from(txParams);
    final dynamic legacyGasLimit = baseTx.remove('gasLimit');
    baseTx.remove('nonce');
    if (baseTx['gas'] == null && legacyGasLimit != null) {
      baseTx['gas'] = legacyGasLimit;
    }

    return _withWeb3Client(network, (client) async {
      await _ensureGasParameters(baseTx, client);

      final String chainId = network.chainIdCaip2.toLowerCase();
      final String fromAddress = walletAddress.hexEip55;
      int attempts = 0;
      const int maxAttempts = 3;

      int currentNonce = await NonceManager.instance.getAndIncrementNonce(
        chainId: chainId,
        address: fromAddress,
        client: client,
      );

      Map<String, dynamic> workingTx = Map<String, dynamic>.from(baseTx)
        ..['nonce'] = _encodeQuantity(BigInt.from(currentNonce));

      while (true) {
        SignedTransactionDetails? signed;
        try {
          signed = await walletApi.signTransactionForNetwork(workingTx, network);
        } catch (error) {
          NonceManager.instance.invalidateNonce(
            chainId: chainId,
            address: fromAddress,
            usedNonce: currentNonce,
          );
          throw WalletConnectRequestException('$error');
        }
        if (signed == null) {
          NonceManager.instance.invalidateNonce(
            chainId: chainId,
            address: fromAddress,
            usedNonce: currentNonce,
          );
          throw WalletConnectRequestException('Failed to sign transaction.');
        }

        try {
          final String? broadcastHash =
              await walletApi.broadcastSignedTransaction(
            signed.rawTransaction,
            network,
          );
          final String hash =
              (broadcastHash == null || broadcastHash.isEmpty)
                  ? signed.hash
                  : broadcastHash;
          return hash;
        } catch (error) {
          final String message = error.toString();
          final String lower = message.toLowerCase();

          if (lower.contains('already known')) {
            return signed.hash;
          }

          if (_isNonceTooLowError(lower)) {
            if (attempts >= maxAttempts) {
              NonceManager.instance.resetChainAddress(
                chainId: chainId,
                address: fromAddress,
              );
              throw WalletConnectRequestException(
                'Transaction was already sent. Nonce already used.',
                isRejected: true,
              );
            }
            attempts++;
            NonceManager.instance.resetChainAddress(
              chainId: chainId,
              address: fromAddress,
            );
            currentNonce = await NonceManager.instance.getAndIncrementNonce(
              chainId: chainId,
              address: fromAddress,
              client: client,
            );
            workingTx = Map<String, dynamic>.from(baseTx)
              ..['nonce'] = _encodeQuantity(BigInt.from(currentNonce));
            continue;
          }

          if (lower.contains('replacement transaction underpriced')) {
            if (attempts >= maxAttempts) {
              NonceManager.instance.invalidateNonce(
                chainId: chainId,
                address: fromAddress,
                usedNonce: currentNonce,
              );
              throw WalletConnectRequestException(
                'Network rejected transaction: gas price too low for replacement.',
                isRejected: true,
              );
            }
            attempts++;
            workingTx = Map<String, dynamic>.from(workingTx);
            _bumpGasFees(workingTx);
            continue;
          }

          NonceManager.instance.invalidateNonce(
            chainId: chainId,
            address: fromAddress,
            usedNonce: currentNonce,
          );
          throw WalletConnectRequestException(message);
        }
      }
    });
  }

  Future<T> _withWeb3Client<T>(
    NetworkConfig network,
    Future<T> Function(Web3Client client) action,
  ) async {
    final Web3Client client = Web3Client(network.rpcUrl, http.Client());
    try {
      return await action(client);
    } finally {
      client.dispose();
    }
  }

  Future<void> _ensureGasParameters(
    Map<String, dynamic> transaction,
    Web3Client client,
  ) async {
    final BigInt? gasPrice = _parseQuantity(transaction['gasPrice']);
    final BigInt? maxFeePerGas = _parseQuantity(transaction['maxFeePerGas']);
    final BigInt? maxPriorityFeePerGas =
        _parseQuantity(transaction['maxPriorityFeePerGas']);

    if ((gasPrice == null || gasPrice == BigInt.zero) &&
        maxFeePerGas == null &&
        maxPriorityFeePerGas == null) {
      final EtherAmount networkGasPrice = await client.getGasPrice();
      transaction['gasPrice'] =
          _encodeQuantity(networkGasPrice.getInWei);
    }

    final BigInt? gasLimit =
        _parseQuantity(transaction['gas'] ?? transaction['gasLimit']);
    if (gasLimit == null || gasLimit == BigInt.zero) {
      transaction['gas'] = '0x5208';
    }
  }

  void _bumpGasFees(Map<String, dynamic> transaction) {
    void bumpField(String key) {
      final BigInt? value = _parseQuantity(transaction[key]);
      if (value == null) {
        return;
      }
      final BigInt bumped = _increaseByPercent(value, 15);
      transaction[key] = _encodeQuantity(bumped);
    }

    bumpField('gasPrice');
    bumpField('maxFeePerGas');
    bumpField('maxPriorityFeePerGas');
  }

  bool _isNonceTooLowError(String lowerCasedMessage) {
    return lowerCasedMessage.contains('nonce too low') ||
        lowerCasedMessage.contains('nonce is too low') ||
        lowerCasedMessage.contains('nonce lower than expected');
  }

  BigInt _increaseByPercent(BigInt value, int percent) {
    final BigInt multiplied = (value * BigInt.from(100 + percent)) ~/
        BigInt.from(100);
    if (multiplied <= value) {
      return value + BigInt.one;
    }
    return multiplied;
  }

  BigInt? _parseQuantity(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is BigInt) {
      return value;
    }
    if (value is int) {
      return BigInt.from(value);
    }
    if (value is String) {
      if (value.isEmpty) {
        return null;
      }
      final bool isHex = value.startsWith('0x') || value.startsWith('0X');
      final String cleaned = isHex ? value.substring(2) : value;
      if (cleaned.isEmpty) {
        return BigInt.zero;
      }
      return BigInt.parse(cleaned, radix: isHex ? 16 : 10);
    }
    throw ArgumentError('Unsupported quantity type: $value');
  }

  String _encodeQuantity(BigInt value) {
    return '0x${value.toRadixString(16)}';
  }

  List<dynamic> _asList(dynamic value) {
    if (value == null) {
      return const [];
    }
    if (value is List) {
      return List<dynamic>.from(value);
    }
    return <dynamic>[value];
  }

  Map<String, dynamic> _asStringKeyedMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, dynamic val) => MapEntry(key.toString(), val));
    }
    return <String, dynamic>{};
  }

  Uint8List _messageToBytes(String message) {
    if (message.startsWith('0x') || message.startsWith('0X')) {
      return _hexToBytes(message);
    }
    return Uint8List.fromList(utf8.encode(message));
  }

  Uint8List _hexToBytes(String value) {
    final cleaned = value.startsWith('0x') || value.startsWith('0X')
        ? value.substring(2)
        : value;
    if (cleaned.isEmpty) {
      return Uint8List(0);
    }
    if (cleaned.length.isOdd) {
      throw WalletConnectRequestException('Invalid hex string length');
    }
    final result = Uint8List(cleaned.length ~/ 2);
    for (int i = 0; i < cleaned.length; i += 2) {
      final byteString = cleaned.substring(i, i + 2);
      final byteValue = int.tryParse(byteString, radix: 16);
      if (byteValue == null) {
        throw WalletConnectRequestException('Invalid hex character in message');
      }
      result[i ~/ 2] = byteValue;
    }
    return result;
  }

  bool _looksLikeAddress(String value) {
    final normalized = value.toLowerCase();
    return normalized.startsWith('0x') && normalized.length == 42;
  }

  bool _sameAddress(String a, String b) {
    return _normalizeAddress(a) == _normalizeAddress(b);
  }

  String _normalizeAddress(String value) {
    final lower = value.toLowerCase();
    return lower.startsWith('0x') ? lower.substring(2) : lower;
  }

  String _summarizeResult(String value) {
    if (value.length <= 12) {
      return value;
    }
    return '${value.substring(0, 12)}…';
  }

  List<String> _extractChainsFromNamespace(Namespace namespace) {
    final accounts = namespace.accounts;
    if (accounts.isEmpty) {
      return const <String>[];
    }
    final chains = <String>{};
    for (final account in accounts) {
      final parts = account.split(':');
      if (parts.length >= 2) {
        final candidate = '${parts[0]}:${parts[1]}';
        final normalized = _normalizeChainId(candidate);
        if (normalized != null) {
          chains.add(normalized);
        }
      }
    }
    return chains.toList(growable: false);
  }
}
