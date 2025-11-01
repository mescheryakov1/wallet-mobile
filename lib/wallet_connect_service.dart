import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:walletconnect_flutter_v2/walletconnect_flutter_v2.dart';

import 'local_wallet_api.dart';
import 'network_config.dart';
import 'wallet_connect_models.dart';

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

class _NamespaceConfig {
  _NamespaceConfig({required this.isRequired});

  bool isRequired;
  final Set<String> chains = <String>{};
  final Set<String> methods = <String>{};
  final Set<String> events = <String>{};
}

class WalletConnectRequestException implements Exception {
  WalletConnectRequestException(this.message);

  final String message;

  @override
  String toString() => message;
}

class WalletConnectService extends ChangeNotifier {
  WalletConnectService({
    required this.walletApi,
    String? projectId,
  }) : projectId = projectId ?? _defaultWalletConnectProjectId;

  final LocalWalletApi walletApi;
  final String projectId;

  final List<String> activeSessions = [];
  final List<WalletSessionInfo> _sessionInfos = [];

  SignClient? _client;
  String _status = 'disconnected';
  String debugLastProposalLog = '';
  String debugLastError = '';
  bool _handlersRegistered = false;
  String? _lastRequestDebug;
  String? _lastErrorDebug;
  WalletConnectPendingRequest? _pendingRequest;
  Completer<String>? _pendingRequestCompleter;
  WalletConnectActivityEntry? _lastActivityEntry;
  final StreamController<WalletConnectRequestEvent>
      _requestEventsController =
      StreamController<WalletConnectRequestEvent>.broadcast();

  String get status => _status;
  String? get lastRequestDebug => _lastRequestDebug;
  String? get lastErrorDebug => _lastErrorDebug;
  WalletConnectPendingRequest? get pendingRequest => _pendingRequest;
  List<WalletSessionInfo> getActiveSessions() =>
      List<WalletSessionInfo>.unmodifiable(_sessionInfos);
  bool get isConnected => _sessionInfos.isNotEmpty;
  WalletSessionInfo? get primarySessionInfo =>
      _sessionInfos.isEmpty ? null : _sessionInfos.first;
  WalletConnectPeerMetadata? get currentPeerMetadata {
    final session = primarySessionInfo;
    if (session == null) {
      return null;
    }
    if (session.peer != null) {
      return session.peer;
    }
    final icons = <String>[];
    final iconUrl = session.iconUrl;
    if (iconUrl != null && iconUrl.isNotEmpty) {
      icons.add(iconUrl);
    }
    return WalletConnectPeerMetadata(
      name: session.dappName,
      description: session.dappDescription,
      url: session.dappUrl,
      icons: icons,
    );
  }

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

  Future<void> initWalletConnect() async {
    if (_client != null) {
      return;
    }

    if (projectId.isEmpty) {
      _status = 'missing project id';
      notifyListeners();
      return;
    }

    _status = 'initializing';
    notifyListeners();

    try {
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

      await _loadPersistedSessions();

      client.onSessionProposal.subscribe(_onSessionProposal);
      client.onSessionRequest.subscribe(_onSessionRequest);
      client.onSessionConnect.subscribe(_onSessionConnect);
      client.onSessionDelete.subscribe(_onSessionDelete);

      if (!_handlersRegistered) {
        _registerAccountAndHandlers();
      }

      await _refreshActiveSessions();
      _status = 'ready';
    } catch (error, stackTrace) {
      _status = 'error: $error';
      debugPrint('WalletConnect init failed: $error\n$stackTrace');
    }

    notifyListeners();
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

  void _clearPendingRequest() {
    if (_pendingRequest != null) {
      _pendingRequest = null;
      notifyListeners();
    }
  }

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
          .map(WalletSessionInfo.fromJson)
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

  void _setSessionInfos(List<WalletSessionInfo> infos) {
    _sessionInfos
      ..clear()
      ..addAll(infos);
    activeSessions
      ..clear()
      ..addAll(
        infos
            .map((info) => info.dappName)
            .where((name) => name.isNotEmpty),
      );
    if (infos.isEmpty) {
      _lastActivityEntry = null;
    }
    notifyListeners();
  }

  void _recordActivity({
    required String method,
    required bool success,
    required String summary,
    String? chainId,
    int? requestId,
    String? result,
    String? error,
  }) {
    final status = success
        ? WalletConnectRequestStatus.approved
        : WalletConnectRequestStatus.rejected;
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

  Future<void> pairUri(String uri) async {
    final client = _client;
    if (client == null) {
      _status = 'not initialized';
      notifyListeners();
      return;
    }

    final trimmed = uri.trim();
    if (trimmed.isEmpty) {
      return;
    }

    try {
      _status = 'pairing';
      notifyListeners();

      final parsed = Uri.parse(trimmed);
      await client.pair(uri: parsed);

      _status = 'paired';
    } catch (error, stackTrace) {
      _status = 'error: $error';
      debugPrint('WalletConnect pair failed: $error\n$stackTrace');
    }

    notifyListeners();
  }

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

    debugLastProposalLog =
        'RAW event=${event.toString()} | params=${event.params.toString()}';
    debugLastError = '';
    notifyListeners();

    final proposal = event.params;
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

    try {
      await client.approve(
        id: event.id,
        namespaces: namespaces,
      );
    } catch (error, stackTrace) {
      debugLastError = 'approve threw: $error';
      _lastErrorDebug = 'approve failed: $error';
      debugPrint('approve exception: $error\n$stackTrace');
      notifyListeners();
      return;
    }

    _status = 'connected';
    debugLastProposalLog =
        'approved namespaces=${approvedDetails.join(' | ')} accounts=${namespaces.values.map((ns) => ns.accounts).toList()}';
    debugLastError = '';
    _lastErrorDebug = '';
    notifyListeners();
    unawaited(_refreshActiveSessions());
  }

  void _onSessionConnect(SessionConnect? event) {
    if (event == null) {
      return;
    }
    unawaited(_refreshActiveSessions());
  }

  void _onSessionDelete(SessionDelete? event) {
    _status = 'ready';
    _clearPendingRequest();
    unawaited(_refreshActiveSessions());
  }

  Future<void> _refreshActiveSessions() async {
    final client = _client;
    if (client == null) {
      return;
    }

    final previous = <String, WalletSessionInfo>{
      for (final info in _sessionInfos) info.topic: info,
    };
    final sessions = client.sessions.getAll();
    final infos = sessions
        .map(
          (session) => _sessionDataToInfo(
            session,
            approvedAt: previous[session.topic]?.approvedAt,
          ),
        )
        .toList(growable: false);
    _setSessionInfos(infos);
    await _persistSessions();
  }

  WalletSessionInfo _sessionDataToInfo(
    SessionData session, {
    int? approvedAt,
  }) {
    final metadata = session.peer.metadata;
    final iconUrl =
        metadata.icons.isNotEmpty ? metadata.icons.first : null;
    final peerMetadata = WalletConnectPeerMetadata(
      name: metadata.name,
      description: metadata.description,
      url: metadata.url,
      icons: metadata.icons,
    );

    final Set<String> chainIds = <String>{};
    final List<String> accounts = <String>[];
    final Set<String> methods = <String>{};
    final Set<String> events = <String>{};

    session.namespaces.forEach((_, namespace) {
      accounts.addAll(namespace.accounts);
      final namespaceChains = _extractChainsFromNamespace(namespace);
      chainIds.addAll(namespaceChains);
      methods.addAll(namespace.methods);
      events.addAll(namespace.events);
    });

    return WalletSessionInfo(
      topic: session.topic,
      dappName: metadata.name,
      dappUrl: metadata.url,
      iconUrl: iconUrl,
      dappDescription: metadata.description,
      chains: chainIds.toList(growable: false),
      accounts: accounts.toList(growable: false),
      methods: methods.map((value) => value.toLowerCase()).toList(growable: false),
      events: events.toList(growable: false),
      expiry: session.expiry,
      approvedAt: approvedAt ?? DateTime.now().millisecondsSinceEpoch,
      peer: peerMetadata,
      isActive: true,
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
    if (!_requestEventsController.isClosed) {
      _requestEventsController.close();
    }
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
    debugPrint(
      'WC session_request topic=${event.topic} method=${event.params.request.method}',
    );
  }

  Future<String> _handlePersonalSign(String topic, dynamic params) async {
    _cancelPendingCompleterIfActive();

    _pendingRequestCompleter = Completer<String>();
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
      _pendingRequestCompleter = null;
      _pendingRequest = null;
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
        success: false,
        summary: error.message,
        chainId: extraction.chainId,
        requestId: request.requestId,
        error: error.message,
      );
      notifyListeners();
      throw error;
    }

    final chainLabel = extraction.chainId ?? 'unknown';
    _lastRequestDebug =
        'personal_sign chain=$chainLabel topic=$topic params=${extraction.params}';
    _lastErrorDebug = '';
    _pendingRequest = request;
    _emitRequestEvent(
      status: WalletConnectRequestStatus.pending,
      request: request,
    );
    notifyListeners();

    try {
      final result = await _pendingRequestCompleter!.future;
      _lastRequestDebug =
          'personal_sign approved result=${_summarizeResult(result)}';
      _emitRequestEvent(
        status: WalletConnectRequestStatus.approved,
        request: request,
        result: result,
      );
      _recordActivity(
        method: 'personal_sign',
        success: true,
        summary: result,
        chainId: extraction.chainId,
        requestId: request.requestId,
        result: result,
      );
      notifyListeners();
      return result;
    } finally {
      _pendingRequestCompleter = null;
    }
  }

  Future<String> _handleEthSendTransaction(String topic, dynamic params) async {
    _cancelPendingCompleterIfActive();

    _pendingRequestCompleter = Completer<String>();
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
      _pendingRequestCompleter = null;
      _pendingRequest = null;
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
        success: false,
        summary: error.message,
        chainId: extraction.chainId,
        requestId: request.requestId,
        error: error.message,
      );
      notifyListeners();
      throw error;
    }

    final chainLabel = extraction.chainId ?? 'unknown';
    _lastRequestDebug =
        'eth_sendTransaction chain=$chainLabel topic=$topic params=${extraction.params}';
    _lastErrorDebug = '';
    _pendingRequest = request;
    _emitRequestEvent(
      status: WalletConnectRequestStatus.pending,
      request: request,
    );
    notifyListeners();

    try {
      final result = await _pendingRequestCompleter!.future;
      _lastRequestDebug =
          'eth_sendTransaction approved result=${_summarizeResult(result)}';
      _emitRequestEvent(
        status: WalletConnectRequestStatus.approved,
        request: request,
        result: result,
      );
      _recordActivity(
        method: 'eth_sendTransaction',
        success: true,
        summary: result,
        chainId: extraction.chainId,
        requestId: request.requestId,
        result: result,
      );
      notifyListeners();
      return result;
    } finally {
      _pendingRequestCompleter = null;
    }
  }

  void _cancelPendingCompleterIfActive() {
    if (_pendingRequestCompleter != null) {
      if (!_pendingRequestCompleter!.isCompleted) {
        _pendingRequestCompleter!.completeError(
          WalletConnectError(
            code: 4001,
            message: 'User rejected the request.',
          ),
        );
      }
      _pendingRequestCompleter = null;
    }
    if (_pendingRequest != null) {
      _emitRequestEvent(
        status: WalletConnectRequestStatus.rejected,
        request: _pendingRequest!,
        error: 'Request superseded by a new call.',
      );
      _clearPendingRequest();
    }
  }

  Future<void> rejectPendingRequest() async {
    final completer = _pendingRequestCompleter;
    final request = _pendingRequest;
    if (completer == null || request == null) {
      return;
    }

    if (!completer.isCompleted) {
      completer.completeError(
        WalletConnectError(
          code: 4001,
          message: 'User rejected the request.',
        ),
      );
    }
    _lastRequestDebug =
        'rejected ${request.method} id=${request.requestId} via completer';
    _lastErrorDebug = 'error 4001: User rejected the request.';
    _emitRequestEvent(
      status: WalletConnectRequestStatus.rejected,
      request: request,
      error: 'User rejected the request.',
    );
    _recordActivity(
      method: request.method,
      success: false,
      summary: 'User rejected the request.',
      chainId: request.chainId,
      requestId: request.requestId,
      error: 'User rejected the request.',
    );
    _pendingRequestCompleter = null;
    _clearPendingRequest();
  }

  Future<void> approvePendingRequest() async {
    final completer = _pendingRequestCompleter;
    final request = _pendingRequest;
    if (completer == null || request == null) {
      return;
    }

    try {
      final result = await _resolvePendingRequest(request);
      if (!completer.isCompleted) {
        completer.complete(result);
      }
      _lastRequestDebug =
          'approved ${request.method} id=${request.requestId} result=${_summarizeResult(result)}';
      _lastErrorDebug = '';
      _emitRequestEvent(
        status: WalletConnectRequestStatus.approved,
        request: request,
        result: result,
      );
      _recordActivity(
        method: request.method,
        success: true,
        summary: result,
        chainId: request.chainId,
        requestId: request.requestId,
        result: result,
      );
      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint('WalletConnect approve error: $error\n$stackTrace');
      final wrappedError = error is WalletConnectRequestException
          ? error
          : WalletConnectRequestException('$error');
      if (!completer.isCompleted) {
        completer.completeError(wrappedError);
      }
      _lastErrorDebug = 'approve failed: ${wrappedError.message}';
      _emitRequestEvent(
        status: WalletConnectRequestStatus.rejected,
        request: request,
        error: wrappedError.message,
      );
      _recordActivity(
        method: request.method,
        success: false,
        summary: wrappedError.message,
        chainId: request.chainId,
        requestId: request.requestId,
        error: wrappedError.message,
      );
      notifyListeners();
      throw wrappedError;
    } finally {
      _pendingRequestCompleter = null;
      _clearPendingRequest();
    }
  }

  Future<String> _resolvePendingRequest(WalletConnectPendingRequest request) {
    switch (request.method) {
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

    try {
      final hash = await walletApi.sendTransactionOnNetwork(txParams, network);
      if (hash == null || hash.isEmpty) {
        throw WalletConnectRequestException('Failed to send transaction');
      }
      return hash;
    } catch (error) {
      if (error is WalletConnectRequestException) {
        rethrow;
      }
      throw WalletConnectRequestException('$error');
    }
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
