import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

class WalletConnectLogger {
  WalletConnectLogger._();

  static final WalletConnectLogger instance = WalletConnectLogger._();

  IOSink? _sink;
  String? _logFilePath;
  bool _initialized = false;

  bool get hasFileSink => _sink != null;
  String? get logFilePath => _logFilePath;

  Future<void> initialize({String? explicitPath}) async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    final bool shouldWriteToFile = Platform.isWindows;
    if (!shouldWriteToFile) {
      return;
    }

    final String? envPath = _firstNonEmpty([
      const String.fromEnvironment('WC_LOG_PATH', defaultValue: ''),
      Platform.environment['WC_LOG_PATH'] ?? '',
      explicitPath ?? '',
    ]);

    final String logPath = envPath?.trim().isNotEmpty == true
        ? envPath!.trim()
        : _defaultLogPath();

    try {
      final File logFile = File(logPath);
      await logFile.parent.create(recursive: true);
      _sink = logFile.openWrite(mode: FileMode.append);
      _logFilePath = logFile.path;
      _sink!.writeln('--- WalletConnect diagnostics started at '
          '${DateTime.now().toIso8601String()} ---');
    } catch (error) {
      debugPrint('WC:failed to open log file $logPath: $error');
    }
  }

  void log(String message, {bool isNetwork = false}) {
    final String timestamp = DateTime.now().toIso8601String();
    final String prefix = isNetwork ? 'NET' : 'WC';
    final String line = '[$prefix][$timestamp] $message';
    debugPrint(line);
    _sink?.writeln(line);
  }

  void logNetwork(String message) => log(message, isNetwork: true);

  Future<void> dispose() async {
    try {
      await _sink?.flush();
      await _sink?.close();
    } catch (_) {}
    _sink = null;
  }

  String _defaultLogPath() {
    final String baseDir = Platform.environment['TEMP'] ??
        Platform.environment['TMP'] ??
        Directory.systemTemp.path;
    return '${baseDir}\\wallet_mobile\\walletconnect-windows.log';
  }

  String? _firstNonEmpty(List<String> candidates) {
    for (final String candidate in candidates) {
      if (candidate.trim().isNotEmpty) {
        return candidate.trim();
      }
    }
    return null;
  }
}
