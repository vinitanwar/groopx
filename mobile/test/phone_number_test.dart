import 'package:flutter_test/flutter_test.dart';
import 'package:groopx/features/auth/data/phone_number.dart';

void main() {
  test('normalizes international numbers from different countries', () {
    expect(normalizeInternationalPhone('+91 98765 43210'), '+919876543210');
    expect(normalizeInternationalPhone('+1 (202) 555-0123'), '+12025550123');
    expect(normalizeInternationalPhone('+44 20 7946 0958'), '+442079460958');
    expect(normalizeInternationalPhone('0049 30 901820'), '+4930901820');
  });

  test('requires a valid international country code', () {
    expect(normalizeInternationalPhone('9876543210'), isNull);
    expect(normalizeInternationalPhone('+0123456789'), isNull);
    expect(normalizeInternationalPhone('+123'), isNull);
  });
}
