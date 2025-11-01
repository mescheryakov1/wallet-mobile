import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:walletconnect_flutter_v2/walletconnect_flutter_v2.dart';

import 'local_wallet_api.dart';

const String _defaultWalletConnectProjectId =
    'ac79370327e3526ba018428bc44831f1';

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

class WalletConnectService extends ChangeNotifier {
  WalletConnectService({
    required this.walletApi,
    String? projectId,
  }) : projectId = projectId ?? _defaultWalletConnectProjectId;

  final LocalWalletApi walletApi;
  final String projectId;

  final List<String> activeSessions = [];

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

  Future<void> init() async {
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

      _client = await SignClient.createInstance(
        projectId: projectId,
        metadata: metadata,
      );

      _client!.onSessionProposal.subscribe(_onSessionProposal);
      _client!.onSessionConnect.subscribe(_onSessionConnect);
      _client!.onSessionDelete.subscribe(_onSessionDelete);

      if (!_handlersRegistered) {
        _registerAccountAndHandlers();
      }

      _refreshActiveSessions();
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

    final dappName = proposal.proposer.metadata.name ?? 'unknown dapp';
    if (!activeSessions.contains(dappName)) {
      activeSessions.add(dappName);
    }
    _status = 'connected';
    debugLastProposalLog =
        'approved namespaces=${namespaces.keys.toList()}';
    debugLastError = '';
    _lastErrorDebug = '';
    notifyListeners();
  }

  void _onSessionConnect(SessionConnect? event) {
    if (event == null) {
      return;
    }
    _refreshActiveSessions();
  }

  void _onSessionDelete(SessionDelete? event) {
    activeSessions.clear();
    _status = 'ready';
    _clearPendingRequest();
  }

  void _refreshActiveSessions() {
    final client = _client;
    if (client == null) {
      return;
    }

    activeSessions
      ..clear()
      ..addAll(
        client.sessions
            .getAll()
            .map((session) => session.peer.metadata.name)
            .where((name) => name.isNotEmpty),
      );
    notifyListeners();
  }

  @override
  void dispose() {
    final client = _client;
    if (client != null) {
      client.onSessionProposal.unsubscribe(_onSessionProposal);
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
          'personal_sign approved with result length=${result.length}';
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
          'eth_sendTransaction approved with result length=${result.length}';
      notifyListeners();
      return result;
    } finally {
      _pendingRequestCompleter = null;
    }
  }

  void _cancelPendingCompleterIfActive() {
    if (_pendingRequestCompleter != null) {
      if (!_pendingRequestCompleter!.isCompleted) {
        _pendingRequestCompleter!
            .completeError(Errors.getSdkError(Errors.USER_REJECTED_SIGN));
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
      completer.completeError(Errors.getSdkError(Errors.USER_REJECTED_SIGN));
    }
    _lastRequestDebug =
        'rejected ${request.method} id=${request.requestId} via completer';
    _lastErrorDebug = '';
    _pendingRequestCompleter = null;
    _clearPendingRequest();
  }

  Future<void> approvePendingRequest() async {
    final completer = _pendingRequestCompleter;
    final request = _pendingRequest;
    if (completer == null || request == null) {
      return;
    }

    final result = _buildFakeResultFor(request);
    if (!completer.isCompleted) {
      completer.complete(result);
    }
    _lastRequestDebug =
        'approved placeholder for ${request.method} id=${request.requestId}';
    _lastErrorDebug = '';
    _pendingRequestCompleter = null;
    _clearPendingRequest();
  }

  String _buildFakeResultFor(PendingWcRequest request) {
    switch (request.method) {
      case 'personal_sign':
        return _fakeSignatureHex();
      case 'eth_sendTransaction':
        return _fakeTxHashHex();
      default:
        return _fakeSignatureHex();
    }
  }

  String _fakeSignatureHex() {
    final String r = List<String>.filled(32, '11').join();
    final String s = List<String>.filled(32, '22').join();
    const String v = '1b';
    return '0x$r$s$v';
  }

  String _fakeTxHashHex() {
    const String chunk = 'aa';
    final String body = List<String>.filled(32, chunk).join();
    return '0x$body';
  }
}
