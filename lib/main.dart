import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web3dart/crypto.dart';
import 'package:web3dart/web3dart.dart';

void main() {
  runApp(const WalletApp());
}

class WalletApp extends StatelessWidget {
  const WalletApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ethereum Wallet',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const WalletHomePage(),
    );
  }
}

class WalletHomePage extends StatefulWidget {
  const WalletHomePage({super.key});

  @override
  State<WalletHomePage> createState() => _WalletHomePageState();
}

class _WalletHomePageState extends State<WalletHomePage> {
  late final WalletController _controller;
  final _recipientController = TextEditingController();
  final _amountController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = WalletController();
    _controller.addListener(_handleControllerUpdate);
    unawaited(_controller.initialize());
  }

  void _handleControllerUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerUpdate);
    _controller.dispose();
    _recipientController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _sendTransaction() async {
    final recipient = _recipientController.text.trim();
    final amount = _amountController.text.trim();
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    if (recipient.isEmpty || amount.isEmpty) {
      scaffoldMessenger.showSnackBar(
        const SnackBar(content: Text('Введите адрес получателя и сумму.')),
      );
      return;
    }

    final result = await _controller.sendTransaction(
      toAddress: recipient,
      amountInEth: amount,
    );

    result.when(
      success: (hash) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('Транзакция отправлена: $hash')),
        );
        _amountController.clear();
        _recipientController.clear();
      },
      failure: (error) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text('Ошибка: $error')),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final wallet = _controller.wallet;
    final balance = _controller.formattedBalance;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ethereum Wallet'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Обновить баланс',
            onPressed: wallet == null || _controller.isBusy
                ? null
                : () async {
                    try {
                      await _controller.refreshBalance();
                    } catch (error) {
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Не удалось обновить баланс: $error'),
                        ),
                      );
                    }
                  },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ListView(
            children: [
              _NetworkSelector(
                networks: NetworkConfiguration.supportedNetworks,
                selected: _controller.selectedNetwork,
                onChanged: (network) async {
                  try {
                    await _controller.updateNetwork(network);
                  } catch (error) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Не удалось переключить сеть: $error'),
                      ),
                    );
                  }
                },
              ),
              const SizedBox(height: 16),
              if (_controller.isInitializing)
                const Center(child: CircularProgressIndicator())
              else if (wallet == null)
                _EmptyWallet(onCreate: _controller.createWallet)
              else ...[
                WalletInfoCard(
                  wallet: wallet,
                  balance: balance,
                  isLoadingBalance: _controller.isRefreshingBalance,
                  onDelete: _controller.deleteWallet,
                ),
                const SizedBox(height: 24),
                _TransactionForm(
                  controller: this,
                  isSending: _controller.isSending,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _TransactionForm extends StatelessWidget {
  const _TransactionForm({
    required _WalletHomePageState controller,
    required this.isSending,
  }) : _state = controller;

  final _WalletHomePageState _state;
  final bool isSending;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Отправка ETH',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _state._recipientController,
              decoration: const InputDecoration(
                labelText: 'Адрес получателя',
                hintText: '0x...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _state._amountController,
              decoration: InputDecoration(
                labelText:
                    'Сумма в ${_state._controller.selectedNetwork.symbol}',
                hintText: '0.05',
                border: const OutlineInputBorder(),
              ),
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: isSending ? null : () => _state._sendTransaction(),
                icon: isSending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
                label: Text(isSending ? 'Отправка...' : 'Отправить'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyWallet extends StatelessWidget {
  const _EmptyWallet({required this.onCreate});

  final Future<void> Function() onCreate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        children: [
          const Icon(Icons.account_balance_wallet, size: 96),
          const SizedBox(height: 16),
          const Text(
            'Кошелёк не создан',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Нажмите кнопку, чтобы сгенерировать приватный ключ и адрес.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              try {
                await onCreate();
                if (!context.mounted) return;
                messenger.showSnackBar(
                  const SnackBar(content: Text('Новый кошелёк создан.')),
                );
              } catch (error, stackTrace) {
                if (!context.mounted) return;
                await showDialog<void>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    title: const Text('Ошибка создания кошелька'),
                    content: SingleChildScrollView(
                      child: Text('$error\n$stackTrace'),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        child: const Text('Закрыть'),
                      ),
                    ],
                  ),
                );
              }
            },
            child: const Text('Создать кошелёк'),
          ),
        ],
      ),
    );
  }
}

class _NetworkSelector extends StatelessWidget {
  const _NetworkSelector({
    required this.networks,
    required this.selected,
    required this.onChanged,
  });

  final List<NetworkConfiguration> networks;
  final NetworkConfiguration selected;
  final ValueChanged<NetworkConfiguration> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.public),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<NetworkConfiguration>(
            value: selected,
            decoration: const InputDecoration(
              labelText: 'Сеть',
              border: OutlineInputBorder(),
            ),
            items: networks
                .map(
                  (network) => DropdownMenuItem(
                    value: network,
                    child: Text(network.name),
                  ),
                )
                .toList(),
            onChanged: (network) {
              if (network != null) {
                onChanged(network);
              }
            },
          ),
        ),
      ],
    );
  }
}

class WalletInfoCard extends StatelessWidget {
  const WalletInfoCard({
    required this.wallet,
    required this.balance,
    required this.isLoadingBalance,
    required this.onDelete,
  });

  final WalletData wallet;
  final String balance;
  final bool isLoadingBalance;
  final Future<void> Function() onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Адрес:\n${wallet.address.hexEip55}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  tooltip: 'Скопировать адрес',
                  onPressed: () {
                    ClipboardHelper.copy(context, wallet.address.hexEip55);
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            SelectableText('Приватный ключ:\n${wallet.privateKey}'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: isLoadingBalance
                      ? const LinearProgressIndicator(minHeight: 4)
                      : Text('Баланс: $balance'),
                ),
                IconButton(
                  icon: const Icon(Icons.copy_all),
                  tooltip: 'Скопировать приватный ключ',
                  onPressed: () {
                    ClipboardHelper.copy(context, wallet.privateKey);
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.tonal(
              onPressed: () async {
                final messenger = ScaffoldMessenger.of(context);
                await onDelete();
                if (!context.mounted) return;
                messenger.showSnackBar(
                  const SnackBar(content: Text('Кошелёк удалён.')),
                );
              },
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.errorContainer,
              ),
              child: const Text('Удалить кошелёк'),
            ),
          ],
        ),
      ),
    );
  }
}

class ClipboardHelper {
  static void copy(BuildContext context, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Скопировано в буфер обмена.')),
    );
  }
}

class WalletController extends ChangeNotifier {
  WalletController({WalletStorage? storage})
    : _storage = storage ?? WalletStorage();

  final WalletStorage _storage;

  NetworkConfiguration selectedNetwork =
      NetworkConfiguration.supportedNetworks.first;
  WalletData? wallet;
  EtherAmount? _balance;

  bool isInitializing = true;
  bool isRefreshingBalance = false;
  bool isSending = false;
  bool get isBusy => isRefreshingBalance || isSending;

  String get formattedBalance {
    if (_balance == null) {
      return '—';
    }
    final value = _balance!.getValueInUnit(EtherUnit.ether);
    return '${value.toStringAsFixed(6)} ${selectedNetwork.symbol}';
  }

  Future<void> initialize() async {
    try {
      final storedKey = await _storage.readPrivateKey();
      if (storedKey != null) {
        await _loadWalletFromKey(storedKey);
        await refreshBalance();
      }
    } catch (_) {
      // Ошибку покажем на действиях пользователя.
    } finally {
      isInitializing = false;
      notifyListeners();
    }
  }

  Future<void> updateNetwork(NetworkConfiguration network) async {
    selectedNetwork = network;
    notifyListeners();
    if (wallet != null) {
      await refreshBalance();
    }
  }

  Future<void> createWallet() async {
    isInitializing = true;
    notifyListeners();
    try {
      final credentials = EthPrivateKey.createRandom(Random.secure());
      final address = await credentials.extractAddress();
      final privateKeyHex = bytesToHex(credentials.privateKey, include0x: true);
      wallet = WalletData(privateKey: privateKeyHex, address: address);
      await _storage.savePrivateKey(privateKeyHex);
      await refreshBalance();
    } catch (error) {
      wallet = null;
      rethrow;
    } finally {
      isInitializing = false;
      notifyListeners();
    }
  }

  Future<void> deleteWallet() async {
    await _storage.clear();
    wallet = null;
    _balance = null;
    notifyListeners();
  }

  Future<void> refreshBalance() async {
    final currentWallet = wallet;
    if (currentWallet == null) {
      return;
    }
    isRefreshingBalance = true;
    notifyListeners();
    try {
      _balance = await _withClient((client) {
        return client.getBalance(currentWallet.address);
      });
    } catch (_) {
      _balance = null;
      rethrow;
    } finally {
      isRefreshingBalance = false;
      notifyListeners();
    }
  }

  Future<ActionResult> sendTransaction({
    required String toAddress,
    required String amountInEth,
  }) async {
    final currentWallet = wallet;
    if (currentWallet == null) {
      return const ActionResult.failure('Сначала создайте кошелёк.');
    }

    EthereumAddress recipient;
    try {
      recipient = EthereumAddress.fromHex(toAddress);
    } catch (_) {
      return const ActionResult.failure('Некорректный адрес получателя.');
    }

    BigInt value;
    try {
      value = AmountParser.parseEthToWei(amountInEth);
    } catch (_) {
      return const ActionResult.failure('Некорректная сумма.');
    }

    isSending = true;
    notifyListeners();
    try {
      final hash = await _withClient((client) async {
        final credentials = EthPrivateKey.fromHex(currentWallet.privateKey);
        final gasPrice = await client.getGasPrice();
        return client.sendTransaction(
          credentials,
          Transaction(
            to: recipient,
            value: EtherAmount.inWei(value),
            gasPrice: gasPrice,
            maxGas: 21000,
          ),
          chainId: selectedNetwork.chainId,
        );
      });
      await refreshBalance();
      return ActionResult.success(hash);
    } catch (error) {
      return ActionResult.failure('Не удалось отправить транзакцию: $error');
    } finally {
      isSending = false;
      notifyListeners();
    }
  }

  Future<void> _loadWalletFromKey(String privateKey) async {
    final credentials = EthPrivateKey.fromHex(privateKey);
    final address = await credentials.extractAddress();
    wallet = WalletData(privateKey: privateKey, address: address);
  }

  Future<T> _withClient<T>(Future<T> Function(Web3Client client) action) async {
    final client = Web3Client(selectedNetwork.rpcUrl, http.Client());
    try {
      return await action(client);
    } finally {
      client.dispose();
    }
  }
}

class WalletStorage {
  static const _privateKeyKey = 'wallet_private_key';

  Future<String?> readPrivateKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_privateKeyKey);
  }

  Future<void> savePrivateKey(String value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_privateKeyKey, value);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_privateKeyKey);
  }
}

class WalletData {
  WalletData({required this.privateKey, required this.address});

  final String privateKey;
  final EthereumAddress address;
}

class NetworkConfiguration {
  const NetworkConfiguration({
    required this.id,
    required this.name,
    required this.rpcUrl,
    required this.chainId,
    required this.symbol,
  });

  final String id;
  final String name;
  final String rpcUrl;
  final int chainId;
  final String symbol;

  static const mainnet = NetworkConfiguration(
    id: 'mainnet',
    name: 'Ethereum Mainnet',
    rpcUrl: 'https://rpc.ankr.com/eth',
    chainId: 1,
    symbol: 'ETH',
  );

  static const sepolia = NetworkConfiguration(
    id: 'sepolia',
    name: 'Ethereum Sepolia Testnet',
    rpcUrl: 'https://rpc.ankr.com/eth_sepolia',
    chainId: 11155111,
    symbol: 'ETH',
  );

  static List<NetworkConfiguration> get supportedNetworks => const [
    mainnet,
    sepolia,
  ];
}

class AmountParser {
  static final _amountRegex = RegExp(r'^([0-9]+)(?:\.([0-9]{1,18}))?\$');

  static BigInt parseEthToWei(String amount) {
    final match = _amountRegex.firstMatch(amount.trim());
    if (match == null) {
      throw const FormatException('Invalid ETH amount');
    }
    final whole = match.group(1) ?? '0';
    final fractionalPart = match.group(2) ?? '';
    final paddedFraction = fractionalPart.padRight(18, '0');
    final truncatedFraction = paddedFraction.substring(0, 18);
    final weiString = whole + truncatedFraction;
    return BigInt.parse(weiString);
  }
}

class ActionResult {
  const ActionResult._(this._value, this._error);

  const ActionResult.success(String value) : this._(value, null);

  const ActionResult.failure(String error) : this._(null, error);

  final String? _value;
  final String? _error;

  void when({
    required void Function(String value) success,
    required void Function(String error) failure,
  }) {
    if (_value != null) {
      success(_value!);
    } else if (_error != null) {
      failure(_error!);
    }
  }
}
