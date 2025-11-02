import 'package:web3dart/web3dart.dart';

class NonceManager {
  NonceManager._();

  static final NonceManager instance = NonceManager._();

  final Map<String, int> _nextNonceCache = <String, int>{};

  Future<int> getAndIncrementNonce({
    required String chainId,
    required String address,
    required Web3Client client,
  }) async {
    final String cacheKey = _cacheKey(chainId, address);
    final int? cached = _nextNonceCache[cacheKey];
    if (cached != null) {
      _nextNonceCache[cacheKey] = cached + 1;
      return cached;
    }

    final EthereumAddress ethAddress = EthereumAddress.fromHex(address);
    final int networkNonce = await client.getTransactionCount(
      ethAddress,
      atBlock: const BlockNum.pending(),
    );

    final int? updatedCached = _nextNonceCache[cacheKey];
    if (updatedCached != null) {
      if (networkNonce > updatedCached) {
        _nextNonceCache[cacheKey] = networkNonce + 1;
        return networkNonce;
      }
      _nextNonceCache[cacheKey] = updatedCached + 1;
      return updatedCached;
    }

    _nextNonceCache[cacheKey] = networkNonce + 1;
    return networkNonce;
  }

  void invalidateNonce({
    required String chainId,
    required String address,
    required int usedNonce,
  }) {
    final String cacheKey = _cacheKey(chainId, address);
    final int? cached = _nextNonceCache[cacheKey];
    if (cached == null) {
      return;
    }
    if (cached == usedNonce + 1) {
      _nextNonceCache[cacheKey] = usedNonce;
    }
  }

  void resetChainAddress({
    required String chainId,
    required String address,
  }) {
    final String cacheKey = _cacheKey(chainId, address);
    _nextNonceCache.remove(cacheKey);
  }

  String _cacheKey(String chainId, String address) {
    return '${chainId.toLowerCase()}_${address.toLowerCase()}';
  }
}
