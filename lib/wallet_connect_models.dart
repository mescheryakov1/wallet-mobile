// ignore_for_file: public_member_api_docs

import 'package:flutter/foundation.dart';
import 'package:walletconnect_flutter_v2/apis/sign_api/models/session_models.dart'
    as wc;

/// Represents the lifecycle status of a WalletConnect request.
enum WalletConnectRequestStatus {
  pending,
  broadcasting,
  approved,
  rejected,
  done,
  error,
}

/// High-level classification of WalletConnect activity entries.
enum WalletConnectActivityEntryType {
  sessionProposal,
  personalSign,
  ethSendTransaction,
  other,
}

@immutable
class WalletConnectSessionInfo {
  const WalletConnectSessionInfo({
    required this.topic,
    this.dappName,
    this.peerDescription,
    this.dappUrl,
    this.iconUrl,
    required this.accounts,
    this.createdAt,
    required this.namespaces,
    this.updatedAt,
  });

  final String topic;
  final String? dappName;
  final String? peerDescription;
  final String? dappUrl;
  final String? iconUrl;
  final List<String> accounts;
  final int? createdAt;
  final Map<String, wc.Namespace> namespaces;
  final DateTime? updatedAt;

  factory WalletConnectSessionInfo.fromSessionData(wc.SessionData session) {
    final wc.ConnectionMetadata metadata = session.peer.metadata;
    final List<String> collectedAccounts = <String>[];
    session.namespaces.values.forEach(collectedAccounts.addAll);
    final String? resolvedIcon =
        metadata.icons.isNotEmpty ? metadata.icons.first : null;
    return WalletConnectSessionInfo(
      topic: session.topic,
      dappName: metadata.name,
      peerDescription: metadata.description,
      dappUrl: metadata.url,
      iconUrl: resolvedIcon,
      accounts: List<String>.unmodifiable(collectedAccounts),
      createdAt: session.expiry,
      namespaces: session.namespaces,
      updatedAt: DateTime.now(),
    );
  }

  factory WalletConnectSessionInfo.fromJson(Map<String, dynamic> json) {
    final Map<String, dynamic> namespacesJson =
        (json['namespaces'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
    final Map<String, wc.Namespace> parsedNamespaces =
        <String, wc.Namespace>{};
    namespacesJson.forEach((String key, dynamic value) {
      final Map<String, dynamic> namespaceMap =
          (value as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
      parsedNamespaces[key] = wc.Namespace(
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
    final String? resolvedName = json['dappName'] as String? ??
        json['peerName'] as String? ??
        legacyPeer?['name'] as String?;
    final String? resolvedDescription =
        json['peerDescription'] as String? ??
        legacyPeer?['description'] as String?;
    final String? resolvedUrl = json['dappUrl'] as String? ??
        json['peerUrl'] as String? ??
        legacyPeer?['url'] as String?;
    final List<String> legacyIcons =
        (legacyPeer?['icons'] as List?)?.whereType<String>().toList() ??
        const <String>[];
    final String? resolvedIcon = json['iconUrl'] as String? ??
        json['peerIcon'] as String? ??
        (legacyIcons.isNotEmpty ? legacyIcons.first : null);

    final List<String> storedAccounts = (json['accounts'] as List?)
            ?.whereType<String>()
            .toList(growable: false) ??
        const <String>[];

    return WalletConnectSessionInfo(
      topic: json['topic'] as String? ?? '',
      dappName: resolvedName,
      peerDescription: resolvedDescription,
      dappUrl: resolvedUrl,
      iconUrl: resolvedIcon,
      accounts: List<String>.unmodifiable(storedAccounts),
      createdAt: json['createdAt'] as int?,
      namespaces: parsedNamespaces,
      updatedAt: json['updatedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int)
          : null,
    );
  }

  WalletConnectSessionInfo copyWith({
    String? dappName,
    String? peerDescription,
    String? dappUrl,
    String? iconUrl,
    List<String>? accounts,
    int? createdAt,
    Map<String, wc.Namespace>? namespaces,
    DateTime? updatedAt,
  }) {
    return WalletConnectSessionInfo(
      topic: topic,
      dappName: dappName ?? this.dappName,
      peerDescription: peerDescription ?? this.peerDescription,
      dappUrl: dappUrl ?? this.dappUrl,
      iconUrl: iconUrl ?? this.iconUrl,
      accounts: accounts ?? this.accounts,
      createdAt: createdAt ?? this.createdAt,
      namespaces: namespaces ?? this.namespaces,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'topic': topic,
      'dappName': dappName,
      'peerDescription': peerDescription,
      'dappUrl': dappUrl,
      'iconUrl': iconUrl,
      'peerName': dappName, // legacy compatibility
      'peerUrl': dappUrl,
      'peerIcon': iconUrl,
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

  String get displayName => dappName ?? '';
  String? get peerName => dappName;
  String? get peerUrl => dappUrl;
  String? get peerIcon => iconUrl;

  static String? _extractChainFromAccount(String account) {
    final List<String> parts = account.split(':');
    if (parts.length < 2) {
      return null;
    }
    return '${parts[0]}:${parts[1]}'.toLowerCase();
  }
}

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
    this.type = WalletConnectActivityEntryType.other,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final int? requestId;
  final String method;
  final String summary;
  final WalletConnectRequestStatus status;
  final String? chainId;
  final String? result;
  final String? error;
  final WalletConnectActivityEntryType type;
  final DateTime timestamp;

  WalletConnectActivityEntry copyWith({
    int? requestId,
    String? method,
    String? summary,
    WalletConnectRequestStatus? status,
    String? chainId,
    String? result,
    String? error,
    WalletConnectActivityEntryType? type,
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
      type: type ?? this.type,
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
    this.type = WalletConnectActivityEntryType.other,
  });

  final String topic;
  final int requestId;
  final String method;
  final dynamic params;
  final String? chainId;
  final WalletConnectActivityEntryType type;
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
    this.type = WalletConnectActivityEntryType.other,
    DateTime? timestamp,
    this.txHash,
  }) : timestamp = timestamp ?? DateTime.now();

  final WalletConnectPendingRequest request;
  final WalletConnectRequestStatus status;
  final String? result;
  final String? error;
  final DateTime timestamp;
  final bool isDismissed;
  final WalletConnectActivityEntryType type;
  final String? txHash;

  WalletConnectRequestLogEntry copyWith({
    WalletConnectRequestStatus? status,
    String? result,
    String? error,
    DateTime? timestamp,
    bool? isDismissed,
    WalletConnectActivityEntryType? type,
    String? txHash,
  }) {
    return WalletConnectRequestLogEntry(
      request: request,
      status: status ?? this.status,
      result: result ?? this.result,
      error: error ?? this.error,
      timestamp: timestamp ?? this.timestamp,
      isDismissed: isDismissed ?? this.isDismissed,
      type: type ?? this.type,
      txHash: txHash ?? this.txHash,
    );
  }
}

class WalletConnectRequestQueue extends ChangeNotifier {
  final List<WalletConnectRequestLogEntry> _entries =
      <WalletConnectRequestLogEntry>[];

  List<WalletConnectRequestLogEntry> get entries =>
      List<WalletConnectRequestLogEntry>.unmodifiable(_entries);

  WalletConnectRequestLogEntry? get firstPendingLog {
    for (final WalletConnectRequestLogEntry entry in _entries) {
      if (!entry.isDismissed &&
          (entry.status == WalletConnectRequestStatus.pending ||
              entry.status == WalletConnectRequestStatus.broadcasting)) {
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

  void enqueue(WalletConnectRequestLogEntry entry) {
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
        type: entry.type,
      );
    }
    notifyListeners();
  }

  void addOrUpdate(WalletConnectRequestLogEntry entry) {
    enqueue(entry);
  }

  void markApproved(int id, String resultHexOrTxHash) {
    final WalletConnectRequestLogEntry? existing = findById(id);
    if (existing == null) {
      return;
    }
    final int index = _entries.indexOf(existing);
    _entries[index] = existing.copyWith(
      status: WalletConnectRequestStatus.approved,
      result: resultHexOrTxHash,
      isDismissed: existing.isDismissed,
      txHash: resultHexOrTxHash,
    );
    notifyListeners();
  }

  void markRejected(int id, String errorMsg) {
    final WalletConnectRequestLogEntry? existing = findById(id);
    if (existing == null) {
      return;
    }
    final int index = _entries.indexOf(existing);
    _entries[index] = existing.copyWith(
      status: WalletConnectRequestStatus.rejected,
      error: errorMsg,
    );
    notifyListeners();
  }

  void remove(int id) {
    _entries.removeWhere((entry) => entry.request.requestId == id);
    notifyListeners();
  }

  WalletConnectRequestLogEntry? getFirstPending() => firstPendingLog;

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
