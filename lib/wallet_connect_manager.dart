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
  late final StreamController<WalletConnectRequestLogEntry?>
      _actionableRequestController =
      StreamController<WalletConnectRequestLogEntry?>.broadcast();
  StreamSubscription<WalletConnectRequestLogEntry?>?
      _actionableRequestSubscription;
  Future<void>? _initializationFuture;
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
      return _initializationFuture ?? Future<void>.value();
    }

    if (_initializationFuture != null) {
      return _initializationFuture!;
    }

    _initializationFuture = _doInitialize(
      walletApi: walletApi,
      projectId: projectId,
    );
    return _initializationFuture!;
  }

  Future<void> _doInitialize({
    required LocalWalletApi walletApi,
    String? projectId,
  }) async {
    try {
      final WalletConnectService svc = WalletConnectService(
        walletApi: walletApi,
        projectId: projectId,
      );
      _service = svc
        ..addListener(_handleServiceUpdate);
      _requestSubscription = svc.requestEvents.listen(_handleRequestEvent);
      _actionableRequestSubscription = _actionableRequestController.stream
          .listen(_handleActionableRequest);
      await svc.init();
      _initialized = true;
      notifyListeners();
    } finally {
      if (_initialized) {
        return;
      }
      _initializationFuture = null;
    }
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
    _emitActionableRequest();
    notifyListeners();
  }

  void requeueRequest(int requestId) {
    final WalletConnectRequestLogEntry? entry = requestQueue.requeue(requestId);
    if (entry == null) {
      return;
    }
    _emitActionableRequest();
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
    _emitActionableRequest();
    notifyListeners();
  }

  void _emitActionableRequest() {
    if (_actionableRequestController.isClosed) {
      return;
    }
    _actionableRequestController.add(_firstActionableRequest());
  }

  void _handleActionableRequest(
    WalletConnectRequestLogEntry? actionableEntry,
  ) {
    if (actionableEntry != null) {
      WalletConnectPopupController.show(actionableEntry);
    } else {
      WalletConnectPopupController.hide();
    }
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
    _actionableRequestSubscription?.cancel();
    _actionableRequestController.close();
    _service?.removeListener(_handleServiceUpdate);
    super.dispose();
  }
}
