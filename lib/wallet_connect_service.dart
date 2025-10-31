import 'dart:typed_data';

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
  String debugLastRequestLog = '';
  String debugLastRequestError = '';

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
      _client!.onSessionRequest.subscribe(_onSessionRequest);
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

    debugLastProposalLog =
        'RAW event=${event.toString()} | params=${event.params.toString()}';
    debugLastError = '';
    notifyListeners();

    final proposal = event.params;
    final requiredNamespaces = proposal.requiredNamespaces;
    final optionalNamespaces = proposal.optionalNamespaces;
    final requestedNamespaces =
        requiredNamespaces.isNotEmpty ? requiredNamespaces : (optionalNamespaces ?? {});

    debugLastProposalLog =
        'proposal namespaceKeys=${requestedNamespaces.keys.toList()} '
        'req=${requiredNamespaces.keys.toList()} opt=${optionalNamespaces?.keys.toList()}';
    debugLastError = '';
    notifyListeners();

    debugPrint(
      'WC Proposal namespaces: ${requestedNamespaces.keys.toList()} '
      '(req=${requiredNamespaces.keys.toList()}, opt=${optionalNamespaces?.keys.toList()})',
    );

    if (requestedNamespaces.isEmpty) {
      debugLastError = 'reject: no namespaces at all';
      await client.reject(
        id: event.id,
        reason: Errors.getSdkError(Errors.UNSUPPORTED_NAMESPACE_KEY),
      );
      notifyListeners();
      return;
    }

    final selectedEntry = requestedNamespaces.entries.firstWhere(
      (entry) => entry.key.startsWith('eip155'),
      orElse: () => requestedNamespaces.entries.first,
    );

    final namespaceKey = selectedEntry.key;
    final requestedNamespace = selectedEntry.value;

    final address = walletApi.getAddress();
    if (address == null) {
      debugLastError = 'reject: UNSUPPORTED_ACCOUNTS no address available';
      await client.reject(
        id: event.id,
        reason: Errors.getSdkError(Errors.UNSUPPORTED_ACCOUNTS),
      );
      notifyListeners();
      return;
    }

    final requestedChains = requestedNamespace.chains ?? const <String>[];
    final requestedMethods = requestedNamespace.methods ?? const <String>[];
    final requestedEvents = requestedNamespace.events ?? const <String>[];

    final accounts = <String>[];
    for (final chain in requestedChains) {
      accounts.add('$chain:${address.hexEip55}');
    }
    if (accounts.isEmpty) {
      final walletChainId = walletApi.getChainId();
      if (walletChainId != null) {
        accounts.add('eip155:$walletChainId:${address.hexEip55}');
      }
    }

    if (accounts.isEmpty) {
      debugLastError = 'reject: UNSUPPORTED_CHAINS no chains requested and no wallet chain';
      await client.reject(
        id: event.id,
        reason: Errors.getSdkError(Errors.UNSUPPORTED_CHAINS),
      );
      notifyListeners();
      return;
    }

    debugLastProposalLog =
        'about to approve ns=$namespaceKey chains=$requestedChains '
        'accounts=$accounts methods=$requestedMethods events=$requestedEvents';
    debugLastError = '';
    notifyListeners();

    final namespaces = <String, Namespace>{
      namespaceKey: Namespace(
        accounts: accounts,
        methods: requestedMethods,
        events: requestedEvents,
      ),
    };

    try {
      await client.approve(
        id: event.id,
        namespaces: namespaces,
      );
    } catch (e, st) {
      debugLastError = 'approve threw: $e';
      debugPrint('approve exception: $e\n$st');
      notifyListeners();
      return;
    }

    debugPrint(
      'WC Proposal approved for $namespaceKey with accounts=$accounts '
      'methods=$requestedMethods events=$requestedEvents',
    );

    final dappName = proposal.proposer.metadata.name ?? 'unknown dapp';
    if (!activeSessions.contains(dappName)) {
      activeSessions.add(dappName);
    }
    _status = 'connected';
    debugLastProposalLog =
        'approved ns=$namespaceKey accounts=$accounts';
    debugLastError = '';
    notifyListeners();
  }

  Future<void> _onSessionRequest(SessionRequestEvent? event) async {
    final client = _client;
    if (client == null || event == null) {
      return;
    }

    final topic = event.topic;
    final requestId = event.id;
    final method = event.method;
    final rawParams = event.params;

    debugLastRequestLog =
        'req method=$method params=$rawParams topic=$topic id=$requestId';
    debugLastRequestError = '';
    notifyListeners();

    Future<void> sendSuccess(String resultHex) async {
      await client.respondSessionRequest(
        topic: topic,
        response: JsonRpcResponse<String>(
          id: requestId,
          result: resultHex,
        ),
      );
      debugLastRequestLog =
          'responded success $method resultLen=${resultHex.length}';
      debugLastRequestError = '';
      notifyListeners();
    }

    Future<void> sendError(String message) async {
      await client.respondSessionRequest(
        topic: topic,
        response: JsonRpcResponse<String>(
          id: requestId,
          error: JsonRpcError(
            code: 5000,
            message: message,
          ),
        ),
      );
      debugLastRequestLog = 'responded error $method message=$message';
      debugLastRequestError = 'error for $method: $message';
      notifyListeners();
    }

    if (method == 'personal_sign') {
      final paramsList = rawParams is List ? rawParams : <dynamic>[];
      String? messageHex;
      for (final param in paramsList) {
        if (param is String && param.startsWith('0x')) {
          messageHex = param;
          break;
        }
      }

      if (messageHex == null) {
        await sendError('no message hex');
        return;
      }

      Uint8List _hexToBytes(String hex) {
        final cleaned = hex.startsWith('0x') ? hex.substring(2) : hex;
        final length = cleaned.length;
        final result = Uint8List(length ~/ 2);
        for (int i = 0; i < length; i += 2) {
          result[i ~/ 2] =
              int.parse(cleaned.substring(i, i + 2), radix: 16);
        }
        return result;
      }

      Uint8List messageBytes;
      try {
        messageBytes = _hexToBytes(messageHex);
      } catch (error) {
        await sendError('invalid hex: $error');
        return;
      }

      final signature = await walletApi.signMessage(messageBytes);
      if (signature == null) {
        await sendError('signMessage returned null');
        return;
      }

      await sendSuccess(signature);
      return;
    }

    if (method == 'eth_sendTransaction') {
      await sendError('eth_sendTransaction not supported yet');
      return;
    }

    await sendError('unsupported method $method');
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
      client.onSessionRequest.unsubscribe(_onSessionRequest);
      client.onSessionConnect.unsubscribe(_onSessionConnect);
      client.onSessionDelete.unsubscribe(_onSessionDelete);
    }
    super.dispose();
  }
}
