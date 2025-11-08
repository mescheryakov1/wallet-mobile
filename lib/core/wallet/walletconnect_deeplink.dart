import '../../wallet_connect_service.dart';
import '../deeplink/android_deeplink.dart' show DeeplinkAndroid;

Future<void> handleInitialUriAndStream(WalletConnectService svc) async {
  await DeeplinkAndroid.init();

  DeeplinkAndroid.stream.listen((String link) async {
    if (!link.startsWith('wc:')) {
      return;
    }

    try {
      await svc.connectFromUri(link);
    } catch (_) {
      // ignored: errors are handled by the service
    }
  });
}
