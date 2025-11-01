import 'dart:async';

import 'package:flutter/material.dart';

import 'wallet_connect_manager.dart';
import 'wallet_connect_models.dart';
import 'wc_request_approval_page.dart';

class WalletConnectRequestListener extends StatefulWidget {
  const WalletConnectRequestListener({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  State<WalletConnectRequestListener> createState() =>
      _WalletConnectRequestListenerState();
}

class _WalletConnectRequestListenerState
    extends State<WalletConnectRequestListener> {
  final WalletConnectManager _manager = WalletConnectManager.instance;
  OverlayEntry? _bannerEntry;
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    _manager.requestQueue.addListener(_handleQueueUpdate);
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleQueueUpdate());
  }

  @override
  void dispose() {
    _manager.requestQueue.removeListener(_handleQueueUpdate);
    _hideBanner();
    super.dispose();
  }

  void _handleQueueUpdate() {
    if (!mounted) {
      return;
    }
    final WalletConnectRequestLogEntry? pending =
        _manager.firstPendingLog;
    if (pending == null) {
      if (!_dialogOpen) {
        _hideBanner();
      }
      return;
    }

    if (_dialogOpen) {
      return;
    }

    _showBanner(pending);
  }

  Future<void> _openDialog(WalletConnectRequestLogEntry entry) async {
    if (_dialogOpen) {
      return;
    }
    _dialogOpen = true;
    _hideBanner();
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<bool>(
        builder: (_) => WcRequestApprovalPage(
          requestId: entry.request.requestId,
          manager: _manager,
        ),
        fullscreenDialog: true,
      ),
    );
    if (!mounted) {
      return;
    }
    _dialogOpen = false;
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _handleQueueUpdate());
  }

  void _showBanner(WalletConnectRequestLogEntry entry) {
    final overlay = Overlay.of(context, rootOverlay: true);
    if (overlay == null) {
      return;
    }
    _hideBanner();
    _bannerEntry = OverlayEntry(
      builder: (BuildContext context) {
        return _WalletConnectRequestBanner(
          entry: entry,
          onReview: () => _openDialog(entry),
          onReject: () => _rejectRequest(entry),
        );
      },
    );
    overlay.insert(_bannerEntry!);
  }

  void _hideBanner() {
    _bannerEntry?.remove();
    _bannerEntry = null;
  }

  Future<void> _rejectRequest(WalletConnectRequestLogEntry entry) async {
    try {
      await _manager.rejectRequest(entry.request.requestId);
    } catch (error) {
      if (!mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        SnackBar(content: Text('Failed to reject request: $error')),
      );
    } finally {
      if (mounted) {
        _hideBanner();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class _WalletConnectRequestBanner extends StatelessWidget {
  const _WalletConnectRequestBanner({
    required this.entry,
    required this.onReview,
    required this.onReject,
  });

  final WalletConnectRequestLogEntry entry;
  final Future<void> Function() onReview;
  final Future<void> Function() onReject;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final method = entry.request.method;
    final chainLabel = entry.request.chainId ?? 'unknown chain';
    final subtitle = '$method • $chainLabel';

    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(12),
            color: theme.colorScheme.surface,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'WalletConnect request',
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 6),
                    Text(subtitle, style: theme.textTheme.bodyMedium),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () {
                            unawaited(onReject());
                          },
                          child: const Text('Reject'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () {
                            unawaited(onReview());
                          },
                          child: const Text('Review'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
