import 'package:flutter_test/flutter_test.dart';

import 'package:corex_mobile/utils/display_text.dart';

void main() {
  group('titleCaseLabel', () {
    test('raises storage-form values into label case', () {
      expect(titleCaseLabel('active'), 'Active');
      expect(titleCaseLabel('pending'), 'Pending');
      expect(titleCaseLabel('owner'), 'Owner');
    });

    test('turns separators into spaces and caps each word', () {
      expect(titleCaseLabel('under_offer'), 'Under Offer');
      expect(titleCaseLabel('not_started'), 'Not Started');
      expect(titleCaseLabel('sole-mandate'), 'Sole Mandate');
    });

    test('leaves acronyms the server already capitalised alone', () {
      // A lowercase-then-capitalise pass would turn these into Fica and Otp.
      expect(titleCaseLabel('FICA'), 'FICA');
      expect(titleCaseLabel('OTP signed'), 'OTP Signed');
      expect(titleCaseLabel('P24'), 'P24');
    });

    test('is a no-op on values that are already correct', () {
      expect(titleCaseLabel('Active'), 'Active');
      expect(titleCaseLabel('Under Offer'), 'Under Offer');
    });

    test('collapses stray whitespace and repeated separators', () {
      expect(titleCaseLabel('  under__offer  '), 'Under Offer');
      expect(titleCaseLabel('not  started'), 'Not Started');
    });

    test('falls back for null and blank input', () {
      expect(titleCaseLabel(null), '');
      expect(titleCaseLabel(''), '');
      expect(titleCaseLabel('   '), '');
      expect(titleCaseLabel(null, fallback: 'Active'), 'Active');
      expect(titleCaseLabel('_', fallback: 'N/A'), 'N/A');
    });
  });

  group('sentenceCaseLabel', () {
    test('raises only the first word', () {
      expect(sentenceCaseLabel('not_started'), 'Not started');
      expect(sentenceCaseLabel('due_this_week'), 'Due this week');
    });

    test('keeps acronyms and honours the fallback', () {
      expect(sentenceCaseLabel('FICA outstanding'), 'FICA outstanding');
      expect(sentenceCaseLabel(null, fallback: '—'), '—');
    });
  });
}
