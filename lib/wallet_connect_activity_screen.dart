import 'package:flutter/material.dart';

import 'wallet_connect_manager.dart';
import 'wallet_connect_models.dart';
import 'wc_request_approval_page.dart';

class WalletConnectActivityScreen extends StatelessWidget {
  const WalletConnectActivityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final WalletConnectManager manager = WalletConnectManager.instance;
    return Scaffold(
      appBar: AppBar(
        title: const Text('WalletConnect activity'),
      ),
      body: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[manager, manager.requestQueue]),
        builder: (BuildContext context, Widget? _) {
          final List<WalletConnectRequestLogEntry> entries =
              manager.activityLog.reversed.toList();
          if (entries.isEmpty) {
            return const Center(
              child: Text('No WalletConnect requests yet.'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemBuilder: (BuildContext context, int index) {
              final WalletConnectRequestLogEntry entry = entries[index];
              return _ActivityTile(entry: entry);
            },
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemCount: entries.length,
          );
        },
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.entry});

  final WalletConnectRequestLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final WalletConnectPendingRequest request = entry.request;
    final ThemeData theme = Theme.of(context);
    final Color statusColor;
    switch (entry.status) {
      case WalletConnectRequestStatus.pending:
        statusColor = theme.colorScheme.primary;
        break;
      case WalletConnectRequestStatus.broadcasting:
        statusColor = theme.colorScheme.primary;
        break;
      case WalletConnectRequestStatus.approved:
      case WalletConnectRequestStatus.done:
        statusColor = Colors.green;
        break;
      case WalletConnectRequestStatus.error:
      case WalletConnectRequestStatus.rejected:
        statusColor = Colors.red;
        break;
    }
    final bool isPending = entry.status == WalletConnectRequestStatus.pending;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Text(
                  request.method,
                  style: theme.textTheme.titleMedium,
                ),
                Text(
                  entry.status.name,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: statusColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text('Chain: ${request.chainId ?? 'unknown'}'),
            const SizedBox(height: 4),
            if (request.method == 'personal_sign')
              Text(_buildPersonalSignSummary(request))
            else if (request.method == 'eth_sendTransaction')
              Text(_buildTransactionSummary(request))
            else
              Text('${request.params}'),
            const SizedBox(height: 8),
            Text(
              'Updated: ${entry.timestamp.toLocal()}',
              style: theme.textTheme.bodySmall,
            ),
            if (entry.result != null) ...[
              const SizedBox(height: 4),
              Text('Result: ${entry.result}'),
            ],
            if (entry.txHash != null) ...[
              const SizedBox(height: 4),
              Text('Tx hash: ${entry.txHash}'),
            ],
            if (entry.error != null) ...[
              const SizedBox(height: 4),
              Text('Error: ${entry.error}'),
            ],
            if (isPending) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => WcRequestApprovalPage(
                          requestId: request.requestId,
                          manager: WalletConnectManager.instance,
                        ),
                        fullscreenDialog: true,
                      ),
                    );
                  },
                  child: const Text('Review'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _buildPersonalSignSummary(WalletConnectPendingRequest request) {
    final List<dynamic> params = _asList(request.params);
    final String? messageHex = _resolveMessage(params);
    if (messageHex == null) {
      return 'Message: <unknown>';
    }
    final String? decoded = _decodeHexToUtf8(messageHex);
    if (decoded == null || decoded.isEmpty) {
      return 'Message: $messageHex';
    }
    return 'Message: $decoded';
  }

  String _buildTransactionSummary(WalletConnectPendingRequest request) {
    final Map<String, dynamic> tx = _asTx(request.params);
    final String to = tx['to']?.toString() ?? 'unknown';
    final String value = tx['value']?.toString() ?? '0x0';
    return 'To: $to\nValue: $value';
  }

  List<dynamic> _asList(dynamic params) {
    if (params is List) {
      return params;
    }
    return <dynamic>[];
  }

  Map<String, dynamic> _asTx(dynamic params) {
    final List<dynamic> list = _asList(params);
    if (list.isEmpty) {
      return <String, dynamic>{};
    }
    final dynamic first = list.first;
    if (first is Map<String, dynamic>) {
      return first;
    }
    return <String, dynamic>{};
  }

  String? _resolveMessage(List<dynamic> params) {
    for (final dynamic value in params) {
      if (value is String && value.startsWith('0x')) {
        return value;
      }
    }
    return null;
  }

  String? _decodeHexToUtf8(String hex) {
    try {
      final String cleaned = hex.startsWith('0x') ? hex.substring(2) : hex;
      final List<int> bytes = <int>[];
      for (int i = 0; i < cleaned.length; i += 2) {
        bytes.add(int.parse(cleaned.substring(i, i + 2), radix: 16));
      }
      return String.fromCharCodes(bytes);
    } catch (_) {
      return null;
    }
  }
}
