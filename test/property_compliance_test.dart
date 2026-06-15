import 'package:flutter_test/flutter_test.dart';
import 'package:corex_mobile/models/property_compliance.dart';

void main() {
  group('PropertyCompliance.fromJson', () {
    final json = {
      'property_id': 123,
      'status': 'BLOCKED',
      'marketable': false,
      'ready': false,
      'snapshot_at': null,
      'snapshotted_by': null,
      'first_marketed_at': '2026-06-15T10:00:00+02:00',
      'blocked_by': ['No signed authority document (mandate or marketing permission)'],
      'next_actions': [
        {'label': 'Send Marketing Pack', 'action_url': 'https://example.test/pack'}
      ],
      'checklist': {
        'authority_to_market': {'passed': false, 'detail': 'No signed authority document...'},
        'fica_sellers': {'passed': true, 'detail': 'All 1 seller(s) FICA approved'},
        'photos': {'passed': false, 'detail': 'Only 2 photos (minimum 4 required)'},
        'details_complete': {'passed': true, 'detail': 'All required listing details complete'},
        'dev_override': {'passed': true, 'detail': 'Checks disabled in dev'},
      },
      'photos': {'count': 2, 'required': 4, 'passed': false},
      'sellers': [
        {
          'contact_id': 9,
          'name': 'John Owner',
          'role': 'owner',
          'fica_status': 'approved',
          'fica_passed': true
        }
      ],
    };

    test('parses status, blocked_by, photos and sellers', () {
      final c = PropertyCompliance.fromJson(json);
      expect(c.propertyId, 123);
      expect(c.status, 'BLOCKED');
      expect(c.isLive, isFalse);
      expect(c.ready, isFalse);
      expect(c.blockedBy, hasLength(1));
      expect(c.nextActions.single.label, 'Send Marketing Pack');
      expect(c.photos!.count, 2);
      expect(c.photos!.required, 4);
      expect(c.sellers.single.ficaPassed, isTrue);
    });

    test('renders canonical gates first, then unknown gates appended', () {
      final c = PropertyCompliance.fromJson(json);
      expect(c.checklist.map((g) => g.key).toList(),
          ['authority_to_market', 'fica_sellers', 'photos', 'details_complete', 'dev_override']);
    });

    test('LIVE status drives isLive and parses attribution', () {
      final c = PropertyCompliance.fromJson({
        ...json,
        'status': 'LIVE',
        'marketable': true,
        'snapshot_at': '2026-06-15T10:00:00+02:00',
        'snapshotted_by': 'Jane Agent',
      });
      expect(c.isLive, isTrue);
      expect(c.snapshottedBy, 'Jane Agent');
    });
  });

  group('complianceGateLabel', () {
    test('uses curated labels for known gates', () {
      expect(complianceGateLabel('authority_to_market'), 'Authority to market');
      expect(complianceGateLabel('fica_sellers'), 'Seller FICA');
    });

    test('humanises unknown gate keys', () {
      expect(complianceGateLabel('dev_override'), 'Dev Override');
      expect(complianceGateLabel('some_new_gate'), 'Some New Gate');
    });
  });

  group('PropertyCompliance.fromBlockedReport', () {
    test('lifts report + blocked_by from a 422 body', () {
      final c = PropertyCompliance.fromBlockedReport(55, {
        'message': 'Marketing is blocked',
        'blocked_by': ['Only 2 photos (minimum 4 required)'],
        'report': {
          'ready': false,
          'checklist': {
            'photos': {'passed': false, 'detail': 'Only 2 photos'}
          },
        },
      });
      expect(c.propertyId, 55);
      expect(c.ready, isFalse);
      expect(c.blockedBy, contains('Only 2 photos (minimum 4 required)'));
      expect(c.checklist.single.key, 'photos');
    });
  });
}
