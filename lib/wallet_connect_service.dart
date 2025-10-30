import 'package:flutter/foundation.dart';
import 'package:walletconnect_flutter_v2/walletconnect_flutter_v2.dart';

import 'local_wallet_api.dart';

const String _defaultWalletConnectProjectId =
    String.fromEnvironment('WC_PROJECT_ID', defaultValue: '');

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

  String get status => _status;

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

    final address = walletApi.getAddress();
    if (address == null) {
      await client.reject(
        id: event.id,
        reason: Errors.getSdkError(Errors.UNSUPPORTED_ACCOUNTS),
      );
      return;
    }

    final chainId = walletApi.getChainId();
    if (chainId == null) {
      await client.reject(
        id: event.id,
        reason: Errors.getSdkError(Errors.UNSUPPORTED_CHAINS),
      );
      return;
    }

    final requiredNamespace = event.params.requiredNamespaces['eip155'];
    if (requiredNamespace == null) {
      await client.reject(
        id: event.id,
        reason: Errors.getSdkError(Errors.UNSUPPORTED_NAMESPACE_KEY),
      );
      return;
    }

    final requestedChains = requiredNamespace.chains ?? const [];
    final supportedChain = 'eip155:$chainId';
    if (requestedChains.isNotEmpty && !requestedChains.contains(supportedChain)) {
      await client.reject(
        id: event.id,
        reason: Errors.getSdkError(Errors.UNSUPPORTED_CHAINS),
      );
      return;
    }

    final namespaces = <String, Namespace>{
      'eip155': Namespace(
        accounts: <String>['$supportedChain:${address.hexEip55}'],
        methods: requiredNamespace.methods,
        events: requiredNamespace.events,
      ),
    };

    await client.approve(
      id: event.id,
      namespaces: namespaces,
    );

    final dappName = event.params.proposer.metadata.name;
    if (!activeSessions.contains(dappName)) {
      activeSessions.add(dappName);
    }
    _status = 'connected';
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
}
