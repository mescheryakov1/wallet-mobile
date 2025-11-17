import 'package:flutter/material.dart';

import 'wallet_connect_manager.dart';
import 'wallet_connect_models.dart';
import 'wallet_connect_service.dart';

class WalletConnectPage extends StatefulWidget {
  const WalletConnectPage({super.key});

  @override
  State<WalletConnectPage> createState() => _WalletConnectPageState();
}

class _WalletConnectPageState extends State<WalletConnectPage> {
  late final WalletConnectManager _manager;
  late final TextEditingController _uriController;

  @override
  void initState() {
    super.initState();
    _manager = WalletConnectManager.instance;
    _manager.addListener(_handleManagerUpdate);
    _uriController = TextEditingController();
  }

  @override
  void dispose() {
    _manager.removeListener(_handleManagerUpdate);
    _uriController.dispose();
    super.dispose();
  }

  void _handleManagerUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final WalletConnectService service = _manager.service;
    final WalletConnectSessionInfo? session = service.primarySessionInfo;
    return Scaffold(
      appBar: AppBar(
        title: const Text('WalletConnect v2'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: session == null
            ? _buildConnectForm(context, service)
            : _buildConnectedSection(context, service, session),
      ),
    );
  }

  Future<void> _pair() async {
    final WalletConnectService service = _manager.service;
    final String uri = _uriController.text.trim();
    if (uri.isEmpty || service.isPairing) {
      return;
    }

    try {
      await service.connectFromUri(uri);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pair: $error')),
      );
    }
  }

  Widget _buildConnectForm(
    BuildContext context,
    WalletConnectService service,
  ) {
    final ThemeData theme = Theme.of(context);
    final bool isPairing = service.isPairing;
    final String status = service.status;
    final String? error = service.pairingError;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Connect via WalletConnect URI',
              style:
                  theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              'Paste the WalletConnect URI provided by the dApp.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _uriController,
              decoration: const InputDecoration(
                labelText: 'wc:',
                border: OutlineInputBorder(),
              ),
              minLines: 1,
              maxLines: 3,
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    'Status: $status',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                if (error != null)
                  Flexible(
                    child: Text(
                      error,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.error),
                      textAlign: TextAlign.end,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: isPairing ? null : _pair,
                child: isPairing
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Connect'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectedSection(
    BuildContext context,
    WalletConnectService service,
    WalletConnectSessionInfo session,
  ) {
    final ThemeData theme = Theme.of(context);
    final String displayName =
        (session.dappName?.isNotEmpty ?? false) ? session.dappName! : 'Connected dApp';

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              displayName,
              style:
                  theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            if (session.dappUrl != null && session.dappUrl!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                session.dappUrl!,
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'Status: ${service.status}',
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () async {
                  await service.disconnectSession(session.topic);
                },
                child: const Text('Disconnect'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
