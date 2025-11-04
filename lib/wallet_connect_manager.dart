import 'dart:async';

import 'package:flutter/foundation.dart';

import 'local_wallet_api.dart';
import 'wallet_connect_models.dart';
import 'wallet_connect_popup_controller.dart';
import 'wallet_connect_service.dart';

class WalletConnectManager extends ChangeNotifier {
  WalletConnectManager._();

  static final WalletConnectManager instance = WalletConnectManager._();

  WalletConnectService? _service;
  StreamSubscription<WalletConnectRequestEvent>? _requestSubscription;
  bool _initialized = false;

  final WalletConnectRequestQueue requestQueue = WalletConnectRequestQueue();
  WalletConnectRequestEvent? _lastRequestEvent;

  WalletConnectService get service {
    final WalletConnectService? svc = _service;
    if (svc == null) {
      throw StateError('WalletConnectManager has not been initialized');
    }
    return svc;
  }

  WalletConnectRequestEvent? get lastRequestEvent => _lastRequestEvent;

  Future<void> initialize({
    required LocalWalletApi walletApi,
    String? projectId,
  }) async {
    if (_initialized) {
      return;
    }

    final WalletConnectService svc = WalletConnectService(
      walletApi: walletApi,
      projectId: projectId,
    );
    _service = svc
      ..addListener(_handleServiceUpdate);
    _requestSubscription = svc.requestEvents.listen(_handleRequestEvent);
    await svc.init();
    _initialized = true;
    notifyListeners();
  }

  WalletConnectPendingRequest? get pendingRequest => service.pendingRequest;

  WalletConnectRequestLogEntry? get firstPendingLog =>
      requestQueue.firstPendingLog;

  List<WalletConnectRequestLogEntry> get activityLog => requestQueue.entries;

  bool get hasPendingRequests => requestQueue.hasPending();

  Future<void> approveRequest(int requestId) async {
    final WalletConnectRequestLogEntry? entry = requestQueue.findById(requestId);
    if (entry == null) {
      throw StateError('Request $requestId not found');
    }
    if (entry.status != WalletConnectRequestStatus.pending) {
      return;
    }
    final method = entry.request.method;
    if (method == 'session_proposal') {
      await service.approveSessionProposal(requestId.toString());
    } else {
      await service.approveRequest(requestId.toString());
    }
  }

  Future<void> rejectRequest(int requestId) async {
    final WalletConnectRequestLogEntry? entry = requestQueue.findById(requestId);
    if (entry == null) {
      throw StateError('Request $requestId not found');
    }
    if (entry.status != WalletConnectRequestStatus.pending) {
      return;
    }
    final method = entry.request.method;
    if (method == 'session_proposal') {
      await service.rejectSessionProposal(requestId.toString());
    } else {
      await service.rejectRequest(requestId.toString());
    }
  }

  void dismissRequest(int requestId) {
    requestQueue.dismiss(requestId);
    final WalletConnectRequestLogEntry? nextPending = _firstActionableRequest();
    if (nextPending != null) {
      WalletConnectPopupController.show(nextPending);
    } else {
      WalletConnectPopupController.hide();
    }
    notifyListeners();
  }

  void _handleServiceUpdate() {
    notifyListeners();
  }

  void _handleRequestEvent(WalletConnectRequestEvent event) {
    _lastRequestEvent = event;
    final WalletConnectRequestLogEntry? existing =
        requestQueue.findById(event.request.requestId);
    final WalletConnectRequestLogEntry entry = WalletConnectRequestLogEntry(
      request: event.request,
      status: event.status,
      result: event.result,
      error: event.error,
      timestamp: event.timestamp,
      isDismissed: existing?.isDismissed ?? false,
      txHash: event.request.method == 'eth_sendTransaction' &&
              (event.status == WalletConnectRequestStatus.done ||
                  event.status == WalletConnectRequestStatus.approved)
          ? event.result
          : existing?.txHash,
    );
    requestQueue.addOrUpdate(entry);
    final WalletConnectRequestLogEntry? nextPending =
        _firstActionableRequest();
    if (nextPending != null) {
      WalletConnectPopupController.show(nextPending);
    } else {
      WalletConnectPopupController.hide();
    }
    notifyListeners();
  }


  WalletConnectRequestLogEntry? _firstActionableRequest() {
    for (final WalletConnectRequestLogEntry entry in requestQueue.entries) {
      if (!entry.isDismissed &&
          (entry.status == WalletConnectRequestStatus.pending ||
              entry.status == WalletConnectRequestStatus.broadcasting)) {
        return entry;
      }
    }
    return null;
  }

  @override
  void dispose() {
    _requestSubscription?.cancel();
    _service?.removeListener(_handleServiceUpdate);
    super.dispose();
  }
}
