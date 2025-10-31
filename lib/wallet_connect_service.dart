import 'package:flutter/foundation.dart';
import 'package:walletconnect_flutter_v2/walletconnect_flutter_v2.dart';

import 'local_wallet_api.dart';

const String _defaultWalletConnectProjectId =
    'ac79370327e3526ba018428bc44831f1';

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

  String get status => _status;
  String? get lastRequestDebug => _lastRequestDebug;
  String? get lastErrorDebug => _lastErrorDebug;

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

    if (generatedNamespaces.isEmpty) {
      debugLastError = 'approveSession aborted: no generated namespaces';
      _lastErrorDebug = 'approveSession missing generated namespaces';
      notifyListeners();
      return;
    }

    try {
      await client.approveSession(
        id: event.id,
        namespaces: generatedNamespaces,
      );
    } catch (e, st) {
      debugLastError = 'approveSession threw: $e';
      _lastErrorDebug = 'approveSession failed: $e';
      debugPrint('approveSession exception: $e\n$st');
      notifyListeners();
      return;
    }

    final dappName = proposal.proposer.metadata.name ?? 'unknown dapp';
    if (!activeSessions.contains(dappName)) {
      activeSessions.add(dappName);
    }
    _status = 'connected';
    debugLastProposalLog =
        'approved namespaces=${generatedNamespaces.keys.toList()}';
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
    notifyListeners();
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
      var registered = false;
      try {
        client.registerAccount(
          chainId: chainId,
          account: walletAddress,
        );
        registered = true;
      } catch (_) {
        try {
          client.registerAccount(
            chainId: chainId,
            accountAddress: walletAddress,
          );
          registered = true;
        } catch (error) {
          _lastErrorDebug = 'registerAccount failed: $error';
          notifyListeners();
        }
      }

      if (registered) {
        _lastErrorDebug = '';
        notifyListeners();
      }
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

  Future<void> _handlePersonalSign(String topic, dynamic params) async {
    _lastRequestDebug = 'personal_sign topic=$topic params=$params';
    _lastErrorDebug = 'reject: USER_REJECTED_SIGN';
    notifyListeners();

    throw Errors.getSdkError(Errors.USER_REJECTED_SIGN);
  }

  Future<void> _handleEthSendTransaction(String topic, dynamic params) async {
    _lastRequestDebug = 'eth_sendTransaction topic=$topic params=$params';
    _lastErrorDebug = 'reject: USER_REJECTED_SIGN';
    notifyListeners();

    throw Errors.getSdkError(Errors.USER_REJECTED_SIGN);
  }
}
