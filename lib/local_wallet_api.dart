import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:web3dart/web3dart.dart';

import 'network_config.dart';

@immutable
class SignedTransactionDetails {
  const SignedTransactionDetails({
    required this.rawTransaction,
    required this.hash,
  });

  final Uint8List rawTransaction;
  final String hash;
}

abstract class LocalWalletApi extends ChangeNotifier {
  EthereumAddress? getAddress();
  int? getChainId();
  Future<String?> signMessage(Uint8List messageBytes);
  Future<String?> sendEth({
    required EthereumAddress to,
    required EtherAmount value,
  });
  Future<String?> sendTransaction(Map<String, dynamic> transaction);
  Future<String?> sendTransactionOnNetwork(
    Map<String, dynamic> transaction,
    NetworkConfig network,
  );
  Future<SignedTransactionDetails?> signTransactionForNetwork(
    Map<String, dynamic> transaction,
    NetworkConfig network,
  );
  Future<String?> broadcastSignedTransaction(
    Uint8List signedTransaction,
    NetworkConfig network,
  );
  Future<BigInt?> getPendingNonce(
    NetworkConfig network,
    EthereumAddress address,
  );
}
