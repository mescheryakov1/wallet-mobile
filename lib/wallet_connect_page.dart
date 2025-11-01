import 'package:flutter/material.dart';

import 'main.dart' show WalletController;
import 'wallet_connect_service.dart';
import 'wc_request_approval_page.dart';

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

  String _shortAccount(String account) {
    final parts = account.split(':');
    final address = parts.length >= 3 ? parts[2] : account;
    if (address.length <= 10) {
      return address;
    }
    final start = address.substring(0, 6);
    final end = address.substring(address.length - 4);
    return '$start…$end';
  }

  @override
  Widget build(BuildContext context) {
    final sessions = service.getActiveSessions();
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
              child: sessions.isEmpty
                  ? const Center(
                      child: Text('No active sessions'),
                    )
                  : ListView.builder(
                      itemCount: sessions.length,
                      itemBuilder: (context, index) {
                        final session = sessions[index];
                        final chainsLabel = session.chains.isNotEmpty
                            ? 'Chains: ${session.chains.join(', ')}'
                            : null;
                        final accountsLabel = session.accounts.isNotEmpty
                            ? 'Accounts: ${session.accounts.map(_shortAccount).join(', ')}'
                            : null;
                        return ListTile(
                          title: Text(session.dappName.isNotEmpty
                              ? session.dappName
                              : session.topic),
                          subtitle: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (chainsLabel != null) Text(chainsLabel),
                              if (accountsLabel != null) Text(accountsLabel),
                              if (session.dappUrl != null &&
                                  session.dappUrl!.isNotEmpty)
                                Text(session.dappUrl!),
                            ],
                          ),
                          trailing: TextButton(
                            onPressed: () async {
                              await service.disconnectSession(session.topic);
                            },
                            child: const Text('Disconnect'),
                          ),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 16),
            Text(
              'Pending request: ${service.pendingRequest?.method ?? 'none'}',
            ),
            if (service.pendingRequest != null) ...[
              const SizedBox(height: 8),
              ElevatedButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => WcRequestApprovalPage(
                        service: service,
                      ),
                    ),
                  );
                },
                child: const Text('Review request'),
              ),
            ],
            const SizedBox(height: 24),
            const Text(
              'Debug info:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text('Last proposal: ${service.debugLastProposalLog}'),
            Text('Last error: ${service.debugLastError}'),
            const SizedBox(height: 8),
            Text('Last request: ${service.lastRequestDebug ?? ''}'),
            Text('Last request error: ${service.lastErrorDebug ?? ''}'),
          ],
        ),
      ),
    );
  }
}
