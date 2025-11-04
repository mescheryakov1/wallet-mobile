import 'dart:async';

import 'package:flutter/material.dart';

import 'wallet_connect_manager.dart';
import 'wallet_connect_models.dart';

class WalletConnectRequestListener extends StatefulWidget {
  const WalletConnectRequestListener({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  State<WalletConnectRequestListener> createState() =>
      _WalletConnectRequestListenerState();
}

class _WalletConnectRequestListenerState
    extends State<WalletConnectRequestListener> {
  final WalletConnectManager _manager = WalletConnectManager.instance;
  OverlayEntry? _bannerEntry;
  bool _isProcessingAction = false;

  @override
  void initState() {
    super.initState();
    _manager.requestQueue.addListener(_handleQueueUpdate);
    WidgetsBinding.instance.addPostFrameCallback((_) => _handleQueueUpdate());
  }

  @override
  void dispose() {
    _manager.requestQueue.removeListener(_handleQueueUpdate);
    _hideBanner();
    super.dispose();
  }

  void _handleQueueUpdate() {
    if (!mounted) {
      return;
    }
    final WalletConnectRequestLogEntry? pending =
        _manager.firstPendingLog;
    if (pending == null) {
      _hideBanner();
      _isProcessingAction = false;
      return;
    }

    _isProcessingAction = false;
    _showBanner(pending);
  }

  void _showBanner(WalletConnectRequestLogEntry entry) {
    final overlay = Overlay.of(context, rootOverlay: true);
    if (overlay == null) {
      return;
    }
    _hideBanner();
    _bannerEntry = OverlayEntry(
      builder: (BuildContext context) {
        return _WalletConnectRequestBanner(
          entry: entry,
          isProcessing: _isProcessingAction,
          onApprove: () => _approveRequest(entry),
          onReject: () => _rejectRequest(entry),
          onClose: () => _dismissRequest(entry),
        );
      },
    );
    overlay.insert(_bannerEntry!);
  }

  void _hideBanner() {
    _bannerEntry?.remove();
    _bannerEntry = null;
  }

  Future<void> _approveRequest(WalletConnectRequestLogEntry entry) async {
    if (_isProcessingAction) {
      return;
    }
    setState(() {
      _isProcessingAction = true;
    });
    _bannerEntry?.markNeedsBuild();
    try {
      await _manager.approveRequest(entry.request.requestId);
      _hideBanner();
    } catch (error) {
      if (!mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        SnackBar(content: Text('Failed to approve request: $error')),
      );
      setState(() {
        _isProcessingAction = false;
      });
      _bannerEntry?.markNeedsBuild();
    }
  }

  Future<void> _rejectRequest(WalletConnectRequestLogEntry entry) async {
    if (_isProcessingAction) {
      return;
    }
    setState(() {
      _isProcessingAction = true;
    });
    _bannerEntry?.markNeedsBuild();
    try {
      await _manager.rejectRequest(entry.request.requestId);
    } catch (error) {
      if (!mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(
        SnackBar(content: Text('Failed to reject request: $error')),
      );
      setState(() {
        _isProcessingAction = false;
      });
      _bannerEntry?.markNeedsBuild();
      return;
    } finally {
      if (mounted) {
        _hideBanner();
      }
    }
  }

  void _dismissRequest(WalletConnectRequestLogEntry entry) {
    setState(() {
      _isProcessingAction = false;
    });
    _manager.dismissRequest(entry.request.requestId);
    _hideBanner();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class _WalletConnectRequestBanner extends StatelessWidget {
  const _WalletConnectRequestBanner({
    required this.entry,
    required this.isProcessing,
    required this.onApprove,
    required this.onReject,
    required this.onClose,
  });

  final WalletConnectRequestLogEntry entry;
  final bool isProcessing;
  final Future<void> Function() onApprove;
  final Future<void> Function() onReject;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final method = entry.request.method;
    final bool isSessionProposal = method == 'session_proposal';
    final String chainLabel = isSessionProposal
        ? _sessionChainLabel(entry.request)
        : (entry.request.chainId ?? 'unknown chain');
    final subtitle = '$method • $chainLabel';
    final List<Widget> details = _buildDetails(theme);
    final bool isPending =
        entry.status == WalletConnectRequestStatus.pending;

    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Material(
            elevation: 6,
            borderRadius: BorderRadius.circular(12),
            color: theme.colorScheme.surface,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(16),
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
                                'WalletConnect request',
                                style: theme.textTheme.titleMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 6),
                              Text(subtitle, style: theme.textTheme.bodyMedium),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: isProcessing ? null : onClose,
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...details,
                    if (details.isNotEmpty) const SizedBox(height: 12),
                    if (isProcessing)
                      const Align(
                        alignment: Alignment.center,
                        child: Padding(
                          padding: EdgeInsets.only(bottom: 8),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: isProcessing || !isPending
                              ? null
                              : () {
                                  unawaited(onReject());
                                },
                          child: const Text('Reject'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: isProcessing || !isPending
                              ? null
                              : () {
                                  unawaited(onApprove());
                                },
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

  List<Widget> _buildDetails(ThemeData theme) {
    switch (entry.request.method) {
      case 'personal_sign':
        return _buildPersonalSignDetails(theme);
      case 'eth_sendTransaction':
        return _buildTransactionDetails(theme);
      case 'session_proposal':
        return _buildSessionProposalDetails(theme);
      default:
        return <Widget>[
          Text(
            'Params: ${entry.request.params}',
            style: theme.textTheme.bodySmall,
          ),
        ];
    }
  }

  List<Widget> _buildPersonalSignDetails(ThemeData theme) {
    final List<dynamic> params = _asList(entry.request.params);
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

  List<Widget> _buildTransactionDetails(ThemeData theme) {
    final Map<String, dynamic> tx = _asTx(entry.request.params);
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

  List<Widget> _buildSessionProposalDetails(ThemeData theme) {
    final Map<String, dynamic> data = _asMap(entry.request.params);
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

  List<dynamic> _asList(dynamic params) {
    if (params is List) {
      return params;
    }
    return <dynamic>[];
  }

  Map<String, dynamic> _asMap(dynamic params) {
    if (params is Map<String, dynamic>) {
      return params;
    }
    if (params is Map) {
      return params.map((key, dynamic value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{};
  }

  String _sessionChainLabel(WalletConnectPendingRequest request) {
    final Map<String, dynamic> data = _asMap(request.params);
    final List<dynamic>? chains = data['chains'] as List<dynamic>?;
    if (chains == null || chains.isEmpty) {
      return 'session';
    }
    return chains.join(', ');
  }

  String _formatList(List<dynamic>? values) {
    if (values == null || values.isEmpty) {
      return '—';
    }
    return values.map((dynamic value) => value.toString()).join(', ');
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
