class NetworkConfig {
  const NetworkConfig({
    required this.chainIdCaip2,
    required this.chainIdNumeric,
    required this.rpcUrl,
    required this.name,
  });

  final String chainIdCaip2;
  final int chainIdNumeric;
  final String rpcUrl;
  final String name;
}

const NetworkConfig ethereumMainnetConfig = NetworkConfig(
  chainIdCaip2: 'eip155:1',
  chainIdNumeric: 1,
  rpcUrl: 'https://ethereum.publicnode.com',
  name: 'Ethereum Mainnet',
);

const NetworkConfig sepoliaConfig = NetworkConfig(
  chainIdCaip2: 'eip155:11155111',
  chainIdNumeric: 11155111,
  rpcUrl: 'https://ethereum-sepolia.publicnode.com',
  name: 'Sepolia',
);

const List<NetworkConfig> walletConnectSupportedNetworks = <NetworkConfig>[
  ethereumMainnetConfig,
  sepoliaConfig,
];

List<String> walletConnectSupportedChainIds() {
  return walletConnectSupportedNetworks
      .map((config) => config.chainIdCaip2)
      .toList(growable: false);
}

NetworkConfig? findNetworkByCaip2(String chainIdCaip2) {
  final normalized = chainIdCaip2.toLowerCase();
  for (final config in walletConnectSupportedNetworks) {
    if (config.chainIdCaip2.toLowerCase() == normalized) {
      return config;
    }
  }
  return null;
}

NetworkConfig? findNetworkByNumeric(int chainId) {
  for (final config in walletConnectSupportedNetworks) {
    if (config.chainIdNumeric == chainId) {
      return config;
    }
  }
  return null;
}
