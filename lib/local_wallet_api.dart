import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:web3dart/web3dart.dart';

import 'network_config.dart';

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
}
