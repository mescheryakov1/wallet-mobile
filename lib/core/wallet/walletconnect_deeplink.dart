import 'dart:async';

import 'package:uni_links/uni_links.dart';

import '../../wallet_connect_service.dart';

Future<void> handleInitialUriAndStream(WalletConnectService svc) async {
  try {
    final Uri? initial = await getInitialUri();
    if (initial != null && initial.scheme == 'wc') {
      await svc.connectFromUri(initial.toString());
    }
  } catch (_) {
    // ignored: initial uri retrieval errors are non-fatal
  }

  uriLinkStream.listen((Uri? uri) async {
    if (uri != null && uri.scheme == 'wc') {
      try {
        await svc.connectFromUri(uri.toString());
      } catch (_) {
        // ignored: errors are handled by the service
      }
    }
  }, onError: (_) {
    // ignored: stream errors are non-fatal
  });
}
