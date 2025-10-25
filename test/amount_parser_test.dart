import 'package:flutter_test/flutter_test.dart';
import 'package:wallet_mobile/main.dart';

void main() {
  group('AmountParser', () {
    test('parses whole number ETH values', () {
      expect(
        AmountParser.parseEthToWei('1'),
        BigInt.parse('1000000000000000000'),
      );
    });

    test('parses fractional ETH values up to 18 decimals', () {
      expect(
        AmountParser.parseEthToWei('0.123456789012345678'),
        BigInt.parse('123456789012345678'),
      );
    });

    test('parses fractional ETH values with fewer decimals', () {
      expect(
        AmountParser.parseEthToWei('0.1'),
        BigInt.parse('100000000000000000'),
      );
    });

    test('trims whitespace and rejects invalid values', () {
      expect(
        AmountParser.parseEthToWei(' 2 '),
        BigInt.parse('2000000000000000000'),
      );

      expect(
        () => AmountParser.parseEthToWei('invalid'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
