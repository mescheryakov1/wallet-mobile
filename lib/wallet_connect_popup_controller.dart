import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'core/navigation/navigator_key.dart';
import 'core/ui/popup_coordinator.dart';
import 'wallet_connect_manager.dart';
import 'wallet_connect_models.dart';
import 'wallet_connect_request_popup.dart';

class WalletConnectPopupController {
  WalletConnectPopupController._();

  static ValueNotifier<WalletConnectRequestLogEntry>? _entryNotifier;
  static int? _currentRequestId;
  static BuildContext? _dialogContext;

  static void show(WalletConnectRequestLogEntry entry) {
    final int requestId = entry.request.requestId;
    if (_currentRequestId == requestId && _entryNotifier != null) {
      _entryNotifier!.value = entry;
      return;
    }
    final ValueNotifier<WalletConnectRequestLogEntry>? currentNotifier =
        _entryNotifier;
    if (_dialogContext == null &&
        currentNotifier != null &&
        currentNotifier.value.request.requestId == requestId) {
      currentNotifier.value = entry;
      return;
    }

    hide();
    final notifier = ValueNotifier<WalletConnectRequestLogEntry>(entry);
    _entryNotifier = notifier;

    PopupCoordinator.I.enqueue((BuildContext context) {
      if (_entryNotifier != notifier) {
        SchedulerBinding.instance.addPostFrameCallback((_) {
          final NavigatorState navigator = Navigator.of(context);
          if (navigator.canPop()) {
            navigator.pop();
          }
        });
        return const SizedBox.shrink();
      }
      return WillPopScope(
        onWillPop: () async => false,
        child: _WalletConnectPopupDialog(
          notifier: notifier,
        ),
      );
    });
  }

  static void hide() {
    final BuildContext? context = _dialogContext;
    final ValueNotifier<WalletConnectRequestLogEntry>? notifier = _entryNotifier;
    _dialogContext = null;
    _currentRequestId = null;
    _entryNotifier = null;
    if (context != null) {
      final NavigatorState navigator = Navigator.of(context);
      if (navigator.canPop()) {
        navigator.pop();
      }
    } else {
      notifier?.dispose();
    }
  }

  static Future<void> _handleApprove() async {
    final WalletConnectRequestLogEntry? entry = _entryNotifier?.value;
    if (entry == null) {
      return;
    }
    final manager = WalletConnectManager.instance;
    try {
      final int requestId = entry.request.requestId;
      manager.dismissRequest(requestId);
      await manager.approveRequest(requestId);
      _showSnackBar('Request approved');
    } on StateError catch (_) {
      _showSnackBar('Request is no longer pending');
    } catch (error) {
      manager.requeueRequest(entry.request.requestId);
      _showSnackBar('Failed to approve request: $error');
    }
  }

  static Future<void> _handleReject() async {
    final WalletConnectRequestLogEntry? entry = _entryNotifier?.value;
    if (entry == null) {
      return;
    }
    final manager = WalletConnectManager.instance;
    try {
      final int requestId = entry.request.requestId;
      manager.dismissRequest(requestId);
      await manager.rejectRequest(requestId);
      _showSnackBar('Request rejected');
    } on StateError catch (_) {
      _showSnackBar('Request is no longer pending');
    } catch (error) {
      manager.requeueRequest(entry.request.requestId);
      _showSnackBar('Failed to reject request: $error');
    }
  }

  static void _handleDismiss() {
    final WalletConnectRequestLogEntry? entry = _entryNotifier?.value;
    if (entry == null) {
      return;
    }
    WalletConnectManager.instance.dismissRequest(entry.request.requestId);
    hide();
  }

  static void _registerDialogContext(
    BuildContext context,
    ValueNotifier<WalletConnectRequestLogEntry> notifier,
  ) {
    _dialogContext = context;
    _currentRequestId = notifier.value.request.requestId;
  }

  static void _clearDialogContext(
    BuildContext context,
    ValueNotifier<WalletConnectRequestLogEntry> notifier,
  ) {
    if (_dialogContext == context) {
      _dialogContext = null;
    }
    if (_currentRequestId == notifier.value.request.requestId) {
      _currentRequestId = null;
    }
    if (identical(_entryNotifier, notifier)) {
      _entryNotifier = null;
    }
    notifier.dispose();
  }

  static void _showSnackBar(String message) {
    final BuildContext? context = rootNavigatorKey.currentContext;
    if (context == null) {
      return;
    }
    final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }
}

class _WalletConnectPopupDialog extends StatefulWidget {
  const _WalletConnectPopupDialog({
    required this.notifier,
  });

  final ValueNotifier<WalletConnectRequestLogEntry> notifier;

  @override
  State<_WalletConnectPopupDialog> createState() => _WalletConnectPopupDialogState();
}

class _WalletConnectPopupDialogState extends State<_WalletConnectPopupDialog> {
  @override
  void initState() {
    super.initState();
    WalletConnectPopupController._registerDialogContext(
      context,
      widget.notifier,
    );
  }

  @override
  void dispose() {
    WalletConnectPopupController._clearDialogContext(context, widget.notifier);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.zero,
      child: ValueListenableBuilder<WalletConnectRequestLogEntry>(
        valueListenable: widget.notifier,
        builder: (BuildContext context, WalletConnectRequestLogEntry entry, _) {
          return WalletConnectRequestPopup(
            entry: entry,
            onApprove: WalletConnectPopupController._handleApprove,
            onReject: WalletConnectPopupController._handleReject,
            onDismiss: WalletConnectPopupController._handleDismiss,
          );
        },
      ),
    );
  }
}
