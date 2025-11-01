import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:web3dart/web3dart.dart';

import 'wallet_connect_manager.dart';
import 'wallet_connect_models.dart';

class WcRequestApprovalPage extends StatefulWidget {
  const WcRequestApprovalPage({
    required this.requestId,
    WalletConnectManager? manager,
    super.key,
  }) : manager = manager ?? WalletConnectManager.instance;

  final int requestId;
  final WalletConnectManager manager;

  @override
  State<WcRequestApprovalPage> createState() => _WcRequestApprovalPageState();
}

class _WcRequestApprovalPageState extends State<WcRequestApprovalPage> {
  late final WalletConnectManager _manager;
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _manager = widget.manager;
    _manager.addListener(_handleServiceUpdate);
    _manager.requestQueue.addListener(_handleServiceUpdate);
  }

  @override
  void dispose() {
    _manager.requestQueue.removeListener(_handleServiceUpdate);
    _manager.removeListener(_handleServiceUpdate);
    super.dispose();
  }

  void _handleServiceUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  WalletConnectPendingRequest? get _pendingRequest {
    final pending = _manager.pendingRequest;
    if (pending != null && pending.requestId == widget.requestId) {
      return pending;
    }
    return null;
  }

  WalletConnectRequestLogEntry? get _logEntry =>
      _manager.requestQueue.findById(widget.requestId);

  Future<void> _approve() async {
    if (_isProcessing) {
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      await _manager.approveRequest(widget.requestId);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request approved')),
      );
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _reject() async {
    if (_isProcessing) {
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      await _manager.rejectRequest(widget.requestId);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request rejected')),
      );
      Navigator.of(context).pop(false);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = _logEntry;
    final request = _pendingRequest ?? entry?.request;
    return Scaffold(
      appBar: AppBar(
        title: const Text('WalletConnect request'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: request == null
            ? const Center(
                child: Text('No pending requests to review.'),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            request.method,
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          if (entry != null)
                            Text(
                              'Status: ${entry.status.name}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w500),
                            ),
                          const SizedBox(height: 12),
                          ..._buildRequestDetails(request),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _isProcessing ||
                                  entry?.status !=
                                      WalletConnectRequestStatus.pending
                              ? null
                              : _reject,
                          child: const Text('Reject'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _isProcessing ||
                                  entry?.status !=
                                      WalletConnectRequestStatus.pending
                              ? null
                              : _approve,
                          child: _isProcessing
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Approve'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  List<Widget> _buildRequestDetails(WalletConnectPendingRequest request) {
    switch (request.method) {
      case 'personal_sign':
        return _buildPersonalSignDetails(request);
      case 'eth_sendTransaction':
        return _buildEthSendTransactionDetails(request);
      default:
        return <Widget>[
          const Text('Parameters:'),
          const SizedBox(height: 8),
          Text('${request.params}'),
        ];
    }
  }

  List<Widget> _buildPersonalSignDetails(WalletConnectPendingRequest request) {
    final params = _asList(request.params);
    final address = _resolveAddress(params);
    final messageRaw = _resolveMessage(params);
    final decodedMessage =
        messageRaw != null ? _decodeHexToUtf8(messageRaw) : null;

    return <Widget>[
      if (request.chainId != null) ...[
        const Text('Chain'),
        const SizedBox(height: 4),
        SelectableText(request.chainId!),
        const SizedBox(height: 12),
      ],
      if (address != null) ...[
        const Text('Address'),
        const SizedBox(height: 4),
        SelectableText(address),
        const SizedBox(height: 12),
      ],
      if (decodedMessage != null && decodedMessage.isNotEmpty) ...[
        const Text('Message'),
        const SizedBox(height: 4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade400),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SelectableText(
            decodedMessage,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
        ),
        const SizedBox(height: 12),
      ],
      if (messageRaw != null) ...[
        const Text('Message (raw)'),
        const SizedBox(height: 4),
        SelectableText(messageRaw),
        const SizedBox(height: 12),
      ],
      const Text('Raw parameters'),
      const SizedBox(height: 4),
      SelectableText(_formatParams(params)),
    ];
  }

  List<Widget> _buildEthSendTransactionDetails(
    WalletConnectPendingRequest request,
  ) {
    final params = _asList(request.params);
    Map<String, dynamic>? transaction;
    if (params.isNotEmpty && params.first is Map) {
      transaction = Map<String, dynamic>.from(params.first as Map);
    }

    final rows = <Widget>[];
    if (request.chainId != null) {
      rows
        ..add(_detailRow('Chain', request.chainId))
        ..add(const SizedBox(height: 8));
    }
    if (transaction != null) {
      rows.addAll([
        _detailRow('From', transaction['from']),
        _detailRow('To', transaction['to']),
        _detailRow('Value', _formatEthValue(transaction['value'])),
        _detailRow('Gas limit', _formatQuantity(transaction['gas'])),
        _detailRow('Gas price', _formatWei(transaction['gasPrice'])),
        _detailRow('Max fee per gas', _formatWei(transaction['maxFeePerGas'])),
        _detailRow(
          'Max priority fee',
          _formatWei(transaction['maxPriorityFeePerGas']),
        ),
        _detailRow('Nonce', _formatQuantity(transaction['nonce'])),
        _detailRow('Data', transaction['data']),
      ]);
    }

    rows
      ..add(const SizedBox(height: 12))
      ..add(const Text('Raw parameters'))
      ..add(const SizedBox(height: 4))
      ..add(SelectableText(_formatParams(params)));

    return rows;
  }

  List<dynamic> _asList(dynamic value) {
    if (value == null) {
      return const [];
    }
    if (value is List) {
      return List<dynamic>.from(value);
    }
    return <dynamic>[value];
  }

  String? _resolveAddress(List<dynamic> params) {
    if (params.length >= 2) {
      final first = params[0];
      final second = params[1];
      if (first is String && _looksLikeAddress(first)) {
        return first;
      }
      if (second is String && _looksLikeAddress(second)) {
        return second;
      }
    }
    for (final param in params) {
      if (param is String && _looksLikeAddress(param)) {
        return param;
      }
    }
    return null;
  }

  String? _resolveMessage(List<dynamic> params) {
    if (params.isEmpty) {
      return null;
    }
    for (final param in params) {
      if (param is String && !_looksLikeAddress(param)) {
        return param;
      }
    }
    final fallback = params.firstWhere(
      (value) => value is String,
      orElse: () => null,
    );
    return fallback is String ? fallback : null;
  }

  String? _decodeHexToUtf8(String message) {
    final hexString = message.startsWith('0x')
        ? message.substring(2)
        : message;
    if (hexString.isEmpty) {
      return '';
    }
    if (hexString.length.isOdd) {
      return null;
    }

    final bytes = Uint8List(hexString.length ~/ 2);
    for (int i = 0; i < hexString.length; i += 2) {
      final segment = hexString.substring(i, i + 2);
      final value = int.tryParse(segment, radix: 16);
      if (value == null) {
        return null;
      }
      bytes[i ~/ 2] = value;
    }

    try {
      return utf8.decode(bytes, allowMalformed: true);
    } catch (_) {
      return null;
    }
  }

  Widget _detailRow(String label, Object? value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SelectableText(value?.toString() ?? '—'),
          ),
        ],
      ),
    );
  }

  String? _formatEthValue(Object? value) {
    final quantity = _parseQuantity(value);
    if (quantity == null) {
      return value?.toString();
    }
    final amount = EtherAmount.inWei(quantity);
    final eth = amount.getValueInUnit(EtherUnit.ether);
    return '${eth.toStringAsFixed(6)} ETH';
  }

  String? _formatWei(Object? value) {
    final quantity = _parseQuantity(value);
    if (quantity == null) {
      return value?.toString();
    }
    final gwei = EtherAmount.inWei(quantity).getValueInUnit(EtherUnit.gwei);
    return '${gwei.toStringAsFixed(2)} Gwei';
  }

  String? _formatQuantity(Object? value) {
    final quantity = _parseQuantity(value);
    return quantity?.toString() ?? value?.toString();
  }

  BigInt? _parseQuantity(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is BigInt) {
      return value;
    }
    if (value is int) {
      return BigInt.from(value);
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        return BigInt.zero;
      }
      if (trimmed.startsWith('0x') || trimmed.startsWith('0X')) {
        return BigInt.parse(trimmed.substring(2), radix: 16);
      }
      return BigInt.tryParse(trimmed);
    }
    return null;
  }

  bool _looksLikeAddress(String value) {
    return value.length == 42 && value.startsWith('0x');
  }

  String _formatParams(List<dynamic> params) {
    try {
      return const JsonEncoder.withIndent('  ').convert(params);
    } catch (_) {
      return params.toString();
    }
  }
}
