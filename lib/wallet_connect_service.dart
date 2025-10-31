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
  bool _handlersRegistered = false;

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

      if (!_handlersRegistered) {
        _registerRequestHandlers();
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

  void _registerRequestHandlers() {
    final client = _client;
    if (client == null) {
      return;
    }

    const chainId = 'eip155:11155111';

    client.registerRequestHandler(
      chainId: chainId,
      method: 'personal_sign',
      handler: (String topic, dynamic params) async {
        debugLastRequestLog =
            'personal_sign request topic=$topic params=$params';
        debugLastRequestError = '';
        notifyListeners();

        String? messageHex;
        if (params is List) {
          for (final element in params) {
            if (element is String && element.startsWith('0x')) {
              messageHex = element;
              break;
            }
          }
        }

        if (messageHex == null) {
          debugLastRequestError = 'personal_sign no hex message';
          notifyListeners();
          throw Errors.getSdkError(Errors.USER_REJECTED_SIGN);
        }

        Uint8List hexToBytes(String hex) {
          final cleaned = hex.startsWith('0x') ? hex.substring(2) : hex;
          final length = cleaned.length;
          final result = Uint8List(length ~/ 2);
          for (int i = 0; i < length; i += 2) {
            result[i ~/ 2] =
                int.parse(cleaned.substring(i, i + 2), radix: 16);
          }
          return result;
        }

        final messageBytes = hexToBytes(messageHex);
        final signature = await walletApi.signMessage(messageBytes);
        if (signature == null) {
          debugLastRequestError = 'personal_sign signMessage returned null';
          notifyListeners();
          throw Errors.getSdkError(Errors.USER_REJECTED_SIGN);
        }

        debugLastRequestLog =
            'personal_sign success sigLen=${signature.length}';
        debugLastRequestError = '';
        notifyListeners();
        return signature;
      },
    );

    client.registerRequestHandler(
      chainId: chainId,
      method: 'eth_sendTransaction',
      handler: (String topic, dynamic params) async {
        debugLastRequestLog =
            'eth_sendTransaction request topic=$topic params=$params';
        debugLastRequestError = 'eth_sendTransaction not supported';
        notifyListeners();
        throw Errors.getSdkError(Errors.USER_REJECTED_SIGN);
      },
    );

    _handlersRegistered = true;
  }
}
