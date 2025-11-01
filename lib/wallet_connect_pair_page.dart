import 'package:flutter/material.dart';

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
  bool _isSubmitting = false;

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
    if (uri.isEmpty || _isSubmitting) {
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      await _service.pairUri(uri);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to pair: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect via URI'),
      ),
      body: Padding(
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
                onPressed: _isSubmitting ? null : _pair,
                child: _isSubmitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Pair'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
