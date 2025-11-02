import 'package:flutter/material.dart';

import 'app_navigation.dart';
import 'wallet_connect_manager.dart';
import 'wallet_connect_models.dart';
import 'wallet_connect_request_popup.dart';

class WalletConnectPopupController {
  WalletConnectPopupController._();

  static OverlayEntry? _entry;
  static int? _currentRequestId;

  static void show(WalletConnectRequestLogEntry entry) {
    final overlayState = appNavigatorKey.currentState?.overlay;
    if (overlayState == null) {
      return;
    }

    final int requestId = entry.request.requestId;
    if (_entry != null && _currentRequestId == requestId) {
      _entry!.markNeedsBuild();
      return;
    }

    hide();
    _currentRequestId = requestId;

    _entry = OverlayEntry(
      builder: (BuildContext context) {
        return WalletConnectRequestPopup(
          entry: entry,
          onApprove: () => _handleApprove(entry),
          onReject: () => _handleReject(entry),
          onDismiss: () => _handleDismiss(entry),
        );
      },
    );

    overlayState.insert(_entry!);
  }

  static void hide() {
    _entry?.remove();
    _entry = null;
    _currentRequestId = null;
  }

  static Future<void> _handleApprove(WalletConnectRequestLogEntry entry) async {
    final manager = WalletConnectManager.instance;
    try {
      await manager.approveRequest(entry.request.requestId);
      hide();
      _showSnackBar('Request approved');
    } on StateError catch (_) {
      _showSnackBar('Request is no longer pending');
      hide();
    } catch (error) {
      _showSnackBar('Failed to approve request: $error');
    }
  }

  static Future<void> _handleReject(WalletConnectRequestLogEntry entry) async {
    final manager = WalletConnectManager.instance;
    try {
      await manager.rejectRequest(entry.request.requestId);
      hide();
      _showSnackBar('Request rejected');
    } on StateError catch (_) {
      _showSnackBar('Request is no longer pending');
      hide();
    } catch (error) {
      _showSnackBar('Failed to reject request: $error');
    }
  }

  static void _handleDismiss(WalletConnectRequestLogEntry entry) {
    WalletConnectManager.instance.dismissRequest(entry.request.requestId);
    hide();
  }

  static void _showSnackBar(String message) {
    final context = appNavigatorKey.currentContext;
    if (context == null) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }
}
