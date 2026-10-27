import 'dart:math';

final Random _rng = Random.secure();

/// A random RFC 4122 version-4 uuid, e.g. `6f1c2b9e-3d4a-4c1e-9b7f-0a1b2c3d4e5f`.
///
/// Used for `client_idempotency_key`: minted once when the person taps, then
/// persisted with the queued write and resent unchanged on every retry, so the
/// server can recognise a replay. The server validates the v4 shape, so the
/// version and variant bits are set exactly.
String uuidV4() {
  final b = List<int>.generate(16, (_) => _rng.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40; // version 4
  b[8] = (b[8] & 0x3f) | 0x80; // variant 10xx
  String hex(int from, int to) => b
      .sublist(from, to)
      .map((e) => e.toRadixString(16).padLeft(2, '0'))
      .join();
  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}
