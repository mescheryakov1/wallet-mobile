import 'package:flutter/material.dart';

import 'wallet_connect_models.dart';

class WalletConnectRequestPopup extends StatefulWidget {
  const WalletConnectRequestPopup({
    required this.entry,
    required this.onApprove,
    required this.onReject,
    required this.onDismiss,
    super.key,
  });

  final WalletConnectRequestLogEntry entry;
  final Future<void> Function() onApprove;
  final Future<void> Function() onReject;
  final VoidCallback onDismiss;

  @override
  State<WalletConnectRequestPopup> createState() =>
      _WalletConnectRequestPopupState();
}

class _WalletConnectRequestPopupState
    extends State<WalletConnectRequestPopup> {
  bool _isProcessing = false;

  Future<void> _handleApprove() async {
    if (_isProcessing) {
      return;
    }
    setState(() {
      _isProcessing = true;
    });
    await widget.onApprove();
    if (mounted) {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _handleReject() async {
    if (_isProcessing) {
      return;
    }
    setState(() {
      _isProcessing = true;
    });
    await widget.onReject();
    if (mounted) {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final WalletConnectPendingRequest request = widget.entry.request;
    final String method = request.method;
    final bool isSessionProposal = method == 'session_proposal';
    final String chainLabel = isSessionProposal
        ? _sessionChainLabel(request)
        : (request.chainId ?? 'unknown chain');
    final ThemeData theme = Theme.of(context);
    final bool isPending =
        widget.entry.status == WalletConnectRequestStatus.pending;

    return Positioned.fill(
      child: Material(
        color: Colors.black54,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 6,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _titleForMethod(method),
                                style: theme.textTheme.titleLarge,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '$method • $chainLabel',
                                style: theme.textTheme.bodyMedium,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          tooltip: 'Close',
                          onPressed: _isProcessing ? null : widget.onDismiss,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    ..._buildDetails(theme, request),
                    const SizedBox(height: 16),
                    if (_isProcessing)
                      const Padding(
                        padding: EdgeInsets.only(bottom: 16),
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed:
                              _isProcessing || !isPending ? null : _handleReject,
                          child: const Text('Reject'),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed:
                              _isProcessing || !isPending ? null : _handleApprove,
                          child: const Text('Approve'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _titleForMethod(String method) {
    switch (method) {
      case 'eth_sendTransaction':
        return 'Transaction request';
      case 'personal_sign':
        return 'Signature request';
      case 'session_proposal':
        return 'Connection request';
      default:
        return method;
    }
  }

  List<Widget> _buildDetails(
    ThemeData theme,
    WalletConnectPendingRequest request,
  ) {
    switch (request.method) {
      case 'personal_sign':
        return _buildPersonalSignDetails(theme, request);
      case 'eth_sendTransaction':
        return _buildTransactionDetails(theme, request);
      case 'session_proposal':
        return _buildSessionProposalDetails(theme, request);
      default:
        return <Widget>[
          Text(
            'Params: ${request.params}',
            style: theme.textTheme.bodySmall,
          ),
        ];
    }
  }

  List<Widget> _buildPersonalSignDetails(
    ThemeData theme,
    WalletConnectPendingRequest request,
  ) {
    final List<dynamic> params = _asList(request.params);
    final String? address = params.length >= 2 ? params[1] as String? : null;
    final String? messageHex = _resolveMessage(params);
    final String? decoded =
        messageHex != null ? _decodeHexToUtf8(messageHex) : null;
    final String messageDisplay =
        decoded?.trim().isNotEmpty == true ? decoded! : (messageHex ?? '<unknown>');

    return <Widget>[
      Text('From: ${address ?? 'unknown'}', style: theme.textTheme.bodySmall),
      const SizedBox(height: 4),
      Text('Message: $messageDisplay', style: theme.textTheme.bodySmall),
    ];
  }

  List<Widget> _buildTransactionDetails(
    ThemeData theme,
    WalletConnectPendingRequest request,
  ) {
    final Map<String, dynamic> tx = _asTx(request.params);
    final String from = tx['from']?.toString() ?? 'unknown';
    final String to = tx['to']?.toString() ?? 'unknown';
    final String value = tx['value']?.toString() ?? '0x0';
    final String gas = tx['gas']?.toString() ?? tx['gasLimit']?.toString() ?? '-';
    final String gasPrice =
        tx['gasPrice']?.toString() ?? tx['maxFeePerGas']?.toString() ?? '-';
    final String nonce = tx['nonce']?.toString() ?? '-';

    return <Widget>[
      Text('From: $from', style: theme.textTheme.bodySmall),
      const SizedBox(height: 4),
      Text('To: $to', style: theme.textTheme.bodySmall),
      const SizedBox(height: 4),
      Text('Value: $value', style: theme.textTheme.bodySmall),
      const SizedBox(height: 4),
      Text('Gas: $gas', style: theme.textTheme.bodySmall),
      const SizedBox(height: 4),
      Text('Gas price: $gasPrice', style: theme.textTheme.bodySmall),
      const SizedBox(height: 4),
      Text('Nonce: $nonce', style: theme.textTheme.bodySmall),
    ];
  }

  List<Widget> _buildSessionProposalDetails(
    ThemeData theme,
    WalletConnectPendingRequest request,
  ) {
    final Map<String, dynamic> data = _asMap(request.params);
    final Map<String, dynamic>? metadata =
        data['metadata'] as Map<String, dynamic>?;
    final List<dynamic>? chains = data['chains'] as List<dynamic>?;
    final List<dynamic>? methods = data['methods'] as List<dynamic>?;
    final List<dynamic>? events = data['events'] as List<dynamic>?;
    final List<dynamic>? accounts = data['accounts'] as List<dynamic>?;

    final List<Widget> rows = <Widget>[];
    if (metadata != null) {
      final String name = metadata['name']?.toString() ?? 'Unknown dApp';
      rows.add(Text('dApp: $name', style: theme.textTheme.bodySmall));
      final String? url = metadata['url']?.toString();
      if (url != null && url.isNotEmpty) {
        rows
          ..add(const SizedBox(height: 4))
          ..add(Text('URL: $url', style: theme.textTheme.bodySmall));
      }
      final String? description = metadata['description']?.toString();
      if (description != null && description.isNotEmpty) {
        rows
          ..add(const SizedBox(height: 4))
          ..add(Text(description, style: theme.textTheme.bodySmall));
      }
    }

    rows
      ..add(const SizedBox(height: 4))
      ..add(Text('Chains: ${_formatList(chains)}',
          style: theme.textTheme.bodySmall))
      ..add(const SizedBox(height: 4))
      ..add(Text('Methods: ${_formatList(methods)}',
          style: theme.textTheme.bodySmall))
      ..add(const SizedBox(height: 4))
      ..add(Text('Events: ${_formatList(events)}',
          style: theme.textTheme.bodySmall));

    if (accounts != null && accounts.isNotEmpty) {
      rows
        ..add(const SizedBox(height: 4))
        ..add(Text('Accounts: ${_formatList(accounts)}',
            style: theme.textTheme.bodySmall));
    }

    return rows;
  }

  String _sessionChainLabel(WalletConnectPendingRequest request) {
    final Map<String, dynamic> data = _asMap(request.params);
    final List<dynamic>? chains = data['chains'] as List<dynamic>?;
    if (chains == null || chains.isEmpty) {
      return 'session';
    }
    return chains.join(', ');
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, dynamic val) => MapEntry(key.toString(), val));
    }
    return <String, dynamic>{};
  }

  String _formatList(List<dynamic>? values) {
    if (values == null || values.isEmpty) {
      return '—';
    }
    return values.map((dynamic value) => value.toString()).join(', ');
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
    if (first is Map) {
      return Map<String, dynamic>.from(first as Map);
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
        final int byte = int.parse(cleaned.substring(i, i + 2), radix: 16);
        bytes.add(byte);
      }
      return String.fromCharCodes(bytes);
    } catch (_) {
      return null;
    }
  }
}
