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
}
