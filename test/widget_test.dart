import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wallet_mobile/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('renders empty wallet state', (tester) async {
    await tester.pumpWidget(const WalletApp());
    await tester.pumpAndSettle();

    expect(find.text('Ethereum Wallet'), findsOneWidget);
    expect(find.text('Кошелёк не создан'), findsOneWidget);
  });
}
