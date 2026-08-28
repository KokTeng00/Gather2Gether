import 'package:flutter_test/flutter_test.dart';
import 'package:gather2gether/core/validation/validators.dart';

void main() {
  group('Validators', () {
    test('requires meaningful values', () {
      expect(Validators.requiredText('  '), isNotNull);
      expect(
        Validators.requiredText('Hi', minLength: 3),
        'Use at least 3 characters.',
      );
      expect(Validators.requiredText(' Run ', minLength: 3), isNull);
      expect(Validators.requiredText('Community run'), isNull);
    });

    test('validates account inputs', () {
      expect(Validators.email('not-an-email'), isNotNull);
      expect(Validators.email('member@example.com'), isNull);
      expect(Validators.password('short'), isNotNull);
      expect(Validators.password('longpassword1'), isNull);
    });

    test('keeps participant limits within server bounds', () {
      expect(Validators.participantLimit('1'), isNotNull);
      expect(Validators.participantLimit('12'), isNull);
      expect(Validators.participantLimit('501'), isNotNull);
    });
  });
}
