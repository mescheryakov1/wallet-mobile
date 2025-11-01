import 'package:flutter/foundation.dart';

/// Represents the status of a WalletConnect JSON-RPC request.
enum WalletConnectRequestStatus {
  pending,
  broadcasting,
  approved,
  rejected,
  done,
  error,
}

/// Basic metadata describing the connected dApp.
@immutable
class WalletConnectPeerMetadata {
  WalletConnectPeerMetadata({
    required this.name,
    this.description,
    this.url,
    this.icons = const <String>[],
  });

  final String name;
  final String? description;
  final String? url;
  final List<String> icons;

  /// Convenience getter returning the first icon URL if present.
  String? get iconUrl => icons.isNotEmpty ? icons.first : null;
}

/// Snapshot of an approved WalletConnect session in the app.
@immutable
class WalletSessionInfo {
  WalletSessionInfo({
    required this.topic,
    required this.dappName,
    required this.chains,
    required this.accounts,
    required this.methods,
    required this.events,
    this.dappUrl,
    this.iconUrl,
    this.dappDescription,
    this.expiry,
    this.approvedAt,
    this.peer,
    this.isActive = true,
  });

  factory WalletSessionInfo.fromJson(Map<String, dynamic> json) {
    return WalletSessionInfo(
      topic: json['topic'] as String? ?? '',
      dappName: json['dappName'] as String? ?? '',
      dappUrl: json['dappUrl'] as String?,
      iconUrl: json['iconUrl'] as String?,
      dappDescription: json['dappDescription'] as String?,
      chains: (json['chains'] as List?)
              ?.whereType<String>()
              .toList(growable: false) ??
          const <String>[],
      accounts: (json['accounts'] as List?)
              ?.whereType<String>()
              .toList(growable: false) ??
          const <String>[],
      methods: (json['methods'] as List?)
              ?.whereType<String>()
              .toList(growable: false) ??
          const <String>[],
      events: (json['events'] as List?)
              ?.whereType<String>()
              .toList(growable: false) ??
          const <String>[],
      expiry: json['expiry'] as int?,
      approvedAt: json['approvedAt'] as int?,
      isActive: json['isActive'] as bool? ?? true,
    );
  }

  final String topic;
  final String dappName;
  final List<String> chains;
  final List<String> accounts;
  final List<String> methods;
  final List<String> events;
  final String? dappUrl;
  final String? iconUrl;
  final String? dappDescription;
  final int? expiry;
  final int? approvedAt;
  final WalletConnectPeerMetadata? peer;
  final bool isActive;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'topic': topic,
      'dappName': dappName,
      if (dappUrl != null) 'dappUrl': dappUrl,
      if (iconUrl != null) 'iconUrl': iconUrl,
      if (dappDescription != null) 'dappDescription': dappDescription,
      'chains': chains,
      'accounts': accounts,
      'methods': methods,
      'events': events,
      if (expiry != null) 'expiry': expiry,
      if (approvedAt != null) 'approvedAt': approvedAt,
      'isActive': isActive,
    };
  }

  WalletSessionInfo copyWith({
    String? topic,
    String? dappName,
    List<String>? chains,
    List<String>? accounts,
    List<String>? methods,
    List<String>? events,
    String? dappUrl,
    String? iconUrl,
    String? dappDescription,
    int? expiry,
    int? approvedAt,
    WalletConnectPeerMetadata? peer,
    bool? isActive,
  }) {
    return WalletSessionInfo(
      topic: topic ?? this.topic,
      dappName: dappName ?? this.dappName,
      chains: chains ?? this.chains,
      accounts: accounts ?? this.accounts,
      methods: methods ?? this.methods,
      events: events ?? this.events,
      dappUrl: dappUrl ?? this.dappUrl,
      iconUrl: iconUrl ?? this.iconUrl,
      dappDescription: dappDescription ?? this.dappDescription,
      expiry: expiry ?? this.expiry,
      approvedAt: approvedAt ?? this.approvedAt,
      peer: peer ?? this.peer,
      isActive: isActive ?? this.isActive,
    );
  }
}

/// Lightweight record of the most recent WalletConnect action.
@immutable
class WalletConnectActivityEntry {
  WalletConnectActivityEntry({
    this.requestId,
    required this.method,
    required this.summary,
    required this.status,
    this.chainId,
    this.result,
    this.error,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final int? requestId;
  final String method;
  final String summary;
  final WalletConnectRequestStatus status;
  final String? chainId;
  final String? result;
  final String? error;
  final DateTime timestamp;

  WalletConnectActivityEntry copyWith({
    int? requestId,
    String? method,
    String? summary,
    WalletConnectRequestStatus? status,
    String? chainId,
    String? result,
    String? error,
    DateTime? timestamp,
  }) {
    return WalletConnectActivityEntry(
      requestId: requestId ?? this.requestId,
      method: method ?? this.method,
      summary: summary ?? this.summary,
      status: status ?? this.status,
      chainId: chainId ?? this.chainId,
      result: result ?? this.result,
      error: error ?? this.error,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}

@immutable
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

@immutable
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

@immutable
class WalletConnectRequestLogEntry {
  WalletConnectRequestLogEntry({
    required this.request,
    required this.status,
    this.result,
    this.error,
    this.isDismissed = false,
    DateTime? timestamp,
    this.txHash,
  }) : timestamp = timestamp ?? DateTime.now();

  final WalletConnectPendingRequest request;
  final WalletConnectRequestStatus status;
  final String? result;
  final String? error;
  final DateTime timestamp;
  final bool isDismissed;
  final String? txHash;

  WalletConnectRequestLogEntry copyWith({
    WalletConnectRequestStatus? status,
    String? result,
    String? error,
    DateTime? timestamp,
    bool? isDismissed,
    String? txHash,
  }) {
    return WalletConnectRequestLogEntry(
      request: request,
      status: status ?? this.status,
      result: result ?? this.result,
      error: error ?? this.error,
      timestamp: timestamp ?? this.timestamp,
      isDismissed: isDismissed ?? this.isDismissed,
      txHash: txHash ?? this.txHash,
    );
  }
}

class WalletConnectRequestQueue extends ChangeNotifier {
  final List<WalletConnectRequestLogEntry> _entries =
      <WalletConnectRequestLogEntry>[];

  List<WalletConnectRequestLogEntry> get entries =>
      List<WalletConnectRequestLogEntry>.unmodifiable(_entries);

  WalletConnectRequestLogEntry? getFirstPending() {
    for (final WalletConnectRequestLogEntry entry in _entries) {
      if (entry.status == WalletConnectRequestStatus.pending &&
          !entry.isDismissed) {
        return entry;
      }
    }
    return null;
  }

  bool hasPending() {
    for (final WalletConnectRequestLogEntry entry in _entries) {
      if (entry.status == WalletConnectRequestStatus.pending ||
          entry.status == WalletConnectRequestStatus.broadcasting) {
        return true;
      }
    }
    return false;
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
      final bool preserveDismissed = existing.isDismissed &&
          entry.status == WalletConnectRequestStatus.pending;
      final bool nextDismissed = preserveDismissed
          ? true
          : (existing.isDismissed || entry.isDismissed);
      _entries[index] = entry.copyWith(
        isDismissed: nextDismissed,
        txHash: entry.txHash ?? existing.txHash,
      );
    }
    notifyListeners();
  }

  void dismiss(int requestId) {
    final WalletConnectRequestLogEntry? existing = findById(requestId);
    if (existing == null || existing.status != WalletConnectRequestStatus.pending) {
      return;
    }
    final int index = _entries.indexOf(existing);
    _entries[index] = existing.copyWith(isDismissed: true);
    notifyListeners();
  }

  void clear() {
    _entries.clear();
    notifyListeners();
  }
}
