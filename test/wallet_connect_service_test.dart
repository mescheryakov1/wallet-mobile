import 'dart:async';
import 'dart:typed_data';

import 'package:event/event.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:walletconnect_flutter_v2/apis/core/relay_client/relay_client_models.dart';
import 'package:walletconnect_flutter_v2/apis/models/basic_models.dart';
import 'package:walletconnect_flutter_v2/apis/sign_api/models/proposal_models.dart';
import 'package:walletconnect_flutter_v2/apis/sign_api/models/sign_client_events.dart';
import 'package:web3dart/web3dart.dart';

import 'package:wallet_mobile/local_wallet_api.dart';
import 'package:wallet_mobile/network_config.dart';
import 'package:wallet_mobile/wallet_connect_models.dart';
import 'package:wallet_mobile/wallet_connect_service.dart';

class _MockSignClient extends Mock implements SignClient {}

class _FakeWalletApi extends ChangeNotifier implements LocalWalletApi {
  _FakeWalletApi(this._address);

  final EthereumAddress _address;

  @override
  EthereumAddress? getAddress() => _address;

  @override
  int? getChainId() => null;

  @override
  Future<String?> broadcastSignedTransaction(
    Uint8List signedTransaction,
    NetworkConfig network,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<BigInt?> getPendingNonce(
    NetworkConfig network,
    EthereumAddress address,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<String?> sendEth({required EthereumAddress to, required EtherAmount value}) {
    throw UnimplementedError();
  }

  @override
  Future<String?> sendTransaction(Map<String, dynamic> transaction) {
    throw UnimplementedError();
  }

  @override
  Future<String?> sendTransactionOnNetwork(
    Map<String, dynamic> transaction,
    NetworkConfig network,
  ) {
    throw UnimplementedError();
  }

  @override
  Future<String?> signMessage(Uint8List messageBytes) {
    throw UnimplementedError();
  }

  @override
  Future<SignedTransactionDetails?> signTransactionForNetwork(
    Map<String, dynamic> transaction,
    NetworkConfig network,
  ) {
    throw UnimplementedError();
  }
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      Uri.parse('wc:stub@2?relay-protocol=irn&symKey=stub'),
    );
  });

  test('connectFromUri retries and handles late proposals', () {
    fakeAsync((async) {
      final mockClient = _MockSignClient();
      final proposalEvent = Event<SessionProposalEvent>();
      when(() => mockClient.onSessionProposal).thenReturn(proposalEvent);
      when(() => mockClient.pair(uri: any(named: 'uri')))
          .thenAnswer((_) => Future<void>.value());

      final walletApi = _FakeWalletApi(
        EthereumAddress.fromHex('0x0000000000000000000000000000000000000001'),
      );
      final service = WalletConnectService(
        walletApi: walletApi,
        sessionProposalTimeout: const Duration(milliseconds: 50),
        androidSessionProposalTimeout: const Duration(milliseconds: 50),
        maxPairingAttempts: 2,
        initialPairingBackoff: const Duration(milliseconds: 20),
      );
      service.setTestingClient(mockClient);

      final uri =
          'wc:8a8c5ba4-5d2b-4fd2-996b-1b53ff2d0c2b@2?relay-protocol=irn&symKey=test';
      async.run((() async {
        unawaited(service.connectFromUri(uri));
      }));

      async.elapse(const Duration(milliseconds: 55));
      expect(service.pairingError, isNotNull);
      async.elapse(const Duration(milliseconds: 25));
      verify(() => mockClient.pair(uri: any(named: 'uri'))).called(2);

      final proposal = ProposalData(
        id: 1,
        expiry: DateTime.now().add(const Duration(minutes: 5)).millisecondsSinceEpoch,
        relays: [Relay('irn')],
        proposer: ConnectionMetadata(
          publicKey: 'pk',
          metadata: PairingMetadata(
            name: 'tester',
            description: 'test',
            url: 'https://example.com',
            icons: const [],
          ),
        ),
        requiredNamespaces: {
          'eip155': const RequiredNamespace(
            chains: ['eip155:1'],
            methods: ['eth_sendTransaction'],
            events: ['accountsChanged'],
          ),
        },
        optionalNamespaces: const {},
        pairingTopic: 'topic',
      );

      proposalEvent.broadcast(SessionProposalEvent(1, proposal));
      async.flushMicrotasks();

      expect(service.pairingInProgress, isFalse);
      expect(service.pairingError, isNull);
      expect(service.pendingSessionProposal, isNotNull);
    });
  });

  test('queues incoming requests without cancelling active one', () async {
    final walletApi = _FakeWalletApi(
      EthereumAddress.fromHex('0x0000000000000000000000000000000000000001'),
    );
    final service = WalletConnectService(walletApi: walletApi);

    final List<WalletConnectRequestEvent> events = <WalletConnectRequestEvent>[];
    service.requestEvents.listen(events.add);

    final WalletConnectPendingRequest first = WalletConnectPendingRequest(
      topic: 't1',
      requestId: 1,
      method: 'personal_sign',
      params: const ['0xabc', '0xdef'],
    );
    final WalletConnectPendingRequest second = WalletConnectPendingRequest(
      topic: 't1',
      requestId: 2,
      method: 'eth_sendTransaction',
      params: const [<String, String>{'from': '0x0', 'to': '0x1'}],
    );
    final WalletConnectPendingRequest third = WalletConnectPendingRequest(
      topic: 't1',
      requestId: 3,
      method: 'personal_sign',
      params: const ['0x123', '0x456'],
    );

    final List<Future<String>> requestFutures = <Future<String>>[
      service.enqueueRequestForTesting(first),
      service.enqueueRequestForTesting(second),
      service.enqueueRequestForTesting(third),
    ];

    expect(service.pendingRequest?.requestId, 1);
    expect(service.queuedRequests.map((request) => request.requestId),
        orderedEquals(<int>[1, 2, 3]));

    final pendingEvents = events
        .where((event) => event.status == WalletConnectRequestStatus.pending)
        .map((event) => event.request.requestId)
        .toList(growable: false);
    expect(pendingEvents, orderedEquals(<int>[1, 2, 3]));

    expect(() => service.approveRequest('2'), throwsStateError);
    expect(() => service.rejectRequest('2'), throwsStateError);

    await service.rejectRequest('1');
    expect(service.pendingRequest?.requestId, 2);
    await service.rejectRequest('2');
    expect(service.pendingRequest?.requestId, 3);
    await service.rejectRequest('3');

    for (final Future<String> future in requestFutures) {
      await expectLater(future, throwsA(isA<WalletConnectError>()));
    }

    expect(service.pendingRequest, isNull);
    expect(service.queuedRequests, isEmpty);
  });

  test('logs cancellation diagnostics without UI spam and formats errors', () async {
    final walletApi = _FakeWalletApi(
      EthereumAddress.fromHex('0x0000000000000000000000000000000000000001'),
    );
    final service = WalletConnectService(walletApi: walletApi);

    final List<WalletConnectRequestEvent> events = <WalletConnectRequestEvent>[];
    service.requestEvents.listen(events.add);

    final List<String?> diagnostics = <String?>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      diagnostics.add(message);
    };

    addTearDown(() {
      debugPrint = originalDebugPrint;
      service.dispose();
    });

    const WalletConnectPendingRequest request = WalletConnectPendingRequest(
      topic: 't-cancel',
      requestId: 101,
      method: 'personal_sign',
      params: <Object>['0xabc', '0xdef'],
    );

    await service.enqueueRequestForTesting(request);

    service.cancelActiveRequestForTesting(
      reason: 'Pairing timeout after inactivity',
      clearQueued: true,
      source: 'test_cancel',
    );

    expect(events, isNotEmpty);
    final WalletConnectRequestEvent event = events.last;
    expect(event.status, WalletConnectRequestStatus.rejected);
    expect(
      event.error,
      'auto_reject/timeout: Pairing timeout after inactivity (id=101, method=personal_sign)',
    );

    final String? lastLog = diagnostics.whereType<String>().last;
    expect(lastLog, contains('source=test_cancel'));
    expect(lastLog, contains('active=101/personal_sign'));
    expect(lastLog, contains('queue=101'));
    expect(lastLog, contains('platform='));
  });

  test('auto rejection errors encode cause for validation races', () async {
    final walletApi = _FakeWalletApi(
      EthereumAddress.fromHex('0x0000000000000000000000000000000000000001'),
    );
    final service = WalletConnectService(walletApi: walletApi);

    final List<WalletConnectRequestEvent> events = <WalletConnectRequestEvent>[];
    service.requestEvents.listen(events.add);

    await expectLater(
      service.handlePersonalSignForTesting('topic', <Object>['0xabc', '0xdef']),
      throwsA(isA<WalletConnectError>()),
    );

    expect(events, isNotEmpty);
    final WalletConnectRequestEvent event = events.last;
    expect(event.status, WalletConnectRequestStatus.rejected);
    expect(event.error, isNotNull);
    expect(event.error, startsWith('auto_reject/race:'));
    expect(event.error, contains('id='));
    expect(event.error, contains('method=personal_sign'));
  });

  test('WalletConnectRequestQueue preserves first pending entry order', () {
    final queue = WalletConnectRequestQueue();

    final WalletConnectRequestLogEntry first = WalletConnectRequestLogEntry(
      request: WalletConnectPendingRequest(
        topic: 't1',
        requestId: 10,
        method: 'personal_sign',
        params: const ['0x0'],
      ),
      status: WalletConnectRequestStatus.pending,
      timestamp: DateTime.utc(2024, 1, 1),
    );

    final WalletConnectRequestLogEntry second = WalletConnectRequestLogEntry(
      request: WalletConnectPendingRequest(
        topic: 't1',
        requestId: 11,
        method: 'eth_sendTransaction',
        params: const [<String, String>{'from': '0x0', 'to': '0x1'}],
      ),
      status: WalletConnectRequestStatus.pending,
      timestamp: DateTime.utc(2024, 1, 2),
    );

    queue.enqueue(first);
    queue.enqueue(second);

    expect(queue.firstPendingLog?.request.requestId, 10);
    expect(queue.entries.map((entry) => entry.request.requestId),
        orderedEquals(<int>[10, 11]));
  });
}
