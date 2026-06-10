import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Every appointment/event time in CoreX is anchored to South Africa
/// (`Africa/Johannesburg`, UTC+2, no DST). The backend stores and returns event
/// times with that offset, e.g. `2026-06-11T11:00:00+02:00`.
///
/// `DateTime.parse` folds that offset into a UTC instant and drops it, so any
/// display that reads `.hour`/`.minute` off the raw value — or calls
/// `.toLocal()` — renders the *device's* wall-clock time. On a device set to UTC
/// (emulators, CI, some test phones) an 11:00 event then shows as 09:00.
///
/// Always convert through [jhb] for display, and build picker/save values with
/// [jhbWallClock], so the rendered time is correct regardless of device zone.
/// We use the timezone identifier (not a hardcoded ±2) so any future DST/offset
/// change for the zone stays correct automatically.

tz.Location? _jhb;

tz.Location get _location {
  var loc = _jhb;
  if (loc == null) {
    tzdata.initializeTimeZones();
    loc = tz.getLocation('Africa/Johannesburg');
    _jhb = loc;
  }
  return loc;
}

/// Warm the timezone database once at startup. Optional — [jhb] and
/// [jhbWallClock] lazily initialise on first use — but calling this in `main`
/// avoids the one-off cost on the first event render.
void initAppTime() => _location;

/// Convert any instant to its Africa/Johannesburg wall-clock time. Reading
/// `.hour`/`.minute`/`.day`/`.weekday` on the result yields SA-local values.
/// Safe for both UTC values (`DateTime.parse('…+02:00')`) and device-local ones,
/// since the conversion is anchored to the underlying instant.
tz.TZDateTime jhb(DateTime d) => tz.TZDateTime.from(d, _location);

/// Build an Africa/Johannesburg instant from wall-clock components. Use when
/// reconstructing a time from date/time pickers (whose fields are wall-clock),
/// then call `.toUtc().toIso8601String()` on the result before sending to the
/// API so the stored instant matches the SA time the user picked.
tz.TZDateTime jhbWallClock(int year, int month, int day,
        [int hour = 0, int minute = 0]) =>
    tz.TZDateTime(_location, year, month, day, hour, minute);
