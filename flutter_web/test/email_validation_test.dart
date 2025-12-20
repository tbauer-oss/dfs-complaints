import 'package:flutter_test/flutter_test.dart';
import 'package:dfs_customer_complaint/utils/email_validation.dart';

void main() {
  group('email validation', () {
    test('accepts valid addresses with normalization', () {
      expect(isValidEmail('markus.schmidtke@eve-rotary.com'), isTrue);
      expect(isValidEmail('Markus.Schmidtke@eve-rotary.com'), isTrue);
      expect(isValidEmail(' markus.schmidtke@eve-rotary.com '), isTrue);
      expect(isValidEmail('markus.schmidtke@eve-rotary.com\n'), isTrue);
    });

    test('rejects invalid addresses', () {
      expect(isValidEmail('markus.schmidtke@eve-rotary'), isFalse);
      expect(isValidEmail('markus@eve-rotary..com'), isFalse);
    });
  });
}
