// ignore_for_file: public_member_api_docs

import 'package:flutter/foundation.dart';
import 'package:walletconnect_flutter_v2/walletconnect_flutter_v2.dart' as wc;

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
class WalletConnectPeerMetadata {
  const WalletConnectPeerMetadata({
    this.name,
    this.url,
    this.icons,
    this.description,
  });

  final String? name;
  final String? url;
  final List<String>? icons;
  final String? description;

  factory WalletConnectPeerMetadata.fromMetadata(wc.ConnectionMetadata? metadata) {
    if (metadata == null) {
      return const WalletConnectPeerMetadata();
    }
    return WalletConnectPeerMetadata(
      name: metadata.name,
      url: metadata.url,
      icons: metadata.icons,
      description: metadata.description,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'url': url,
        'icons': icons,
        'description': description,
      };
}

@immutable
class WalletConnectSessionInfo {
  const WalletConnectSessionInfo({
    required this.topic,
    required this.namespaces,
    required this.accounts,
    required this.peer,
    required this.createdAt,
    this.updatedAt,
  });

  final String topic;
  final Map<String, wc.Namespace> namespaces;
  final List<String> accounts;
  final WalletConnectPeerMetadata peer;
  final DateTime createdAt;
  final DateTime? updatedAt;

  factory WalletConnectSessionInfo.fromSession(wc.SessionData session) {
    final List<String> accs = <String>[];
    session.namespaces.forEach((_, ns) => accs.addAll(ns.accounts));
    return WalletConnectSessionInfo(
      topic: session.topic,
      namespaces: session.namespaces,
      accounts: accs,
      peer: WalletConnectPeerMetadata.fromMetadata(session.peer.metadata),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        session.timestamp ?? DateTime.now().millisecondsSinceEpoch,
      ),
      updatedAt: DateTime.now(),
    );
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

    final List<String> accountsFromJson = (json['accounts'] as List?)
            ?.whereType<String>()
            .toList(growable: false) ??
        const <String>[];

    if (namespaces.isEmpty &&
        (json.containsKey('chains') || json.containsKey('methods'))) {
      final List<String> methods = (json['methods'] as List?)
              ?.whereType<String>()
              .toList(growable: false) ??
          const <String>[];
      final List<String> events = (json['events'] as List?)
              ?.whereType<String>()
              .toList(growable: false) ??
          const <String>[];
      namespaces['eip155'] = wc.Namespace(
        accounts: accountsFromJson,
        methods: methods,
        events: events,
      );
    }

    final Map<String, dynamic>? peerJson =
        (json['peer'] as Map?)?.cast<String, dynamic>();
    return WalletConnectSessionInfo(
      topic: json['topic'] as String? ?? '',
      namespaces: namespaces,
      accounts: accountsFromJson,
      peer: WalletConnectPeerMetadata(
        name: peerJson?['name'] as String?,
        url: peerJson?['url'] as String?,
        icons: (peerJson?['icons'] as List?)
            ?.whereType<String>()
            .toList(growable: false),
        description: peerJson?['description'] as String?,
      ),
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        json['createdAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
      ),
      updatedAt: json['updatedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int)
          : null,
    );
  }

  WalletConnectSessionInfo copyWith({
    Map<String, wc.Namespace>? namespaces,
    List<String>? accounts,
    WalletConnectPeerMetadata? peer,
    DateTime? updatedAt,
  }) {
    return WalletConnectSessionInfo(
      topic: topic,
      namespaces: namespaces ?? this.namespaces,
      accounts: accounts ?? this.accounts,
      peer: peer ?? this.peer,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'topic': topic,
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
      'accounts': accounts,
      'chains': chains,
      'methods': methods,
      'events': events,
      'dappName': dappName,
      'dappUrl': dappUrl,
      'iconUrl': iconUrl,
      'peer': peer.toJson(),
      'createdAt': createdAt.millisecondsSinceEpoch,
      if (updatedAt != null) 'updatedAt': updatedAt!.millisecondsSinceEpoch,
    };
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

  String? get dappName => peer.name;

  String? get dappUrl => peer.url;

  String? get iconUrl =>
      (peer.icons != null && peer.icons!.isNotEmpty) ? peer.icons!.first : null;

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
