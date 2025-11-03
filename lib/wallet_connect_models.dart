// ignore_for_file: public_member_api_docs

import 'package:flutter/foundation.dart';
import 'package:walletconnect_flutter_v2/apis/sign_api/models/session_models.dart'
    as wc;

/// Represents the status of a WalletConnect JSON-RPC request.
enum WalletConnectRequestStatus {
  pending,
  broadcasting,
  approved,
  rejected,
  done,
  error,
}

@immutable
class WalletConnectSessionInfo {
@immutable
class WalletConnectSessionInfo {
  const WalletConnectSessionInfo({
    required this.topic,
    required this.peerName,
    this.peerUrl,
    this.peerIcon,
    this.peerDescription,
    required this.accounts,
    this.createdAt,
    required this.namespaces,
    this.updatedAt,
  });

  final String topic;
  final String peerName;
  final String? peerUrl;
  final String? peerIcon;
  final String? peerDescription;
  final List<String> accounts;
  final int? createdAt;
  final Map<String, wc.Namespace> namespaces;
  final DateTime? updatedAt;

  factory WalletConnectSessionInfo.fromSessionData(wc.SessionData session) {
    final metadata = session.peer.metadata;
    final List<String> accounts = <String>[];
    session.namespaces.values.forEach(accounts.addAll);
    final String? icon = metadata.icons.isNotEmpty ? metadata.icons.first : null;
    return WalletConnectSessionInfo(
      topic: session.topic,
      peerName: metadata.name,
      peerUrl: metadata.url,
      peerIcon: icon,
      peerDescription: metadata.description,
      accounts: accounts,
      createdAt: session.expiry,
      namespaces: session.namespaces,
      updatedAt: DateTime.now(),
    );
  }

  WalletConnectSessionInfo copyWith({
    String? peerName,
    String? peerUrl,
    String? peerIcon,
    String? peerDescription,
    List<String>? accounts,
    int? createdAt,
    Map<String, wc.Namespace>? namespaces,
    DateTime? updatedAt,
  }) {
    return WalletConnectSessionInfo(
      topic: topic,
      peerName: peerName ?? this.peerName,
      peerUrl: peerUrl ?? this.peerUrl,
      peerIcon: peerIcon ?? this.peerIcon,
      peerDescription: peerDescription ?? this.peerDescription,
      accounts: accounts ?? this.accounts,
      createdAt: createdAt ?? this.createdAt,
      namespaces: namespaces ?? this.namespaces,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'topic': topic,
      'peerName': peerName,
      'peerUrl': peerUrl,
      'peerIcon': peerIcon,
      'peerDescription': peerDescription,
      'accounts': accounts,
      'namespaces': namespaces.map(
        (String key, wc.Namespace value) => MapEntry<String, dynamic>(
          key,
          <String, dynamic>{
            'accounts': value.accounts,
            'methods': value.methods,
            'events': value.events,
          },
        ),
      ),
      if (createdAt != null) 'createdAt': createdAt,
      if (updatedAt != null) 'updatedAt': updatedAt!.millisecondsSinceEpoch,
    };
  }

  factory WalletConnectSessionInfo.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> namespacesJson =
        (json['namespaces'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
    final Map<String, wc.Namespace> namespaces = <String, wc.Namespace>{};
    namespacesJson.forEach((String key, dynamic value) {
      final Map<String, dynamic> namespaceMap =
          (value as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
      namespaces[key] = wc.Namespace(
        accounts: (namespaceMap['accounts'] as List?)
                ?.whereType<String>()
                .toList(growable: false) ??
            const <String>[],
        methods: (namespaceMap['methods'] as List?)
                ?.whereType<String>()
                .toList(growable: false) ??
            const <String>[],
        events: (namespaceMap['events'] as List?)
                ?.whereType<String>()
                .toList(growable: false) ??
            const <String>[],
      );
    });

    final Map<String, dynamic>? legacyPeer =
        (json['peer'] as Map?)?.cast<String, dynamic>();
    final String? resolvedName =
        json['peerName'] as String? ?? json['dappName'] as String? ??
            legacyPeer?['name'] as String?;
    final String? resolvedUrl =
        json['peerUrl'] as String? ?? json['dappUrl'] as String? ??
            legacyPeer?['url'] as String?;
    final List<String> legacyIcons =
        (legacyPeer?['icons'] as List?)?.whereType<String>().toList() ??
        const <String>[];
    final String? resolvedIcon = json['peerIcon'] as String? ??
        json['iconUrl'] as String? ??
        (legacyIcons.isNotEmpty ? legacyIcons.first : null);
    final String? resolvedDescription =
        json['peerDescription'] as String? ??
        legacyPeer?['description'] as String?;

    return WalletConnectSessionInfo(
      topic: json['topic'] as String? ?? '',
      peerName: resolvedName ?? '',
      peerUrl: resolvedUrl,
      peerIcon: resolvedIcon,
      peerDescription: resolvedDescription,
      accounts: (json['accounts'] as List?)
              ?.whereType<String>()
              .toList(growable: false) ??
          const <String>[],
      createdAt: json['createdAt'] as int?,
      namespaces: namespaces,
      updatedAt: json['updatedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int)
          : null,
    );
  }

  List<String> get chains {
    final Set<String> chains = <String>{};
    for (final wc.Namespace namespace in namespaces.values) {
      for (final String account in namespace.accounts) {
        final String? chain = _extractChainFromAccount(account);
        if (chain != null) {
          chains.add(chain);
        }
      }
    }
    return chains.toList(growable: false);
  }

  List<String> get methods {
    final Set<String> methods = <String>{};
    for (final wc.Namespace namespace in namespaces.values) {
      methods.addAll(namespace.methods);
    }
    return methods.toList(growable: false);
  }

  List<String> get events {
    final Set<String> events = <String>{};
    for (final wc.Namespace namespace in namespaces.values) {
      events.addAll(namespace.events);
    }
    return events.toList(growable: false);
  }

  String? get dappName => peerName.isEmpty ? null : peerName;

  String? get dappUrl => peerUrl;

  String? get iconUrl => peerIcon;

  static String? _extractChainFromAccount(String account) {
    final List<String> parts = account.split(':');
    if (parts.length < 2) {
      return null;
    }
    return '${parts[0]}:${parts[1]}'.toLowerCase();
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
  const WalletConnectPendingRequest({
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
  const WalletConnectRequestEvent({
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
  const WalletConnectRequestLogEntry({
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
