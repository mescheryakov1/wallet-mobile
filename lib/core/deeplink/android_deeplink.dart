import 'dart:async';

import 'package:flutter/services.dart';

class DeeplinkAndroid {
  DeeplinkAndroid._();

  static const MethodChannel _channel = MethodChannel('deeplink');
  static final StreamController<String> _controller =
      StreamController<String>.broadcast();
  static bool _initialized = false;

  static Stream<String> get stream => _controller.stream;

  static Future<void> init() async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    _channel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'onLink' && call.arguments is String) {
        _controller.add(call.arguments as String);
      }
    });

    try {
      final String? initial = await _channel.invokeMethod<String>('getInitialLink');
      if (initial != null) {
        _controller.add(initial);
      }
    } on MissingPluginException {
      // The channel is not available on this platform; ignore.
    }
  }
}
