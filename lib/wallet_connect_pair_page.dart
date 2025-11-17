import 'package:flutter/material.dart';

import 'wallet_connect_manager.dart';
import 'wallet_connect_models.dart';
import 'wallet_connect_service.dart';

class WalletConnectPairPage extends StatefulWidget {
  const WalletConnectPairPage({super.key});

  @override
  State<WalletConnectPairPage> createState() => _WalletConnectPairPageState();
}

class _WalletConnectPairPageState extends State<WalletConnectPairPage> {
  late final TextEditingController _uriController;
  final WalletConnectManager _manager = WalletConnectManager.instance;
  WalletConnectService get _service => _manager.service;

  @override
  void initState() {
    super.initState();
    _uriController = TextEditingController();
  }

  @override
  void dispose() {
    _uriController.dispose();
    super.dispose();
  }

  Future<void> _pair() async {
    final uri = _uriController.text.trim();
    if (uri.isEmpty || _service.isPairing) {
      return;
    }

    try {
      await _service.connectFromUri(uri);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pair: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge(
        <Listenable>[
          _service,
          _manager,
          _manager.requestQueue,
        ],
      ),
      builder: (BuildContext context, Widget? _) {
        final bool isPairing = _service.isPairing;
        final String? error = _service.pairingError;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Connect via URI'),
          ),
          body: _buildConnectForm(
            isPairing: isPairing,
            error: error,
            status: _service.status,
            session: _service.primarySessionInfo,
          ),
        );
      },
    );
  }

  Widget _buildConnectForm({
    required bool isPairing,
    required String? error,
    required String status,
    required WalletConnectSessionInfo? session,
  }) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Status: $status',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 12),
          const Text(
            'Paste the WalletConnect URI provided by the dApp.',
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
          if (isPairing) ...[
            const SizedBox(height: 16),
            Row(
              children: const <Widget>[
                SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text('Waiting for session proposal...'),
                ),
              ],
            ),
          ],
          if (error != null) ...[
            const SizedBox(height: 16),
            Text(
              error,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ],
          if (session != null) ...[
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () async {
                  await _service.disconnectSession(session.topic);
                },
                child: const Text('Disconnect'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
