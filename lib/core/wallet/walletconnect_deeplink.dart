import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

import '../../wallet_connect_manager.dart';
import '../deeplink/android_deeplink.dart' show DeeplinkAndroid;

Future<void> handleInitialUriAndStream() async {
  // Только Android. На Windows/macOS/Linux/Web выходим сразу.
  if (kIsWeb || !Platform.isAndroid) return;
  await DeeplinkAndroid.init();
  // Не блокируем запускающий код: подписка асинхронная, без await.
  DeeplinkAndroid.stream.listen((String link) {
    if (!link.startsWith('wc:')) {
      return;
    }

    try {
      WalletConnectManager.instance.pending.push(link);
    } catch (_) {
      // ignored: errors are handled by the service
    }
  });
}
