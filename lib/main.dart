import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web3dart/web3dart.dart';
import 'package:web3dart/crypto.dart';
import 'package:image_picker/image_picker.dart';
import 'package:qr_code_tools/qr_code_tools.dart';
import 'package:walletconnect_dart/walletconnect_dart.dart';
import 'package:uuid/uuid.dart';

const PeerMeta _defaultWalletConnectPeerMeta = PeerMeta(
  name: 'Wallet Mobile',
  description: 'Кроссплатформенный эфир-кошелёк',
  url: 'https://walletconnect.org',
  icons: [
    'https://walletconnect.org/walletconnect-logo.png',
  ],
);

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
    if (!mounted) {
      return;
    }
    setState(() {});
    final request = _controller.dequeueWalletConnectRequest();
    if (request != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _showWalletConnectRequestDialog(request);
      });
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

  Future<void> _scanWalletConnectQr() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(source: ImageSource.camera);
      if (image == null) {
        return;
      }
      final decoded = await QrCodeToolsPlugin.decodeFrom(image.path);
      final uri = decoded?.trim();
      if (uri == null || uri.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('QR-код не распознан.')),
        );
        return;
      }
      final result = await _controller.connectToWalletConnect(uri);
      if (!mounted) {
        return;
      }
      result.when(
        success: (message) => messenger.showSnackBar(
          SnackBar(content: Text(message)),
        ),
        failure: (error) => messenger.showSnackBar(
          SnackBar(content: Text(error)),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(content: Text('Ошибка сканирования QR-кода: $error')),
      );
    }
  }

  Future<void> _disconnectWalletConnect() async {
    await _controller.disconnectWalletConnect();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('WalletConnect отключён.')),
    );
  }

  Future<void> _showWalletConnectRequestDialog(
      WalletConnectRequest request) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final peer = _controller.walletConnectPeerMeta;
        return WalletConnectApprovalDialog(
          controller: _controller,
          request: request,
          peerMeta: peer,
          network: _controller.selectedNetwork,
        );
      },
    );

    if (!mounted) {
      return;
    }

    if (result == true) {
      final response = await _controller.approveWalletConnectRequest(request);
      if (!mounted) return;
      response.when(
        success: (message) => messenger.showSnackBar(
          SnackBar(content: Text(message)),
        ),
        failure: (error) => messenger.showSnackBar(
          SnackBar(content: Text(error)),
        ),
      );
    } else {
      final response = await _controller.rejectWalletConnectRequest(
        request,
        message: 'Отклонено пользователем.',
      );
      if (!mounted) return;
      response.when(
        success: (message) => messenger.showSnackBar(
          SnackBar(content: Text(message)),
        ),
        failure: (error) => messenger.showSnackBar(
          SnackBar(content: Text(error)),
        ),
      );
    }
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
                _EmptyWallet(
                  onCreate: _controller.createWallet,
                  isCreating: _controller.isCreatingWallet,
                  onImport: _controller.importWallet,
                  isImporting: _controller.isImportingWallet,
                )
              else ...[
                WalletInfoCard(
                  wallet: wallet,
                  balance: balance,
                  isLoadingBalance: _controller.isRefreshingBalance,
                  onDelete: _controller.deleteWallet,
                  onViewTransactions: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => TransactionHistoryPage(
                          address: wallet.address,
                          network: _controller.selectedNetwork,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
                _TransactionForm(
                  controller: this,
                  isSending: _controller.isSending,
                ),
                const SizedBox(height: 24),
                WalletConnectSection(
                  controller: _controller,
                  onScanQr: _scanWalletConnectQr,
                  onDisconnect: _controller.isWalletConnectConnected
                      ? _disconnectWalletConnect
                      : null,
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
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.local_gas_station, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: _state._controller.isFetchingGasEstimate
                      ? const Text('Загрузка оценки газа...')
                      : Text(
                          'Расход газа: ${_state._controller.formattedGasEstimate}',
                        ),
                ),
              ],
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

class WalletConnectSection extends StatelessWidget {
  const WalletConnectSection({
    required this.controller,
    required this.onScanQr,
    this.onDisconnect,
  });

  final WalletController controller;
  final Future<void> Function() onScanQr;
  final Future<void> Function()? onDisconnect;

  @override
  Widget build(BuildContext context) {
    final isConnected = controller.isWalletConnectConnected;
    final isConnecting = controller.isWalletConnectConnecting;
    final pendingCount = controller.walletConnectPendingRequestCount;
    final isProcessing = controller.isProcessingWalletConnectRequest;
    final peer = controller.walletConnectPeerMeta;
    final peerName = peer?.name ?? '';
    final peerUrl = peer?.url ?? '';
    final peerDescription = peer?.description ?? '';
    final session = controller.walletConnectSession;

    final status = isConnected
        ? 'Подключено'
        : isConnecting
            ? 'Подключение...'
            : 'Не подключено';

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.qr_code_2),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'WalletConnect',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                if (isConnecting)
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Статус: $status'),
            if (peer != null) ...[
              if (peerName.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'dApp: $peerName',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
              if (peerUrl.isNotEmpty)
                Text(peerUrl),
              if (peerDescription.isNotEmpty)
                Text(peerDescription),
            ],
            if (session != null && session.accounts.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('Аккаунты: ${session.accounts.join(', ')}'),
              Text('Chain ID: ${session.chainId}'),
            ],
            if (pendingCount > 0 || isProcessing) ...[
              const SizedBox(height: 8),
              Text(
                isProcessing
                    ? 'Обрабатывается запрос от dApp...'
                    : 'Ожидающих запросов: $pendingCount',
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: isConnecting ? null : () => unawaited(onScanQr()),
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Сканировать QR'),
                ),
                if (onDisconnect != null)
                  OutlinedButton.icon(
                    onPressed: () => unawaited(onDisconnect!()),
                    icon: const Icon(Icons.link_off),
                    label: const Text('Отключить'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class WalletConnectApprovalDialog extends StatelessWidget {
  const WalletConnectApprovalDialog({
    required this.controller,
    required this.request,
    required this.peerMeta,
    required this.network,
  });

  final WalletController controller;
  final WalletConnectRequest request;
  final PeerMeta? peerMeta;
  final NetworkConfiguration network;

  @override
  Widget build(BuildContext context) {
    final isProcessing = controller.isProcessingWalletConnectRequest;

    final titleText = (peerMeta?.name?.isNotEmpty ?? false)
        ? peerMeta!.name!
        : 'Запрос WalletConnect';

    return AlertDialog(
      title: Text(titleText),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if ((peerMeta?.url ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(peerMeta!.url ?? ''),
              ),
            if ((peerMeta?.description ?? '').isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(peerMeta!.description ?? ''),
              ),
            WalletConnectRequestDetails(
              request: request,
              networkSymbol: network.symbol,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: isProcessing ? null : () => Navigator.of(context).pop(false),
          child: const Text('Отклонить'),
        ),
        FilledButton(
          onPressed: isProcessing ? null : () => Navigator.of(context).pop(true),
          child: isProcessing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Подтвердить'),
        ),
      ],
    );
  }
}

class WalletConnectRequestDetails extends StatelessWidget {
  const WalletConnectRequestDetails({
    required this.request,
    required this.networkSymbol,
  });

  final WalletConnectRequest request;
  final String networkSymbol;

  @override
  Widget build(BuildContext context) {
    switch (request.type) {
      case WalletConnectRequestType.sendTransaction:
        final tx = request.transaction!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _RequestInfo(label: 'Отправитель', value: tx.from.hexEip55),
            _RequestInfo(
              label: 'Получатель',
              value: tx.to?.hexEip55 ?? '—',
            ),
            if (tx.value != null)
              _RequestInfo(
                label: 'Сумма',
                value: _formatEther(tx.value!),
              ),
            if (tx.gasLimit != null)
              _RequestInfo(
                label: 'Лимит газа',
                value: tx.gasLimit!.toString(),
              ),
            if (tx.gasPrice != null)
              _RequestInfo(
                label: 'Цена газа',
                value: _formatGas(tx.gasPrice!),
              ),
            if (tx.maxFeePerGas != null)
              _RequestInfo(
                label: 'Max fee per gas',
                value: _formatGas(tx.maxFeePerGas!),
              ),
            if (tx.maxPriorityFeePerGas != null)
              _RequestInfo(
                label: 'Max priority fee',
                value: _formatGas(tx.maxPriorityFeePerGas!),
              ),
            if (tx.nonce != null)
              _RequestInfo(label: 'Nonce', value: tx.nonce!.toString()),
            if (tx.dataHex != null && tx.dataHex!.isNotEmpty && tx.dataHex != '0x')
              _RequestInfo(label: 'Данные', value: tx.dataHex!),
          ],
        );
      case WalletConnectRequestType.personalSign:
      case WalletConnectRequestType.ethSign:
        final sign = request.sign!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (sign.address != null)
              _RequestInfo(
                label: 'Адрес',
                value: sign.address!.hexEip55,
              ),
            const SizedBox(height: 8),
            const Text(
              'Сообщение:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            SelectableText(sign.preview),
            const SizedBox(height: 8),
            const Text(
              'HEX:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            SelectableText(sign.rawHex),
          ],
        );
    }
  }

  String _formatEther(EtherAmount amount) {
    final value = amount.getValueInUnit(EtherUnit.ether);
    if (value == 0) {
      return '0 $networkSymbol';
    }
    final decimals = value >= 1 ? 6 : 8;
    return '${value.toStringAsFixed(decimals)} $networkSymbol';
  }

  String _formatGas(EtherAmount amount) {
    final gwei = amount.getValueInUnit(EtherUnit.gwei);
    return '${gwei.toStringAsFixed(2)} Gwei';
  }
}

class _RequestInfo extends StatelessWidget {
  const _RequestInfo({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          SelectableText(value),
        ],
      ),
    );
  }
}


class _EmptyWallet extends StatefulWidget {
  const _EmptyWallet({
    required this.onCreate,
    required this.isCreating,
    required this.onImport,
    required this.isImporting,
  });

  final Future<void> Function() onCreate;
  final bool isCreating;
  final Future<ActionResult> Function(String privateKey) onImport;
  final bool isImporting;

  @override
  State<_EmptyWallet> createState() => _EmptyWalletState();
}

class _EmptyWalletState extends State<_EmptyWallet> {
  final _privateKeyController = TextEditingController();
  bool _obscurePrivateKey = true;

  @override
  void dispose() {
    _privateKeyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isBusy = widget.isCreating || widget.isImporting;

    return Center(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.account_balance_wallet, size: 96),
          const SizedBox(height: 16),
          const Text(
            'Кошелёк не создан',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Создайте новый кошелёк или импортируйте ранее сохранённый приватный ключ.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: isBusy
                ? null
                : () async {
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      await widget.onCreate();
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
            icon: widget.isCreating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add),
            label:
                Text(widget.isCreating ? 'Создание...' : 'Создать новый кошелёк'),
          ),
          const SizedBox(height: 24),
          const Divider(),
          const SizedBox(height: 24),
          const Text(
            'Импорт приватного ключа или фразы восстановления',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Вставьте сохранённый приватный ключ или фразу из 24 слов, чтобы восстановить доступ к кошельку.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _privateKeyController,
            decoration: InputDecoration(
              labelText: 'Приватный ключ или фраза восстановления',
              hintText: '0x... или 24 слова',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePrivateKey ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: () {
                  setState(() {
                    _obscurePrivateKey = !_obscurePrivateKey;
                  });
                },
              ),
            ),
            obscureText: _obscurePrivateKey,
            enableSuggestions: false,
            autocorrect: false,
            textInputAction: TextInputAction.done,
            enabled: !widget.isImporting,
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: isBusy ? null : _handleImport,
            icon: widget.isImporting
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download),
            label: Text(widget.isImporting ? 'Импорт...' : 'Импортировать кошелёк'),
          ),
        ],
      ),
    );
  }

  Future<void> _handleImport() async {
    final privateKey = _privateKeyController.text.trim();
    final messenger = ScaffoldMessenger.of(context);
    if (privateKey.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Введите приватный ключ или фразу восстановления.'),
        ),
      );
      return;
    }

    final result = await widget.onImport(privateKey);
    if (!mounted) return;

    result.when(
      success: (message) {
        messenger.showSnackBar(SnackBar(content: Text(message)));
        _privateKeyController.clear();
      },
      failure: (error) {
        messenger.showSnackBar(SnackBar(content: Text(error)));
      },
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
    this.onViewTransactions,
  });

  final WalletData wallet;
  final String balance;
  final bool isLoadingBalance;
  final Future<void> Function() onDelete;
  final VoidCallback? onViewTransactions;

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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SelectableText(
                    'Приватный ключ:\n${wallet.privateKey}',
                  ),
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: SelectableText(
                    wallet.mnemonic != null
                        ? 'Фраза восстановления:\n${wallet.mnemonic!}'
                        : 'Фраза восстановления недоступна для этого кошелька.',
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.copy),
                  tooltip: 'Скопировать фразу восстановления',
                  onPressed: wallet.mnemonic == null
                      ? null
                      : () {
                          ClipboardHelper.copy(context, wallet.mnemonic!);
                        },
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: isLoadingBalance
                      ? const LinearProgressIndicator(minHeight: 4)
                      : Text('Баланс: $balance'),
                ),
              ],
            ),
            if (onViewTransactions != null) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onViewTransactions,
                icon: const Icon(Icons.receipt_long),
                label: const Text('Просмотр транзакций'),
              ),
            ],
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
  EtherAmount? _gasPrice;
  EtherAmount? _gasFee;

  bool isInitializing = true;
  bool isCreatingWallet = false;
  bool isImportingWallet = false;
  bool isRefreshingBalance = false;
  bool isSending = false;
  bool isFetchingGasEstimate = false;
  WalletConnect? _walletConnect;
  PeerMeta? walletConnectPeerMeta;
  SessionStatus? walletConnectSession;
  bool isWalletConnectConnecting = false;
  bool isProcessingWalletConnectRequest = false;
  final List<WalletConnectRequest> _walletConnectRequests = [];
  static const int defaultGasLimit = 21000;
  bool get isBusy =>
      isRefreshingBalance || isSending || isCreatingWallet || isImportingWallet;

  bool get isWalletConnectConnected => _walletConnect?.connected ?? false;

  String get formattedBalance {
    if (_balance == null) {
      return '—';
    }
    final value = _balance!.getValueInUnit(EtherUnit.ether);
    return '${value.toStringAsFixed(6)} ${selectedNetwork.symbol}';
  }

  String get formattedGasEstimate {
    if (_gasPrice == null || _gasFee == null) {
      return '—';
    }
    final gasPriceGwei = _gasPrice!.getValueInUnit(EtherUnit.gwei);
    final feeInEth = _gasFee!.getValueInUnit(EtherUnit.ether);
    return '${defaultGasLimit} газа • '
        '${feeInEth.toStringAsFixed(6)} ${selectedNetwork.symbol} '
        '(цена газа ${gasPriceGwei.toStringAsFixed(2)} Gwei)';
  }

  WalletConnectRequest? dequeueWalletConnectRequest() {
    if (_walletConnectRequests.isEmpty) {
      return null;
    }
    return _walletConnectRequests.removeAt(0);
  }

  int get walletConnectPendingRequestCount => _walletConnectRequests.length;

  Future<void> initialize() async {
    try {
      final storedKey = await _storage.readPrivateKey();
      if (storedKey != null) {
        final storedMnemonic = await _storage.readMnemonic();
        await _loadWalletFromKey(
          storedKey,
          mnemonic: storedMnemonic,
        );
        try {
          await refreshBalance();
        } catch (_) {
          // Ошибку покажем на действиях пользователя.
        }
      }
    } catch (_) {
      // Ошибку покажем на действиях пользователя.
    } finally {
      try {
        if (_gasPrice == null || _gasFee == null) {
          await refreshGasEstimate();
        }
      } catch (_) {
        // Ошибку покажем при взаимодействии пользователя.
      }
      isInitializing = false;
      notifyListeners();
    }
  }

  Future<void> updateNetwork(NetworkConfiguration network) async {
    selectedNetwork = network;
    notifyListeners();
    if (wallet != null) {
      await refreshBalance();
    } else {
      await refreshGasEstimate();
    }
  }

  Future<void> createWallet() async {
    isCreatingWallet = true;
    notifyListeners();

    try {
      final mnemonic = Bip39MnemonicGenerator(Bip39Languages.english)
          .fromWordsNumber(Bip39WordsNum.wordsNum24);
      final seed = Bip39SeedGenerator(mnemonic).generate();
      final derivation =
          Bip44.fromSeed(seed, Bip44Coins.ethereum).deriveDefaultPath;
      final privateKeyHex =
          BytesUtils.toHexString(derivation.privateKey.raw, prefix: '0x');
      final credentials = EthPrivateKey.fromHex(privateKeyHex);
      final address = await credentials.extractAddress();
      final mnemonicPhrase = mnemonic.toStr();
      await _storage.savePrivateKey(privateKeyHex, mnemonic: mnemonicPhrase);
      wallet = WalletData(
        privateKey: privateKeyHex,
        address: address,
        mnemonic: mnemonicPhrase,
      );
      notifyListeners();
      await refreshBalance();
    } finally {
      isCreatingWallet = false;
      notifyListeners();
    }
  }

  Future<ActionResult> importWallet(String privateKey) async {
    isImportingWallet = true;
    notifyListeners();

    try {
      final parsed = _parseImportInput(privateKey);
      await _loadWalletFromKey(parsed.privateKey, mnemonic: parsed.mnemonic);
      await _storage.savePrivateKey(parsed.privateKey, mnemonic: parsed.mnemonic);
      notifyListeners();
      await refreshBalance();
      return const ActionResult.success('Кошелёк импортирован.');
    } on FormatException catch (error) {
      return ActionResult.failure('Некорректные данные: ${error.message}');
    } catch (error) {
      return ActionResult.failure('Не удалось импортировать кошелёк: $error');
    } finally {
      isImportingWallet = false;
      notifyListeners();
    }
  }

  Future<void> deleteWallet() async {
    await _storage.clear();
    wallet = null;
    _balance = null;
    await disconnectWalletConnect();
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
    try {
      await refreshGasEstimate();
    } catch (_) {
      // Ошибку покажем при пользовательском действии.
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
      try {
        await refreshGasEstimate();
      } catch (_) {
        // Ошибку покажем при пользовательском действии.
      }
      return ActionResult.success(hash);
    } catch (error) {
      return ActionResult.failure('Не удалось отправить транзакцию: $error');
    } finally {
      isSending = false;
      notifyListeners();
    }
  }

  Future<void> refreshGasEstimate() async {
    isFetchingGasEstimate = true;
    notifyListeners();
    try {
      final gasPrice = await _withClient((client) => client.getGasPrice());
      final gasPriceWei = gasPrice.getValueInUnitBI(EtherUnit.wei);
      final totalFeeWei = gasPriceWei * BigInt.from(defaultGasLimit);
      _gasPrice = gasPrice;
      _gasFee = EtherAmount.inWei(totalFeeWei);
    } catch (_) {
      _gasPrice = null;
      _gasFee = null;
      rethrow;
    } finally {
      isFetchingGasEstimate = false;
      notifyListeners();
    }
  }

  Future<ActionResult> connectToWalletConnect(String uri) async {
    final currentWallet = wallet;
    if (currentWallet == null) {
      return const ActionResult.failure('Сначала создайте кошелёк.');
    }
    final trimmed = uri.trim();
    if (trimmed.isEmpty) {
      return const ActionResult.failure('QR-код не содержит данных WalletConnect.');
    }

    isWalletConnectConnecting = true;
    notifyListeners();

    try {
      final existing = _walletConnect;
      if (existing != null) {
        unawaited(existing.killSession());
      }
      _clearWalletConnectSession(notify: false);

      final peerMeta = _defaultWalletConnectPeerMeta;
      final session = WalletConnectSession.fromUri(
        uri: trimmed,
        clientId: const Uuid().v4(),
        clientMeta: peerMeta,
      );

      final connector = WalletConnect(
        session: session,
        clientMeta: peerMeta,
      );

      _walletConnect = connector;
      _registerWalletConnectListeners(connector);

      connector.reconnect();

      return const ActionResult.success(
        'Запрос на подключение отправлен. Подтвердите соединение в dApp.',
      );
    } catch (error) {
      _clearWalletConnectSession(notify: false);
      isWalletConnectConnecting = false;
      notifyListeners();
      return ActionResult.failure('Не удалось подключиться: $error');
    }
  }

  Future<void> disconnectWalletConnect() async {
    final connector = _walletConnect;
    if (connector != null) {
      try {
        await connector.killSession();
      } catch (_) {
        // Игнорируем ошибки завершения сессии.
      }
    }
    _clearWalletConnectSession();
  }

  Future<ActionResult> approveWalletConnectRequest(
      WalletConnectRequest request) async {
    final connector = _walletConnect;
    final currentWallet = wallet;
    if (connector == null || currentWallet == null) {
      return const ActionResult.failure('Нет активного подключения WalletConnect.');
    }

    isProcessingWalletConnectRequest = true;
    notifyListeners();

    try {
      switch (request.type) {
        case WalletConnectRequestType.sendTransaction:
          final txData = request.transaction!;
          if (!_addressesEqual(txData.from, currentWallet.address)) {
            await connector.rejectRequest(
              id: request.id,
              errorMessage:
                  'Адрес отправителя не совпадает с активным кошельком.',
            );
            return const ActionResult.failure(
              'Адрес отправителя не совпадает с текущим кошельком.',
            );
          }

          final credentials = EthPrivateKey.fromHex(currentWallet.privateKey);
          final transaction = Transaction(
            from: txData.from,
            to: txData.to,
            maxGas: txData.gasLimit,
            gasPrice: txData.gasPrice,
            value: txData.value,
            data: txData.data,
            nonce: txData.nonce,
            maxFeePerGas: txData.maxFeePerGas,
            maxPriorityFeePerGas: txData.maxPriorityFeePerGas,
          );

          final hash = await _withClient((client) {
            return client.sendTransaction(
              credentials,
              transaction,
              chainId: selectedNetwork.chainId,
            );
          });

          await connector.approveRequest(id: request.id, result: hash);
          await refreshBalance();
          try {
            await refreshGasEstimate();
          } catch (_) {
            // Ошибку покажем при пользовательском действии.
          }
          return ActionResult.success('Транзакция отправлена: $hash');

        case WalletConnectRequestType.personalSign:
        case WalletConnectRequestType.ethSign:
          final signData = request.sign!;
          final requestedAddress = signData.address;
          if (requestedAddress != null &&
              !_addressesEqual(requestedAddress, currentWallet.address)) {
            await connector.rejectRequest(
              id: request.id,
              errorMessage:
                  'Адрес подписи не совпадает с активным кошельком.',
            );
            return const ActionResult.failure(
              'Подписание невозможно: указан другой адрес.',
            );
          }

          final credentials = EthPrivateKey.fromHex(currentWallet.privateKey);
          Uint8List signatureBytes;
          if (request.type == WalletConnectRequestType.personalSign) {
            signatureBytes =
                await credentials.signPersonalMessage(signData.bytes);
          } else {
            signatureBytes = await credentials.sign(
              signData.bytes,
              chainId: selectedNetwork.chainId,
            );
          }
          final signatureHex = bytesToHex(signatureBytes, include0x: true);
          await connector.approveRequest(
            id: request.id,
            result: signatureHex,
          );
          return const ActionResult.success('Сообщение подписано.');
      }
    } catch (error) {
      await connector.rejectRequest(
        id: request.id,
        errorMessage: '$error',
      );
      return ActionResult.failure('Не удалось обработать запрос: $error');
    } finally {
      isProcessingWalletConnectRequest = false;
      notifyListeners();
    }
  }

  Future<ActionResult> rejectWalletConnectRequest(
    WalletConnectRequest request, {
    String? message,
  }) async {
    final connector = _walletConnect;
    if (connector == null) {
      return const ActionResult.failure('Нет активного подключения WalletConnect.');
    }

    final errorMessage = message ?? 'Отклонено пользователем.';
    await connector.rejectRequest(
      id: request.id,
      errorMessage: errorMessage,
    );
    return const ActionResult.success('Запрос отклонён.');
  }

  void _registerWalletConnectListeners(WalletConnect connector) {
    connector.on('connect', (status) {
      final sessionStatus = status as SessionStatus;
      walletConnectSession = sessionStatus;
      isWalletConnectConnecting = false;
      notifyListeners();
    });
    connector.on('session_update', (update) {
      final sessionUpdate = update as WCSessionUpdateResponse;
      walletConnectSession = SessionStatus(
        chainId: sessionUpdate.chainId,
        accounts: sessionUpdate.accounts,
      );
      notifyListeners();
    });
    connector.on('disconnect', (_) {
      _clearWalletConnectSession();
    });

    connector.on('session_request', (request) async {
      final sessionRequest = request as WCSessionRequest;
      walletConnectPeerMeta = sessionRequest.peerMeta;
      notifyListeners();
      final currentWallet = wallet;
      if (currentWallet == null) {
        await connector.rejectSession(message: 'Кошелёк не создан.');
        return;
      }

      try {
        await connector.approveSession(
          chainId: selectedNetwork.chainId,
          accounts: [currentWallet.address.hexEip55],
        );
      } catch (error) {
        await connector.rejectSession(message: '$error');
        _clearWalletConnectSession();
      }
    });

    connector.on(
      'eth_sendTransaction',
      (request) => _handleWalletConnectTransactionRequest(
        request as JsonRpcRequest,
      ),
    );
    connector.on(
      'personal_sign',
      (request) => _handleWalletConnectPersonalSignRequest(
        request as JsonRpcRequest,
      ),
    );
    connector.on(
      'eth_sign',
      (request) => _handleWalletConnectEthSignRequest(
        request as JsonRpcRequest,
      ),
    );

    const unsupportedMethods = [
      'eth_signTransaction',
      'eth_signTypedData',
      'eth_signTypedData_v1',
      'eth_signTypedData_v2',
      'eth_signTypedData_v3',
      'eth_signTypedData_v4',
    ];
    for (final method in unsupportedMethods) {
      connector.on(method, (request) {
        _rejectWalletConnectRpcRequest(
          request as JsonRpcRequest,
          'Метод $method пока не поддерживается.',
        );
      });
    }
  }

  void _handleWalletConnectTransactionRequest(JsonRpcRequest request) {
    final params = request.params;
    if (params == null || params.isEmpty) {
      _rejectWalletConnectRpcRequest(
        request,
        'Некорректные параметры транзакции.',
      );
      return;
    }

    final first = params.first;
    if (first is! Map) {
      _rejectWalletConnectRpcRequest(
        request,
        'Некорректные параметры транзакции.',
      );
      return;
    }

    final raw = Map<String, dynamic>.from(first as Map);
    final transaction = _parseWalletConnectTransaction(raw);
    if (transaction == null) {
      _rejectWalletConnectRpcRequest(
        request,
        'Не удалось обработать параметры транзакции.',
      );
      return;
    }

    _enqueueWalletConnectRequest(
      WalletConnectRequest.transaction(
        rpcRequest: request,
        transaction: transaction,
      ),
    );
  }

  void _handleWalletConnectPersonalSignRequest(JsonRpcRequest request) {
    final params = request.params ?? [];
    if (params.isEmpty) {
      _rejectWalletConnectRpcRequest(
        request,
        'Пустой запрос на подпись.',
      );
      return;
    }

    dynamic messageParam = params[0];
    String? addressParam;
    if (params.length > 1) {
      addressParam = params[1] is String ? params[1] as String? : null;
      if (_looksLikeAddress(messageParam) && !_looksLikeAddress(addressParam)) {
        addressParam = params[0] as String?;
        messageParam = params[1];
      }
    }

    final signData = _buildWalletConnectSignData(messageParam, addressParam);
    if (signData == null) {
      _rejectWalletConnectRpcRequest(
        request,
        'Не удалось прочитать данные для подписи.',
      );
      return;
    }

    _enqueueWalletConnectRequest(
      WalletConnectRequest.personalSign(
        rpcRequest: request,
        sign: signData,
      ),
    );
  }

  void _handleWalletConnectEthSignRequest(JsonRpcRequest request) {
    final params = request.params ?? [];
    if (params.length < 2) {
      _rejectWalletConnectRpcRequest(
        request,
        'Некорректные параметры подписи.',
      );
      return;
    }

    final addressParam = params[0] is String ? params[0] as String? : null;
    final messageParam = params[1];
    final signData = _buildWalletConnectSignData(messageParam, addressParam);
    if (signData == null) {
      _rejectWalletConnectRpcRequest(
        request,
        'Не удалось прочитать данные для подписи.',
      );
      return;
    }

    _enqueueWalletConnectRequest(
      WalletConnectRequest.ethSign(
        rpcRequest: request,
        sign: signData,
      ),
    );
  }

  WalletConnectTransactionData? _parseWalletConnectTransaction(
      Map<String, dynamic> raw) {
    final from = _parseEthereumAddress(raw['from']);
    if (from == null) {
      return null;
    }
    final to = _parseEthereumAddress(raw['to']);
    final value = _parseBigInt(raw['value']);
    final gas = _parseBigInt(raw['gas'] ?? raw['gasLimit']);
    final gasPrice = _parseBigInt(raw['gasPrice']);
    final maxFeePerGas = _parseBigInt(raw['maxFeePerGas']);
    final maxPriorityFeePerGas = _parseBigInt(raw['maxPriorityFeePerGas']);
    final nonce = _parseBigInt(raw['nonce']);
    final dataField = raw['data'] ?? raw['input'];
    final dataBytes = _parseHexBytes(dataField);

    return WalletConnectTransactionData(
      raw: raw,
      from: from,
      to: to,
      value: value != null ? EtherAmount.inWei(value) : null,
      gasLimit: gas?.toInt(),
      gasPrice: gasPrice != null ? EtherAmount.inWei(gasPrice) : null,
      maxFeePerGas:
          maxFeePerGas != null ? EtherAmount.inWei(maxFeePerGas) : null,
      maxPriorityFeePerGas: maxPriorityFeePerGas != null
          ? EtherAmount.inWei(maxPriorityFeePerGas)
          : null,
      data: dataBytes?.bytes,
      dataHex: dataBytes?.hex,
      nonce: nonce?.toInt(),
    );
  }

  WalletConnectSignData? _buildWalletConnectSignData(
    dynamic message,
    String? address,
  ) {
    final bytes = _parseMessageBytes(message);
    if (bytes == null) {
      return null;
    }
    final preview = _formatMessagePreview(bytes);
    final hex = bytesToHex(bytes, include0x: true);
    return WalletConnectSignData(
      bytes: bytes,
      preview: preview,
      rawHex: hex,
      address: _parseEthereumAddress(address),
    );
  }

  void _enqueueWalletConnectRequest(WalletConnectRequest request) {
    _walletConnectRequests.add(request);
    notifyListeners();
  }

  void _rejectWalletConnectRpcRequest(
    JsonRpcRequest request,
    String message,
  ) {
    final connector = _walletConnect;
    if (connector == null) {
      return;
    }
    unawaited(connector.rejectRequest(id: request.id, errorMessage: message));
  }

  void _clearWalletConnectSession({bool notify = true}) {
    _walletConnect = null;
    walletConnectPeerMeta = null;
    walletConnectSession = null;
    _walletConnectRequests.clear();
    isWalletConnectConnecting = false;
    isProcessingWalletConnectRequest = false;
    if (notify) {
      notifyListeners();
    }
  }

  EthereumAddress? _parseEthereumAddress(dynamic value) {
    if (value is! String || value.trim().isEmpty) {
      return null;
    }
    try {
      return EthereumAddress.fromHex(value);
    } catch (_) {
      return null;
    }
  }

  BigInt? _parseBigInt(dynamic value) {
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
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        return null;
      }
      final hasPrefix = trimmed.startsWith('0x') || trimmed.startsWith('0X');
      final cleaned = hasPrefix ? trimmed.substring(2) : trimmed;
      if (cleaned.isEmpty) {
        return BigInt.zero;
      }
      return BigInt.parse(cleaned, radix: hasPrefix ? 16 : 10);
    }
    return null;
  }

  _HexBytes? _parseHexBytes(dynamic value) {
    if (value is! String || value.trim().isEmpty) {
      return null;
    }
    final trimmed = value.trim();
    final hasPrefix = trimmed.startsWith('0x') || trimmed.startsWith('0X');
    final raw = hasPrefix ? trimmed.substring(2) : trimmed;
    if (raw.isEmpty) {
      return const _HexBytes(hex: '0x');
    }
    final even = raw.length.isOdd ? '0$raw' : raw;
    final normalized = '0x$even';
    try {
      final bytes = Uint8List.fromList(hexToBytes(normalized));
      return _HexBytes(hex: normalized, bytes: bytes);
    } catch (_) {
      return _HexBytes(hex: normalized);
    }
  }

  Uint8List? _parseMessageBytes(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is Uint8List) {
      return value;
    }
    if (value is List<int>) {
      return Uint8List.fromList(value);
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.startsWith('0x') || trimmed.startsWith('0X')) {
        final parsed = _parseHexBytes(trimmed);
        return parsed?.bytes;
      }
      return Uint8List.fromList(utf8.encode(trimmed));
    }
    return null;
  }

  String _formatMessagePreview(Uint8List bytes) {
    if (bytes.isEmpty) {
      return '(пустое сообщение)';
    }
    try {
      final decoded = utf8.decode(bytes, allowMalformed: true).trim();
      if (decoded.isNotEmpty) {
        return decoded.length > 140
            ? '${decoded.substring(0, 140)}…'
            : decoded;
      }
    } catch (_) {
      // Игнорируем и покажем hex.
    }
    return '0x${bytesToHex(bytes)}';
  }

  bool _addressesEqual(EthereumAddress a, EthereumAddress b) {
    return a.hexNo0x.toLowerCase() == b.hexNo0x.toLowerCase();
  }

  bool _looksLikeAddress(dynamic value) {
    if (value is! String) {
      return false;
    }
    final trimmed = value.trim();
    return trimmed.startsWith('0x') && trimmed.length == 42;
  }

  Future<void> _loadWalletFromKey(String privateKey, {String? mnemonic}) async {
    final credentials = EthPrivateKey.fromHex(privateKey);
    final address = await credentials.extractAddress();
    wallet = WalletData(
      privateKey: privateKey,
      address: address,
      mnemonic: mnemonic,
    );
  }

  String _normalizePrivateKey(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('Приватный ключ не должен быть пустым.');
    }
    final sanitized = trimmed.replaceAll(RegExp(r'\s+'), '');
    final hasPrefix = sanitized.startsWith('0x') || sanitized.startsWith('0X');
    final hex = hasPrefix ? sanitized.substring(2) : sanitized;
    if (hex.length != 64) {
      throw const FormatException('Приватный ключ должен содержать 64 символа.');
    }
    if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(hex)) {
      throw const FormatException(
        'Приватный ключ должен содержать только hex-символы.',
      );
    }
    return '0x${hex.toLowerCase()}';
  }

  _ImportPayload _parseImportInput(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw const FormatException(
        'Приватный ключ или фраза восстановления не должны быть пустыми.',
      );
    }

    try {
      final normalizedKey = _normalizePrivateKey(trimmed);
      return _ImportPayload(privateKey: normalizedKey);
    } on FormatException catch (error) {
      final words = trimmed
          .split(RegExp(r'\s+'))
          .where((word) => word.isNotEmpty)
          .toList();
      final wordCount = words.length;

      if (Bip39WordsNum.fromValue(wordCount) == null) {
        throw error;
      }

      final normalizedMnemonic =
          words.map((word) => word.toLowerCase()).join(' ');
      final validator = Bip39MnemonicValidator(Bip39Languages.english);
      if (!validator.validateWords(normalizedMnemonic)) {
        throw const FormatException('Некорректная фраза восстановления.');
      }

      final mnemonic = Bip39Mnemonic.fromString(normalizedMnemonic);
      final seed = Bip39SeedGenerator(mnemonic).generate();
      final derivation =
          Bip44.fromSeed(seed, Bip44Coins.ethereum).deriveDefaultPath;
      final privateKeyHex =
          BytesUtils.toHexString(derivation.privateKey.raw, prefix: '0x');

      return _ImportPayload(
        privateKey: privateKeyHex,
        mnemonic: mnemonic.toStr(),
      );
    }
  }

  @override
  void dispose() {
    final connector = _walletConnect;
    if (connector != null) {
      unawaited(connector.killSession());
    }
    _clearWalletConnectSession(notify: false);
    super.dispose();
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

enum WalletConnectRequestType {
  sendTransaction,
  personalSign,
  ethSign,
}

class WalletConnectRequest {
  WalletConnectRequest.transaction({
    required this.rpcRequest,
    required WalletConnectTransactionData transaction,
  })  : type = WalletConnectRequestType.sendTransaction,
        transaction = transaction,
        sign = null;

  WalletConnectRequest.personalSign({
    required this.rpcRequest,
    required WalletConnectSignData sign,
  })  : type = WalletConnectRequestType.personalSign,
        transaction = null,
        sign = sign;

  WalletConnectRequest.ethSign({
    required this.rpcRequest,
    required WalletConnectSignData sign,
  })  : type = WalletConnectRequestType.ethSign,
        transaction = null,
        sign = sign;

  final WalletConnectRequestType type;
  final JsonRpcRequest rpcRequest;
  final WalletConnectTransactionData? transaction;
  final WalletConnectSignData? sign;

  int get id => rpcRequest.id;
  String get method => rpcRequest.method;
}

class WalletConnectTransactionData {
  WalletConnectTransactionData({
    required this.raw,
    required this.from,
    this.to,
    this.value,
    this.gasLimit,
    this.gasPrice,
    this.maxFeePerGas,
    this.maxPriorityFeePerGas,
    this.data,
    this.dataHex,
    this.nonce,
  });

  final Map<String, dynamic> raw;
  final EthereumAddress from;
  final EthereumAddress? to;
  final EtherAmount? value;
  final int? gasLimit;
  final EtherAmount? gasPrice;
  final EtherAmount? maxFeePerGas;
  final EtherAmount? maxPriorityFeePerGas;
  final Uint8List? data;
  final String? dataHex;
  final int? nonce;
}

class WalletConnectSignData {
  WalletConnectSignData({
    required this.bytes,
    required this.preview,
    required this.rawHex,
    this.address,
  });

  final Uint8List bytes;
  final String preview;
  final String rawHex;
  final EthereumAddress? address;
}

class _HexBytes {
  const _HexBytes({required this.hex, this.bytes});

  final String hex;
  final Uint8List? bytes;
}

class _ImportPayload {
  const _ImportPayload({
    required this.privateKey,
    this.mnemonic,
  });

  final String privateKey;
  final String? mnemonic;
}

class WalletStorage {
  static const _privateKeyKey = 'wallet_private_key';
  static const _mnemonicKey = 'wallet_mnemonic';

  Future<String?> readPrivateKey() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_privateKeyKey);
  }

  Future<String?> readMnemonic() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_mnemonicKey);
  }

  Future<void> savePrivateKey(String value, {String? mnemonic}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_privateKeyKey, value);
    if (mnemonic != null) {
      await prefs.setString(_mnemonicKey, mnemonic);
    }
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_privateKeyKey);
    await prefs.remove(_mnemonicKey);
  }
}

class WalletData {
  WalletData({
    required this.privateKey,
    required this.address,
    this.mnemonic,
  });

  final String privateKey;
  final EthereumAddress address;
  final String? mnemonic;
}

class NetworkConfiguration {
  const NetworkConfiguration({
    required this.id,
    required this.name,
    required this.rpcUrl,
    required this.chainId,
    required this.symbol,
    required this.explorerApiUrl,
  });

  final String id;
  final String name;
  final String rpcUrl;
  final int chainId;
  final String symbol;
  final String explorerApiUrl;

  static const mainnet = NetworkConfiguration(
    id: 'mainnet',
    name: 'Ethereum Mainnet',
    rpcUrl: 'https://ethereum.publicnode.com',
    chainId: 1,
    symbol: 'ETH',
    explorerApiUrl: 'https://eth.blockscout.com/api',
  );

  static const sepolia = NetworkConfiguration(
    id: 'sepolia',
    name: 'Ethereum Sepolia Testnet',
    rpcUrl: 'https://ethereum-sepolia.publicnode.com',
    chainId: 11155111,
    symbol: 'ETH',
    explorerApiUrl: 'https://eth-sepolia.blockscout.com/api',
  );

  static List<NetworkConfiguration> get supportedNetworks => const [
    mainnet,
    sepolia,
  ];
}

class AmountParser {
  static final _amountRegex = RegExp(r'^([0-9]+)(?:\.([0-9]{1,18}))?$');

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

class TransactionEntry {
  TransactionEntry({
    required this.hash,
    required this.from,
    this.to,
    required this.value,
    required this.gasUsed,
    required this.gasPrice,
    required this.timestamp,
  });

  final String hash;
  final EthereumAddress from;
  final EthereumAddress? to;
  final EtherAmount value;
  final int gasUsed;
  final EtherAmount gasPrice;
  final DateTime timestamp;

  factory TransactionEntry.fromJson(Map<String, dynamic> json) {
    final fromValue = json['from']?.toString();
    if (fromValue == null || fromValue.isEmpty) {
      throw const FormatException('Отсутствует адрес отправителя.');
    }
    final toValue = json['to']?.toString();
    final valueString = json['value']?.toString() ?? '0';
    final gasPriceString = json['gasPrice']?.toString() ?? '0';
    final gasUsedString = json['gasUsed']?.toString() ?? json['gas']?.toString();
    final timestampString = json['timeStamp']?.toString() ?? '0';

    final timestampSeconds = int.tryParse(timestampString) ?? 0;
    final gasUsed = int.tryParse(gasUsedString ?? '0') ?? 0;

    EthereumAddress? toAddress;
    if (toValue != null && toValue.isNotEmpty) {
      toAddress = EthereumAddress.fromHex(toValue);
    }

    return TransactionEntry(
      hash: json['hash']?.toString() ?? '',
      from: EthereumAddress.fromHex(fromValue),
      to: toAddress,
      value: EtherAmount.inWei(BigInt.tryParse(valueString) ?? BigInt.zero),
      gasUsed: gasUsed,
      gasPrice:
          EtherAmount.inWei(BigInt.tryParse(gasPriceString) ?? BigInt.zero),
      timestamp: DateTime.fromMillisecondsSinceEpoch(
        timestampSeconds * 1000,
        isUtc: true,
      ),
    );
  }
}

class TransactionHistoryService {
  const TransactionHistoryService();

  Future<List<TransactionEntry>> fetchRecentTransactions({
    required NetworkConfiguration network,
    required EthereumAddress address,
    int limit = 100,
  }) async {
    final uri = Uri.parse(network.explorerApiUrl).replace(
      queryParameters: {
        'module': 'account',
        'action': 'txlist',
        'address': address.hexEip55,
        'startblock': '0',
        'endblock': '99999999',
        'page': '1',
        'offset': limit.toString(),
        'sort': 'desc',
      },
    );

    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw StateError(
        'Сервис вернул статус ${response.statusCode}. Попробуйте позже.',
      );
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Некорректный ответ от сервиса блокчейна.');
    }

    final status = decoded['status']?.toString();
    if (status != null && status != '1') {
      final message = decoded['message']?.toString() ?? '';
      if (message.toLowerCase().contains('no transactions')) {
        return const [];
      }
      final errorDetails = decoded['result']?.toString() ?? message;
      throw StateError('Сервис вернул ошибку: $errorDetails');
    }

    final result = decoded['result'];
    if (result is! List) {
      throw const FormatException('Не удалось разобрать список транзакций.');
    }

    return result.map((item) {
      if (item is Map<String, dynamic>) {
        return TransactionEntry.fromJson(item);
      }
      if (item is Map) {
        return TransactionEntry.fromJson(
          Map<String, dynamic>.from(item as Map<Object?, Object?>),
        );
      }
      throw const FormatException('Неверный формат элемента транзакции.');
    }).toList();
  }
}

class TransactionHistoryPage extends StatefulWidget {
  const TransactionHistoryPage({
    super.key,
    required this.address,
    required this.network,
  });

  final EthereumAddress address;
  final NetworkConfiguration network;

  @override
  State<TransactionHistoryPage> createState() => _TransactionHistoryPageState();
}

class _TransactionHistoryPageState extends State<TransactionHistoryPage> {
  final TransactionHistoryService _service = const TransactionHistoryService();
  List<TransactionEntry>? _transactions;
  Object? _error;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    unawaited(_loadTransactions());
  }

  Future<void> _loadTransactions() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final items = await _service.fetchRecentTransactions(
        network: widget.network,
        address: widget.address,
        limit: 100,
      );
      if (!mounted) return;
      setState(() {
        _transactions = items;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _transactions = null;
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Транзакции'),
        actions: [
          IconButton(
            tooltip: 'Обновить список',
            onPressed: _isLoading ? null : _loadTransactions,
            icon: _isLoading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_isLoading && _transactions != null)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Не удалось загрузить транзакции: $_error',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _isLoading ? null : _loadTransactions,
                icon: const Icon(Icons.refresh),
                label: const Text('Повторить попытку'),
              ),
            ],
          ),
        ),
      );
    }

    final transactions = _transactions;
    if (transactions == null) {
      if (_isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
      return const Center(child: Text('Нет данных для отображения.'));
    }

    if (transactions.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Для этого адреса ещё нет транзакций.'),
        ),
      );
    }

    return _TransactionsTable(
      transactions: transactions,
      symbol: widget.network.symbol,
    );
  }
}

class _TransactionsTable extends StatelessWidget {
  const _TransactionsTable({
    required this.transactions,
    required this.symbol,
  });

  final List<TransactionEntry> transactions;
  final String symbol;

  @override
  Widget build(BuildContext context) {
    return Scrollbar(
      thumbVisibility: true,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: const [
                DataColumn(label: Text('Дата')),
                DataColumn(label: Text('Откуда')),
                DataColumn(label: Text('Куда')),
                DataColumn(label: Text('Сумма')),
                DataColumn(label: Text('Газ')),
              ],
              rows: transactions
                  .map(
                    (transaction) => DataRow(
                      cells: [
                        DataCell(Text(_formatDate(transaction.timestamp))),
                        DataCell(_AddressCell(transaction.from.hexEip55)),
                        DataCell(
                          _AddressCell(
                            transaction.to?.hexEip55 ?? '—',
                          ),
                        ),
                        DataCell(
                          Text(
                            '${_formatValue(transaction.value)} $symbol',
                          ),
                        ),
                        DataCell(
                          Text(
                            '${transaction.gasUsed} @ '
                            '${_formatGasPrice(transaction.gasPrice)} Gwei',
                          ),
                        ),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }

  static String _formatDate(DateTime dateTime) {
    final local = dateTime.toLocal();
    final twoDigits = (int value) => value.toString().padLeft(2, '0');
    final date =
        '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)}';
    final time =
        '${twoDigits(local.hour)}:${twoDigits(local.minute)}:${twoDigits(local.second)}';
    return '$date $time';
  }

  static String _formatValue(EtherAmount amount) {
    final value = amount.getValueInUnit(EtherUnit.ether);
    if (value == 0) {
      return '0';
    }
    if (value >= 1) {
      return value.toStringAsFixed(6);
    }
    return value.toStringAsFixed(8);
  }

  static String _formatGasPrice(EtherAmount gasPrice) {
    final gwei = gasPrice.getValueInUnit(EtherUnit.gwei);
    return gwei.toStringAsFixed(2);
  }
}

class _AddressCell extends StatelessWidget {
  const _AddressCell(this.value);

  final String value;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: SelectableText(
        value,
        style: const TextStyle(fontSize: 13),
      ),
    );
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
