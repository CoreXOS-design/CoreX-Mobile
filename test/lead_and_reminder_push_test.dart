import 'package:flutter_test/flutter_test.dart';

import 'package:corex_mobile/models/calendar_form.dart';
import 'package:corex_mobile/services/messaging_service.dart';

/// Section 6 of the push contract: new-lead and appointment-reminder pushes,
/// and the per-appointment reminder options on the event form.
void main() {
  group('push tap routing', () {
    test('a new-lead push opens the lead, not the rentals path', () {
      expect(
        MessagingService.resolveAction({
          'type': 'portal_lead',
          'portal_lead_id': '31',
          'deep_link': '/portal-leads/31',
          'target': 'portal_lead',
          'target_id': '31',
          'event_key': 'lead.portal_received',
        }),
        '/portal-leads/31',
      );
    });

    test('a new-lead push without target still opens the lead', () {
      expect(
        MessagingService.resolveAction(
            {'type': 'portal_lead', 'portal_lead_id': '31'}),
        '/portal-leads/31',
      );
    });

    test('an appointment reminder opens the event', () {
      final url = MessagingService.resolveAction({
        'type': 'event_due_reminder',
        'event_id': '88',
        'event_date': '2026-10-27 09:00:00',
        'deep_link': '/calendar/events/88',
        'target': 'calendar_event',
        'target_id': '88',
      });
      expect(url, '/corex/command-center/calendar?event=88');
    });

    test('rental targets still take the rentals path', () {
      final url = MessagingService.resolveAction(
          {'target': 'fault', 'target_id': '42'});
      expect(Uri.parse(url!).scheme, 'corex-rental');
    });
  });

  group('reminder options', () {
    test('parses lead options, my default and channels', () {
      final opts = CalendarOptions.fromJson({
        'categories': [],
        'reminder': {
          'lead_options': [
            {'minutes': 15, 'label': '15 minutes before'},
            {'minutes': 60, 'label': '1 hour before'},
          ],
          'my_default_minutes': 30,
          'channels': [
            {'key': 'popup', 'label': 'Notification'},
            {'key': 'email', 'label': 'Email'},
          ],
          'default_channels': ['popup'],
        },
      });
      final r = opts.reminder!;
      expect(r.leadOptions.map((o) => o.minutes), [15, 60]);
      expect(r.myDefaultMinutes, 30);
      expect(r.channels.map((c) => c.label), ['Notification', 'Email']);
      expect(r.defaultChannels, ['popup']);
    });

    test('an older backend without a reminder block gives null', () {
      expect(CalendarOptions.fromJson({'categories': []}).reminder, isNull);
    });

    test('the event carries its own choice; null means none set', () {
      final set = EventFormData.fromJson({
        'id': 1,
        'title': 'Viewing',
        'event_date': '2026-10-27T09:00:00',
        'reminder_minutes_before': 15,
        'reminder_channels': ['popup', 'email'],
      });
      expect(set.reminderMinutesBefore, 15);
      expect(set.reminderChannels, ['popup', 'email']);

      final unset = EventFormData.fromJson({
        'id': 2,
        'title': 'Viewing',
        'event_date': '2026-10-27T09:00:00',
        'reminder_minutes_before': null,
        'reminder_channels': null,
      });
      expect(unset.reminderMinutesBefore, isNull);
      expect(unset.reminderChannels, isNull);
    });
  });
}
