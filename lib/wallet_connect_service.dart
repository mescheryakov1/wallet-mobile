import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:walletconnect_flutter_v2/walletconnect_flutter_v2.dart';

import 'local_wallet_api.dart';

const String _defaultWalletConnectProjectId =
    'ac79370327e3526ba018428bc44831f1';
const String _sessionsStorageKey = 'wc_sessions';

class WalletSessionInfo {
  WalletSessionInfo({
    required this.topic,
    required this.dappName,
    required this.chains,
    required this.accounts,
    this.dappUrl,
    this.iconUrl,
    this.expiry,
    this.approvedAt,
  });

  factory WalletSessionInfo.fromJson(Map<String, dynamic> json) {
    return WalletSessionInfo(
      topic: json['topic'] as String? ?? '',
      dappName: json['dappName'] as String? ?? '',
      dappUrl: json['dappUrl'] as String?,
      iconUrl: json['iconUrl'] as String?,
      chains: (json['chains'] as List?)
              ?.whereType<String>()
              .toList(growable: false) ??
          const <String>[],
      accounts: (json['accounts'] as List?)
              ?.whereType<String>()
              .toList(growable: false) ??
          const <String>[],
      expiry: json['expiry'] as int?,
      approvedAt: json['approvedAt'] as int?,
    );
  }

  final String topic;
  final String dappName;
  final List<String> chains;
  final List<String> accounts;
  final String? dappUrl;
  final String? iconUrl;
  final int? expiry;
  final int? approvedAt;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'topic': topic,
      'dappName': dappName,
      if (dappUrl != null) 'dappUrl': dappUrl,
      if (iconUrl != null) 'iconUrl': iconUrl,
      'chains': chains,
      'accounts': accounts,
      if (expiry != null) 'expiry': expiry,
      if (approvedAt != null) 'approvedAt': approvedAt,
    };
  }
}

class PendingWcRequest {
  PendingWcRequest({
    required this.topic,
    required this.requestId,
    required this.method,
    required this.params,
  });

  final String topic;
  final int requestId;
  final String method;
  final dynamic params;
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
  PendingWcRequest? _pendingRequest;
  Completer<String>? _pendingRequestCompleter;

  String get status => _status;
  String? get lastRequestDebug => _lastRequestDebug;
  String? get lastErrorDebug => _lastErrorDebug;
  PendingWcRequest? get pendingRequest => _pendingRequest;
  List<WalletSessionInfo> getActiveSessions() =>
      List<WalletSessionInfo>.unmodifiable(_sessionInfos);

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

  void _setPendingRequest(String method, String topic, dynamic params) {
    final client = _client;
    SessionRequest? matchedRequest;
    _lastErrorDebug = '';

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

    if (matchedRequest == null && (_lastErrorDebug == null || _lastErrorDebug!.isEmpty)) {
      _lastErrorDebug = 'pending request not found, using fallback id';
    }

    _pendingRequest = PendingWcRequest(
      topic: topic,
      requestId: requestId,
      method: method,
      params: requestParams,
    );
    notifyListeners();
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
    notifyListeners();
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
    final generatedNamespaces = proposal.generatedNamespaces ?? {};

    debugLastProposalLog =
        'proposal namespaceKeys=${generatedNamespaces.keys.toList()} '
        'generated=${generatedNamespaces.isNotEmpty}';
    debugLastError = '';
    notifyListeners();

    debugPrint(
      'WC Proposal generated namespaces: ${generatedNamespaces.keys.toList()}',
    );

    Map<String, Namespace> namespaces;
    if (generatedNamespaces.isNotEmpty) {
      namespaces = generatedNamespaces;
    } else {
      final requestedNamespaces = proposal.requiredNamespaces.isNotEmpty
          ? proposal.requiredNamespaces
          : (proposal.optionalNamespaces ?? {});

      final address = walletApi.getAddress();
      if (address == null) {
        debugLastError = 'reject: no address available';
        _lastErrorDebug = 'reject: UNSUPPORTED_ACCOUNTS';
        notifyListeners();
        await client.reject(
          id: event.id,
          reason: Errors.getSdkError(Errors.UNSUPPORTED_ACCOUNTS),
        );
        return;
      }

      String namespaceKey = 'eip155';
      List<String> chains = <String>[];
      List<String> methods = <String>[];
      List<String> eventsList = <String>[];

      if (requestedNamespaces.isNotEmpty) {
        final selectedEntry = requestedNamespaces.entries.firstWhere(
          (entry) => entry.key.startsWith('eip155'),
          orElse: () => requestedNamespaces.entries.first,
        );
        namespaceKey = selectedEntry.key;
        final requiredNamespace = selectedEntry.value;
        chains = List<String>.from(requiredNamespace.chains ?? const []);
        methods = List<String>.from(requiredNamespace.methods ?? const []);
        eventsList =
            List<String>.from(requiredNamespace.events ?? const []);
      }

      if (chains.isEmpty) {
        final walletChainId = walletApi.getChainId();
        final fallbackChainId = walletChainId != null
            ? 'eip155:$walletChainId'
            : 'eip155:1';
        chains = <String>[fallbackChainId];
      }

      if (methods.isEmpty) {
        methods = const ['personal_sign', 'eth_sendTransaction'];
      }

      if (eventsList.isEmpty) {
        eventsList = const ['accountsChanged', 'chainChanged'];
      }

      final accounts = chains
          .map((chain) => '$chain:${address.hexEip55}')
          .toList(growable: false);

      namespaces = <String, Namespace>{
        namespaceKey: Namespace(
          accounts: accounts,
          methods: methods,
          events: eventsList,
        ),
      };

      debugLastProposalLog =
          'manual namespaces for $namespaceKey chains=$chains accounts=$accounts';
      notifyListeners();
    }

    try {
      await client.approve(
        id: event.id,
        namespaces: namespaces,
      );
    } catch (e, st) {
      debugLastError = 'approve threw: $e';
      _lastErrorDebug = 'approve failed: $e';
      debugPrint('approve exception: $e\n$st');
      notifyListeners();
      return;
    }

    _status = 'connected';
    debugLastProposalLog =
        'approved namespaces=${namespaces.keys.toList()}';
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

    final Set<String> chainIds = <String>{};
    final List<String> accounts = <String>[];

    session.namespaces.forEach((_, namespace) {
      accounts.addAll(namespace.accounts);
      final namespaceChains = _extractChainsFromNamespace(namespace);
      chainIds.addAll(namespaceChains);
    });

    return WalletSessionInfo(
      topic: session.topic,
      dappName: metadata.name,
      dappUrl: metadata.url,
      iconUrl: iconUrl,
      chains: chainIds.toList(growable: false),
      accounts: accounts.toList(growable: false),
      expiry: session.expiry,
      approvedAt: approvedAt ?? DateTime.now().millisecondsSinceEpoch,
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
    super.dispose();
  }

  void _registerAccountAndHandlers() {
    final client = _client;
    if (client == null) {
      return;
    }

    const chainId = 'eip155:11155111';
    final walletAddress = walletApi.getAddress()?.hexEip55;

    if (walletAddress == null) {
      _lastErrorDebug = 'registerAccount skipped: no wallet address';
      notifyListeners();
    } else {
      try {
        client.registerAccount(
          chainId: chainId,
          accountAddress: walletAddress,
        );
        _lastErrorDebug = '';
      } catch (error) {
        _lastErrorDebug = 'registerAccount failed: $error';
      }
      notifyListeners();
    }

    try {
      client.registerEventEmitter(
        chainId: chainId,
        event: 'accountsChanged',
      );
      client.registerEventEmitter(
        chainId: chainId,
        event: 'chainChanged',
      );
    } catch (error) {
      _lastErrorDebug = 'registerEventEmitter failed: $error';
      notifyListeners();
    }

    client.registerRequestHandler(
      chainId: chainId,
      method: 'personal_sign',
      handler: _handlePersonalSign,
    );

    client.registerRequestHandler(
      chainId: chainId,
      method: 'eth_sendTransaction',
      handler: _handleEthSendTransaction,
    );

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
    _lastRequestDebug = 'personal_sign topic=$topic params=$params';
    _lastErrorDebug = '';
    notifyListeners();

    _setPendingRequest('personal_sign', topic, params);

    try {
      final result = await _pendingRequestCompleter!.future;
      _lastRequestDebug =
          'personal_sign approved result=${_summarizeResult(result)}';
      notifyListeners();
      return result;
    } finally {
      _pendingRequestCompleter = null;
    }
  }

  Future<String> _handleEthSendTransaction(String topic, dynamic params) async {
    _cancelPendingCompleterIfActive();

    _pendingRequestCompleter = Completer<String>();
    _lastRequestDebug = 'eth_sendTransaction topic=$topic params=$params';
    _lastErrorDebug = '';
    notifyListeners();

    _setPendingRequest('eth_sendTransaction', topic, params);

    try {
      final result = await _pendingRequestCompleter!.future;
      _lastRequestDebug =
          'eth_sendTransaction approved result=${_summarizeResult(result)}';
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
            message: 'User rejected the request',
          ),
        );
      }
      _pendingRequestCompleter = null;
    }
    if (_pendingRequest != null) {
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
          message: 'User rejected the request',
        ),
      );
    }
    _lastRequestDebug =
        'rejected ${request.method} id=${request.requestId} via completer';
    _lastErrorDebug = 'error 4001: User rejected the request';
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
      notifyListeners();
      throw wrappedError;
    } finally {
      _pendingRequestCompleter = null;
      _clearPendingRequest();
    }
  }

  Future<String> _resolvePendingRequest(PendingWcRequest request) {
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

  Future<String> _signPersonalMessage(PendingWcRequest request) async {
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
    PendingWcRequest request,
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
    if (fromValue is String && !_sameAddress(fromValue, walletAddress.hexEip55)) {
      throw WalletConnectRequestException('Transaction from does not match wallet');
    }

    final hash = await walletApi.sendTransaction(txParams);
    if (hash == null || hash.isEmpty) {
      throw WalletConnectRequestException('Failed to send transaction');
    }
    return hash;
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
      final chain = _chainFromAccount(account);
      if (chain != null) {
        chains.add(chain);
      }
    }
    return chains.toList(growable: false);
  }

  String? _chainFromAccount(String account) {
    final parts = account.split(':');
    if (parts.length >= 2) {
      return '${parts[0]}:${parts[1]}';
    }
    return null;
  }
}
