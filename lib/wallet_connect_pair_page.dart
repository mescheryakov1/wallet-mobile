import 'package:flutter/material.dart';

import 'wallet_connect_manager.dart';
import 'wallet_connect_models.dart';
import 'wallet_connect_request_popup.dart';
import 'wallet_connect_service.dart';

class WalletConnectPairPage extends StatefulWidget {
  const WalletConnectPairPage({
    required this.service,
    super.key,
  });

  final WalletConnectService service;

  @override
  State<WalletConnectPairPage> createState() => _WalletConnectPairPageState();
}

class _WalletConnectPairPageState extends State<WalletConnectPairPage> {
  late final TextEditingController _uriController;
  final WalletConnectManager _manager = WalletConnectManager.instance;

  WalletConnectService get _service => widget.service;

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
    if (uri.isEmpty || _service.pairingInProgress) {
      return;
    }

    try {
      await _service.startPairing(uri);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pair: $error')),
      );
    }
  }

  Future<void> _handleRequestApproval(int requestId) async {
    try {
      await _manager.approveRequest(requestId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request approved')),
      );
    } on StateError catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request is no longer pending')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to approve request: $error')),
      );
    }
  }

  Future<void> _handleRequestRejection(int requestId) async {
    try {
      await _manager.rejectRequest(requestId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request rejected')),
      );
    } on StateError catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request is no longer pending')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to reject request: $error')),
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
        final bool isPairing = _service.pairingInProgress;
        final String? error = _service.pairingError;
        final WalletConnectRequestLogEntry? pendingEntry =
            _manager.firstPendingLog;
        final bool showPopup = pendingEntry != null &&
            pendingEntry.status == WalletConnectRequestStatus.pending &&
            pendingEntry.request.method == 'session_proposal';

        return Scaffold(
          appBar: AppBar(
            title: const Text('Connect via URI'),
          ),
          body: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
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
                  ],
                ),
              ),
              if (showPopup && pendingEntry != null)
                WalletConnectRequestPopup(
                  entry: pendingEntry,
                  onApprove: () =>
                      _handleRequestApproval(pendingEntry.request.requestId),
                  onReject: () =>
                      _handleRequestRejection(pendingEntry.request.requestId),
                  onDismiss: () =>
                      _manager.dismissRequest(pendingEntry.request.requestId),
                ),
            ],
          ),
        );
      },
    );
  }
}
