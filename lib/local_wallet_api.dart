import 'dart:typed_data';

import 'package:web3dart/web3dart.dart';

import 'network_config.dart';

abstract class LocalWalletApi {
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
}
