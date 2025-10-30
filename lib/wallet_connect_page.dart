import 'package:flutter/material.dart';

import 'main.dart' show WalletController;
import 'wallet_connect_service.dart';

class WalletConnectPage extends StatefulWidget {
  const WalletConnectPage({
    required this.walletController,
    super.key,
  });

  final WalletController walletController;

  @override
  State<WalletConnectPage> createState() => _WalletConnectPageState();
}

class _WalletConnectPageState extends State<WalletConnectPage> {
  late final WalletConnectService service;
  late final TextEditingController uriController;

  @override
  void initState() {
    super.initState();
    uriController = TextEditingController();
    service = WalletConnectService(walletApi: widget.walletController)
      ..addListener(_handleServiceUpdate);
    service.init();
  }

  void _handleServiceUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    service.removeListener(_handleServiceUpdate);
    service.dispose();
    uriController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WalletConnect v2'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Status: ${service.status}'),
            const SizedBox(height: 16),
            TextField(
              controller: uriController,
              decoration: const InputDecoration(
                labelText: 'wc uri',
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                await service.pairUri(uriController.text);
              },
              child: const Text('Pair'),
            ),
            const SizedBox(height: 24),
            const Text('Active sessions:'),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: service.activeSessions.length,
                itemBuilder: (context, index) {
                  final session = service.activeSessions[index];
                  return ListTile(
                    title: Text(session),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
