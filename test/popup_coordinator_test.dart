import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:wallet_mobile/core/navigation/navigator_key.dart';
import 'package:wallet_mobile/core/ui/popup_coordinator.dart';

void main() {
  setUp(() {
    PopupCoordinator.I.init();
    PopupCoordinator.I.debugReset();
  });

  testWidgets(
    'delays popup queue while paused and replaces outdated items when resumed',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: rootNavigatorKey,
          home: const Scaffold(body: Text('Home')),
        ),
      );

      PopupCoordinator.I.didChangeAppLifecycleState(AppLifecycleState.paused);

      bool firstShown = false;
      bool secondShown = false;

      PopupCoordinator.I.replaceWith((BuildContext context) {
        firstShown = true;
        return AlertDialog(
          title: const Text('First'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      });

      PopupCoordinator.I.replaceWith((BuildContext context) {
        secondShown = true;
        return AlertDialog(
          title: const Text('Second'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      });

      await tester.pump();

      expect(firstShown, isFalse);
      expect(secondShown, isFalse);
      expect(find.byType(AlertDialog), findsNothing);

      PopupCoordinator.I.didChangeAppLifecycleState(AppLifecycleState.resumed);

      await tester.pumpAndSettle();

      expect(firstShown, isFalse);
      expect(secondShown, isTrue);
      expect(find.text('Second'), findsOneWidget);

      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    },
  );

  testWidgets(
    'treats inactive Windows lifecycle as resumable without overdraining queue',
    (WidgetTester tester) async {
      PopupCoordinator.I.debugReset(isWindowsOverride: true);

      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: rootNavigatorKey,
          home: const Scaffold(body: Text('Home')),
        ),
      );

      PopupCoordinator.I.didChangeAppLifecycleState(AppLifecycleState.inactive);

      bool firstShown = false;
      bool secondShown = false;

      PopupCoordinator.I.replaceWith((BuildContext context) {
        firstShown = true;
        return AlertDialog(
          title: const Text('Windows First'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Next'),
            ),
          ],
        );
      });

      await tester.pumpAndSettle();
      expect(firstShown, isTrue);
      expect(find.text('Windows First'), findsOneWidget);

      PopupCoordinator.I.replaceWith((BuildContext context) {
        secondShown = true;
        return AlertDialog(
          title: const Text('Windows Second'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      });

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      expect(secondShown, isTrue);
      expect(find.text('Windows Second'), findsOneWidget);

      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
}
