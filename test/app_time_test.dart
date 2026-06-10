import 'package:flutter_test/flutter_test.dart';
import 'package:corex_mobile/models/dashboard_data.dart';
import 'package:corex_mobile/utils/app_time.dart';

/// Regression tests for the "event time renders 2 hours early on UTC devices"
/// bug. The backend returns event times anchored to Africa/Johannesburg
/// (UTC+2), e.g. "2026-06-11T11:00:00+02:00". `DateTime.parse` folds that offset
/// into a UTC instant and discards it, so any display that uses `.toLocal()` or
/// reads `.hour` off the raw value renders the *device's* wall-clock — 09:00 on
/// a device set to UTC instead of the correct 11:00.
///
/// [jhb]/[jhbWallClock] never consult the device zone, so these assertions hold
/// regardless of the machine the test runs on — which is exactly why the fix is
/// correct on a UTC emulator/CI box.
void main() {
  setUpAll(initAppTime);

  const iso = '2026-06-11T11:00:00+02:00';

  group('jhb() display conversion', () {
    test('renders the SA wall-clock time, not the device zone', () {
      final dt = jhb(DateTime.parse(iso));
      expect(dt.year, 2026);
      expect(dt.month, 6);
      expect(dt.day, 11);
      expect(dt.hour, 11); // the bug rendered 09 here
      expect(dt.minute, 0);
    });

    test('is independent of how the same instant is expressed', () {
      // 11:00 SAST == 09:00 UTC. However the source DateTime is built
      // (parsed-with-offset, explicit UTC, or local), jhb pins it to 11:00 SA.
      final fromOffset = jhb(DateTime.parse(iso));
      final fromUtc = jhb(DateTime.utc(2026, 6, 11, 9, 0));
      final fromEpoch =
          jhb(DateTime.fromMillisecondsSinceEpoch(fromUtc.millisecondsSinceEpoch));
      expect(fromOffset.hour, 11);
      expect(fromUtc.hour, 11);
      expect(fromEpoch.hour, 11);
    });
  });

  test('CalendarEvent.fromJson time renders at 11:00 in SA', () {
    final event = CalendarEvent.fromJson({
      'id': 5741,
      'title': 'Fetch keys',
      'event_date': iso,
    });
    final shown = jhb(event.eventDate);
    expect(shown.hour, 11);
    expect(shown.day, 11);
  });

  test('jhbApiString sends the picked SA wall-clock, not a UTC instant', () {
    // User picks 11:00 on 11 Jun. The backend (like the web cockpit's
    // `datetime-local` field) parses what it receives in its own SA timezone
    // and never shifts UTC→SAST on write, so we must send the naive wall-clock
    // "11:00" — NOT "09:00Z" (which the server would store as 09:00 SA, two
    // hours early: the original "save makes 10:00 become 08:00" bug).
    final picked = jhbWallClock(2026, 6, 11, 11, 0);
    expect(jhbApiString(picked), '2026-06-11T11:00:00');
    // And reading it back for display yields 11:00 again.
    expect(jhb(picked).hour, 11);
  });

  test('jhbApiString of a parsed +02:00 instant preserves SA wall-clock', () {
    // A value coming back from the API (UTC instant under the hood) re-sent
    // unchanged must round-trip to the same wall-clock, not drift.
    expect(jhbApiString(DateTime.parse(iso)), '2026-06-11T11:00:00');
  });
}
