import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_mobile/core/navigation/navigator_key.dart';
import 'package:wallet_mobile/core/ui/popup_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    PopupCoordinator.I.init();
  });

  testWidgets('drains queued popup after navigator becomes available',
      (tester) async {
    var shown = false;

    PopupCoordinator.I.enqueue((context) {
      shown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context, rootNavigator: true).pop();
      });
      return const AlertDialog(title: Text('Queued popup'));
    });

    await tester.pumpWidget(
      const MaterialApp(
        navigatorKey: rootNavigatorKey,
        home: SizedBox.shrink(),
      ),
    );

    await tester.pump();

    expect(shown, isTrue);
    expect(find.text('Queued popup'), findsOneWidget);

    await tester.pumpAndSettle();
  });

  testWidgets('resumes draining after lifecycle resumes', (tester) async {
    PopupCoordinator.I.didChangeAppLifecycleState(AppLifecycleState.inactive);

    PopupCoordinator.I.enqueue((context) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context, rootNavigator: true).pop();
      });
      return const AlertDialog(title: Text('Lifecycle popup'));
    });

    await tester.pumpWidget(
      const MaterialApp(
        navigatorKey: rootNavigatorKey,
        home: SizedBox.shrink(),
      ),
    );

    await tester.pump();

    expect(find.text('Lifecycle popup'), findsNothing);

    PopupCoordinator.I.didChangeAppLifecycleState(AppLifecycleState.resumed);

    await tester.pump();
    await tester.pump();

    expect(find.text('Lifecycle popup'), findsOneWidget);

    await tester.pumpAndSettle();
  });
}
