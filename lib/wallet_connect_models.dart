import 'package:flutter/foundation.dart';

enum WalletConnectRequestStatus { pending, approved, rejected }

class WalletConnectPendingRequest {
  WalletConnectPendingRequest({
    required this.topic,
    required this.requestId,
    required this.method,
    required this.params,
    this.chainId,
  });

  final String topic;
  final int requestId;
  final String method;
  final dynamic params;
  final String? chainId;
}

class WalletConnectRequestEvent {
  WalletConnectRequestEvent({
    required this.request,
    required this.status,
    this.result,
    this.error,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final WalletConnectPendingRequest request;
  final WalletConnectRequestStatus status;
  final String? result;
  final String? error;
  final DateTime timestamp;
}

class WalletConnectRequestLogEntry {
  WalletConnectRequestLogEntry({
    required this.request,
    required this.status,
    this.result,
    this.error,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final WalletConnectPendingRequest request;
  final WalletConnectRequestStatus status;
  final String? result;
  final String? error;
  final DateTime timestamp;
}

class WalletConnectRequestQueue extends ChangeNotifier {
  final List<WalletConnectRequestLogEntry> _entries =
      <WalletConnectRequestLogEntry>[];

  List<WalletConnectRequestLogEntry> get entries =>
      List<WalletConnectRequestLogEntry>.unmodifiable(_entries);

  WalletConnectRequestLogEntry? getFirstPending() {
    for (final WalletConnectRequestLogEntry entry in _entries) {
      if (entry.status == WalletConnectRequestStatus.pending) {
        return entry;
      }
    }
    return null;
  }

  WalletConnectRequestLogEntry? findById(int id) {
    for (final WalletConnectRequestLogEntry entry in _entries) {
      if (entry.request.requestId == id) {
        return entry;
      }
    }
    return null;
  }

  void addOrUpdate(WalletConnectRequestLogEntry entry) {
    final WalletConnectRequestLogEntry? existing =
        findById(entry.request.requestId);
    if (existing == null) {
      _entries.add(entry);
    } else {
      final int index = _entries.indexOf(existing);
      _entries[index] = entry;
    }
    notifyListeners();
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }
}
