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
/// then pass the result to [jhbApiString] before sending to the API so the
/// stored time matches the SA wall-clock the user picked.
tz.TZDateTime jhbWallClock(int year, int month, int day,
        [int hour = 0, int minute = 0]) =>
    tz.TZDateTime(_location, year, month, day, hour, minute);

/// Format an instant as the Africa/Johannesburg wall-clock string the backend
/// expects for writes: `yyyy-MM-ddTHH:mm:ss` — naive, with no `Z` or offset,
/// exactly like the web cockpit's `datetime-local` fields. The server parses
/// this in its own SA timezone, so the stored time equals the picked time.
///
/// Do NOT send `.toUtc().toIso8601String()`: the server treats the literal
/// clock time it receives as SA-local and never shifts UTC→SAST on write, so a
/// `…Z` value (e.g. 10:00 picked → `08:00Z` sent) is stored — and read back —
/// two hours early.
/// Coarse "how long ago" label for a timestamp — `just now`, `5m ago`,
/// `3d ago`, `2mo ago`. Returns null for a missing/unparseable value so callers
/// can omit the field rather than render a placeholder.
///
/// Deliberately elapsed-time only, so it needs no timezone conversion: the
/// difference between two instants is the same in every zone.
String? relativeTime(String? iso, {DateTime? now}) {
  if (iso == null || iso.isEmpty) return null;
  final dt = DateTime.tryParse(iso);
  if (dt == null) return null;
  final diff = (now ?? DateTime.now()).difference(dt);
  if (diff.isNegative) return 'just now';
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  if (diff.inDays < 30) return '${(diff.inDays / 7).floor()}w ago';
  if (diff.inDays < 365) return '${(diff.inDays / 30).floor()}mo ago';
  return '${(diff.inDays / 365).floor()}y ago';
}

String jhbApiString(DateTime d) {
  final t = jhb(d);
  String p(int n) => n.toString().padLeft(2, '0');
  return '${t.year}-${p(t.month)}-${p(t.day)}'
      'T${p(t.hour)}:${p(t.minute)}:${p(t.second)}';
}
