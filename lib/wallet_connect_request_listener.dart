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
  WalletConnectRequestLogEntry? _activeEntry;
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
    super.dispose();
  }

  void _handleQueueUpdate() {
    if (!mounted) {
      return;
    }
    final WalletConnectRequestLogEntry? pending =
        _manager.firstPendingLog;
    if (pending != null) {
      if (_dialogOpen &&
          _activeEntry?.request.requestId == pending.request.requestId) {
        return;
      }
      _activeEntry = pending;
      _dialogOpen = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _openDialog(pending);
      });
    } else {
      _activeEntry = null;
      _dialogOpen = false;
    }
  }

  Future<void> _openDialog(WalletConnectRequestLogEntry entry) async {
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
    _activeEntry = null;
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _handleQueueUpdate());
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
