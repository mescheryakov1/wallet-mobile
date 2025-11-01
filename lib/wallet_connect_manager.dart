import 'dart:async';

import 'package:flutter/foundation.dart';

import 'local_wallet_api.dart';
import 'wallet_connect_models.dart';
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
      requestQueue.getFirstPending();

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
    await service.approvePendingRequest(requestId);
  }

  Future<void> rejectRequest(int requestId) async {
    final WalletConnectRequestLogEntry? entry = requestQueue.findById(requestId);
    if (entry == null) {
      throw StateError('Request $requestId not found');
    }
    if (entry.status != WalletConnectRequestStatus.pending) {
      return;
    }
    await service.rejectPendingRequest(requestId);
  }

  void dismissRequest(int requestId) {
    requestQueue.dismiss(requestId);
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
    );
    requestQueue.addOrUpdate(entry);
    notifyListeners();
  }

  @override
  void dispose() {
    _requestSubscription?.cancel();
    _service?.removeListener(_handleServiceUpdate);
    super.dispose();
  }
}
