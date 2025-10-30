import 'package:flutter/foundation.dart';

class WalletConnectService extends ChangeNotifier {
  String _status = 'disconnected';

  String get status => _status;

  final List<String> activeSessions = [];

  Future<void> init() async {
    _status = 'ready';
    notifyListeners();
  }

  Future<void> pairUri(String uri) async {
    _status = 'pair requested';
    notifyListeners();
    _status = 'ready';
    notifyListeners();
  }
}
