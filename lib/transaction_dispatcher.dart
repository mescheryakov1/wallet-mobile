import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:web3dart/web3dart.dart';

import 'local_wallet_api.dart';
import 'network_config.dart';
import 'wallet_connect_models.dart';

enum DispatchStatus {
  ok,
  alreadyBroadcast,
  mismatchNonce,
  staleNonce,
  underpricedReplacement,
  rpcError,
}

@immutable
class DispatchResult {
  const DispatchResult({
    required this.status,
    this.txHash,
    this.errorMessage,
  });

  final DispatchStatus status;
  final String? txHash;
  final String? errorMessage;
}

class TransactionDispatcher {
  TransactionDispatcher._(this.walletApi);

  static TransactionDispatcher? _instance;

  static TransactionDispatcher instance(LocalWalletApi api) {
    final TransactionDispatcher? existing = _instance;
    if (existing != null) {
      return existing;
    }
    final TransactionDispatcher dispatcher = TransactionDispatcher._(api);
    _instance = dispatcher;
    return dispatcher;
  }

  static TransactionDispatcher get shared {
    final TransactionDispatcher? existing = _instance;
    if (existing == null) {
      throw StateError('TransactionDispatcher has not been initialized');
    }
    return existing;
  }

  final LocalWalletApi walletApi;
  final Map<String, BigInt> _nextNoncePerChainAndAddress =
      <String, BigInt>{};
  final Map<int, DispatchResult> _completedResults = <int, DispatchResult>{};
  final Map<int, Completer<DispatchResult>> _inFlightRequests =
      <int, Completer<DispatchResult>>{};
  final Map<int, String> _inFlightTxByRequestId = <int, String>{};

  Future<DispatchResult> sendTransaction({
    required WalletConnectPendingRequest request,
    required Map<String, dynamic> txParams,
    required NetworkConfig network,
  }) async {
    final DispatchResult? completed = _completedResults[request.requestId];
    if (completed != null) {
      return completed;
    }

    final Completer<DispatchResult>? existingCompleter =
        _inFlightRequests[request.requestId];
    if (existingCompleter != null) {
      return existingCompleter.future;
    }

    final String? existingHash = _inFlightTxByRequestId[request.requestId];
    if (existingHash != null) {
      final DispatchResult result = DispatchResult(
        status: DispatchStatus.alreadyBroadcast,
        txHash: existingHash,
      );
      _completedResults[request.requestId] = result;
      return result;
    }

    final Completer<DispatchResult> completer = Completer<DispatchResult>();
    _inFlightRequests[request.requestId] = completer;

    try {
      final DispatchResult result = await _dispatch(
        request: request,
        txParams: txParams,
        network: network,
      );
      _completedResults[request.requestId] = result;
      completer.complete(result);
      return result;
    } catch (error, stackTrace) {
      completer.completeError(error, stackTrace);
      rethrow;
    } finally {
      _inFlightRequests.remove(request.requestId);
    }
  }

  Future<DispatchResult> _dispatch({
    required WalletConnectPendingRequest request,
    required Map<String, dynamic> txParams,
    required NetworkConfig network,
  }) async {
    final EthereumAddress? walletAddress = walletApi.getAddress();
    if (walletAddress == null) {
      return const DispatchResult(
        status: DispatchStatus.rpcError,
        errorMessage: 'Wallet address unavailable.',
      );
    }

    final Map<String, dynamic> transaction =
        Map<String, dynamic>.from(txParams);
    final String chainId = network.chainIdCaip2.toLowerCase();
    final String nonceKey = _nonceKey(chainId, walletAddress);

    BigInt? providedNonce = _parseQuantity(transaction['nonce']);
    BigInt nonceToUse;
    if (providedNonce != null) {
      final BigInt? cached = _nextNoncePerChainAndAddress[nonceKey];
      if (cached != null && providedNonce < cached) {
        return DispatchResult(
          status: DispatchStatus.mismatchNonce,
          errorMessage:
              'Nonce $providedNonce is lower than expected $cached.',
        );
      }
      nonceToUse = providedNonce;
      _nextNoncePerChainAndAddress[nonceKey] = providedNonce;
    } else {
      final BigInt? cached = _nextNoncePerChainAndAddress[nonceKey];
      if (cached != null) {
        nonceToUse = cached;
      } else {
        final BigInt? remoteNonce =
            await walletApi.getPendingNonce(network, walletAddress);
        nonceToUse = remoteNonce ?? BigInt.zero;
      }
      transaction['nonce'] = _encodeQuantity(nonceToUse);
    }

    transaction['chainId'] ??=
        _encodeQuantity(BigInt.from(network.chainIdNumeric));

    SignedTransactionDetails? signed;
    try {
      signed = await walletApi.signTransactionForNetwork(
        transaction,
        network,
      );
    } catch (error) {
      return DispatchResult(
        status: DispatchStatus.rpcError,
        errorMessage: '$error',
      );
    }

    if (signed == null) {
      return const DispatchResult(
        status: DispatchStatus.rpcError,
        errorMessage: 'Failed to sign transaction.',
      );
    }

    try {
      final String? broadcastHash = await walletApi.broadcastSignedTransaction(
        signed.rawTransaction,
        network,
      );
      final String hashToUse =
          (broadcastHash == null || broadcastHash.isEmpty)
              ? signed.hash
              : broadcastHash;
      _inFlightTxByRequestId[request.requestId] = hashToUse;
      _nextNoncePerChainAndAddress[nonceKey] = nonceToUse + BigInt.one;
      return DispatchResult(
        status: DispatchStatus.ok,
        txHash: hashToUse,
      );
    } catch (error) {
      final String message = error.toString();
      final String lower = message.toLowerCase();
      if (lower.contains('already known')) {
        _inFlightTxByRequestId[request.requestId] = signed.hash;
        _nextNoncePerChainAndAddress[nonceKey] = nonceToUse + BigInt.one;
        return DispatchResult(
          status: DispatchStatus.ok,
          txHash: signed.hash,
        );
      }
      if (lower.contains('nonce too low') ||
          lower.contains('replacement transaction underpriced')) {
        return _retryWithFreshNonce(
          request: request,
          originalTx: transaction,
          network: network,
          walletAddress: walletAddress,
          nonceKey: nonceKey,
          originalMessage: message,
          bumpFees: lower.contains('replacement transaction underpriced'),
        );
      }
      return DispatchResult(
        status: DispatchStatus.rpcError,
        errorMessage: message,
      );
    }
  }

  Future<DispatchResult> _retryWithFreshNonce({
    required WalletConnectPendingRequest request,
    required Map<String, dynamic> originalTx,
    required NetworkConfig network,
    required EthereumAddress walletAddress,
    required String nonceKey,
    required String originalMessage,
    required bool bumpFees,
  }) async {
    final BigInt? refreshedNonce =
        await walletApi.getPendingNonce(network, walletAddress);
    if (refreshedNonce == null) {
      _nextNoncePerChainAndAddress.remove(nonceKey);
      return DispatchResult(
        status:
            bumpFees ? DispatchStatus.underpricedReplacement : DispatchStatus.staleNonce,
        errorMessage: originalMessage,
      );
    }

    _nextNoncePerChainAndAddress[nonceKey] = refreshedNonce;
    final Map<String, dynamic> retryTx =
        Map<String, dynamic>.from(originalTx)..['nonce'] = _encodeQuantity(refreshedNonce);
    if (bumpFees) {
      _bumpGasParameters(retryTx);
    }

    SignedTransactionDetails? retrySigned;
    try {
      retrySigned = await walletApi.signTransactionForNetwork(
        retryTx,
        network,
      );
    } catch (error) {
      return DispatchResult(
        status: DispatchStatus.rpcError,
        errorMessage: '$error',
      );
    }

    if (retrySigned == null) {
      return const DispatchResult(
        status: DispatchStatus.rpcError,
        errorMessage: 'Failed to sign transaction.',
      );
    }

    try {
      final String? broadcastHash = await walletApi.broadcastSignedTransaction(
        retrySigned.rawTransaction,
        network,
      );
      final String hashToUse =
          (broadcastHash == null || broadcastHash.isEmpty)
              ? retrySigned.hash
              : broadcastHash;
      _inFlightTxByRequestId[request.requestId] = hashToUse;
      _nextNoncePerChainAndAddress[nonceKey] = refreshedNonce + BigInt.one;
      return DispatchResult(
        status: DispatchStatus.ok,
        txHash: hashToUse,
      );
    } catch (error) {
      final String message = error.toString();
      final String lower = message.toLowerCase();
      if (lower.contains('already known')) {
        final String hashToUse = retrySigned.hash;
        _inFlightTxByRequestId[request.requestId] = hashToUse;
        _nextNoncePerChainAndAddress[nonceKey] = refreshedNonce + BigInt.one;
        return DispatchResult(
          status: DispatchStatus.ok,
          txHash: hashToUse,
        );
      }
      if (lower.contains('nonce too low')) {
        _nextNoncePerChainAndAddress[nonceKey] = refreshedNonce + BigInt.one;
        return DispatchResult(
          status: DispatchStatus.staleNonce,
          errorMessage: message,
        );
      }
      if (lower.contains('replacement transaction underpriced')) {
        return DispatchResult(
          status: DispatchStatus.underpricedReplacement,
          errorMessage: message,
        );
      }
      return DispatchResult(
        status: DispatchStatus.rpcError,
        errorMessage: message,
      );
    }
  }

  void _bumpGasParameters(Map<String, dynamic> transaction) {
    final BigInt? gasPrice = _parseQuantity(transaction['gasPrice']);
    if (gasPrice != null) {
      final BigInt bumped = _increaseByTenPercent(gasPrice);
      transaction['gasPrice'] = _encodeQuantity(bumped);
    }
    final BigInt? maxFeePerGas = _parseQuantity(transaction['maxFeePerGas']);
    if (maxFeePerGas != null) {
      final BigInt bumped = _increaseByTenPercent(maxFeePerGas);
      transaction['maxFeePerGas'] = _encodeQuantity(bumped);
    }
    final BigInt? maxPriorityFeePerGas =
        _parseQuantity(transaction['maxPriorityFeePerGas']);
    if (maxPriorityFeePerGas != null) {
      final BigInt bumped = _increaseByTenPercent(maxPriorityFeePerGas);
      transaction['maxPriorityFeePerGas'] = _encodeQuantity(bumped);
    }
  }

  BigInt _increaseByTenPercent(BigInt value) {
    final BigInt bumped = (value * BigInt.from(110)) ~/ BigInt.from(100);
    if (bumped == value) {
      return value + BigInt.one;
    }
    return bumped;
  }

  String _nonceKey(String chainId, EthereumAddress address) {
    return '$chainId:${address.hexEip55.toLowerCase()}';
  }

  BigInt? _parseQuantity(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is BigInt) {
      return value;
    }
    if (value is int) {
      return BigInt.from(value);
    }
    if (value is String) {
      if (value.isEmpty) {
        return null;
      }
      final bool isHex = value.startsWith('0x') || value.startsWith('0X');
      final String cleaned = isHex ? value.substring(2) : value;
      if (cleaned.isEmpty) {
        return BigInt.zero;
      }
      return BigInt.parse(cleaned, radix: isHex ? 16 : 10);
    }
    throw ArgumentError('Unsupported quantity type: $value');
  }

  String _encodeQuantity(BigInt value) {
    return '0x${value.toRadixString(16)}';
  }
}
