import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'wallet_connect_service.dart';

class WcRequestApprovalPage extends StatefulWidget {
  const WcRequestApprovalPage({
    required this.service,
    super.key,
  });

  final WalletConnectService service;

  @override
  State<WcRequestApprovalPage> createState() => _WcRequestApprovalPageState();
}

class _WcRequestApprovalPageState extends State<WcRequestApprovalPage> {
  late final WalletConnectService _service;

  @override
  void initState() {
    super.initState();
    _service = widget.service
      ..addListener(_handleServiceUpdate);
  }

  @override
  void dispose() {
    _service.removeListener(_handleServiceUpdate);
    super.dispose();
  }

  void _handleServiceUpdate() {
    if (mounted) {
      setState(() {});
    }
  }

  PendingWcRequest? get _request => _service.pendingRequest;

  Future<void> _approve() async {
    try {
      await _service.approvePendingRequest();
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $error')),
      );
    }
  }

  Future<void> _reject() async {
    try {
      await _service.rejectPendingRequest();
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = _request;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Review WalletConnect request'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: request == null
            ? const Center(
                child: Text('Нет активных запросов для подтверждения.'),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Method: ${request.method}'),
                  const SizedBox(height: 12),
                  ..._buildRequestDetails(request),
                  const Spacer(),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _reject,
                          child: const Text('Reject'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _approve,
                          child: const Text('Approve'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }

  List<Widget> _buildRequestDetails(PendingWcRequest request) {
    switch (request.method) {
      case 'personal_sign':
        return _buildPersonalSignDetails(request.params);
      case 'eth_sendTransaction':
        return _buildEthSendTransactionDetails(request.params);
      default:
        return <Widget>[
          const Text('Parameters:'),
          const SizedBox(height: 8),
          Text('${request.params}'),
        ];
    }
  }

  List<Widget> _buildPersonalSignDetails(dynamic params) {
    final buffer = <Widget>[
      const Text('personal_sign request'),
      const SizedBox(height: 8),
    ];

    final messageHex = _extractFirstHexParam(params);
    if (messageHex != null) {
      buffer
        ..add(Text('Message (hex): $messageHex'))
        ..add(const SizedBox(height: 8));
      final decoded = _decodeHexToUtf8(messageHex);
      if (decoded != null) {
        buffer
          ..add(const Text('Message (utf8):'))
          ..add(const SizedBox(height: 4))
          ..add(Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade400),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              decoded,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ))
          ..add(const SizedBox(height: 8));
      }
    }

    buffer
      ..add(const Text('Raw params:'))
      ..add(const SizedBox(height: 4))
      ..add(Text('$params'));

    return buffer;
  }

  List<Widget> _buildEthSendTransactionDetails(dynamic params) {
    final buffer = <Widget>[
      const Text('eth_sendTransaction request'),
      const SizedBox(height: 8),
    ];

    Map<String, dynamic>? transaction;
    if (params is List && params.isNotEmpty && params.first is Map) {
      transaction = Map<String, dynamic>.from(params.first as Map);
    }

    if (transaction != null) {
      final entries = <String, dynamic>{
        'from': transaction['from'],
        'to': transaction['to'],
        'value': transaction['value'],
        'gas': transaction['gas'],
        'gasPrice': transaction['gasPrice'],
        'nonce': transaction['nonce'],
        'data': transaction['data'],
      };
      buffer
        ..addAll(entries.entries.map(
          (entry) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Text('${entry.key}: ${entry.value ?? '—'}'),
          ),
        ))
        ..add(const SizedBox(height: 12));
    }

    buffer
      ..add(const Text('Raw params:'))
      ..add(const SizedBox(height: 4))
      ..add(Text('$params'));

    return buffer;
  }

  String? _extractFirstHexParam(dynamic params) {
    if (params is List) {
      for (final param in params) {
        if (param is String && param.startsWith('0x')) {
          return param;
        }
      }
    }
    return null;
  }

  String? _decodeHexToUtf8(String hexString) {
    final cleaned = hexString.startsWith('0x')
        ? hexString.substring(2)
        : hexString;
    if (cleaned.isEmpty) {
      return '';
    }
    if (cleaned.length.isOdd) {
      return null;
    }

    final bytes = Uint8List(cleaned.length ~/ 2);
    for (int i = 0; i < cleaned.length; i += 2) {
      final segment = cleaned.substring(i, i + 2);
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
}
