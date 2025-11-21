import 'package:flutter/widgets.dart';

/// Legacy wrapper kept for backward compatibility. WalletConnect popups are
/// now managed globally via the root navigator, so this widget simply returns
/// its [child] without additional listeners.
class WalletConnectRequestListener extends StatelessWidget {
  const WalletConnectRequestListener({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}
