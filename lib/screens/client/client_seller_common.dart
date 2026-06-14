import 'package:flutter/material.dart';

import '../../widgets/ui/status_chip.dart';

const Color _kSellerActive = Color(0xFF22C55E);
const Color _kSellerPending = Color(0xFF0EA5E9);
const Color _kSellerInactive = Color(0xFF8890A4);
const Color _kSellerSold = Color(0xFFF59E0B);

Color sellerStatusColor(String? s) {
  switch ((s ?? '').toLowerCase()) {
    case 'active':
    case 'live':
    case 'published':
      return _kSellerActive;
    case 'pending':
    case 'under_offer':
    case 'under offer':
      return _kSellerPending;
    case 'sold':
    case 'rented':
    case 'leased':
      return _kSellerSold;
    case 'inactive':
    case 'unpublished':
    case 'withdrawn':
    case 'expired':
      return _kSellerInactive;
    default:
      return _kSellerActive;
  }
}

/// Status pill for a listing. Title-cases the raw status and normalises
/// underscores so "under_offer" reads "Under Offer".
Widget sellerStatusPill(String? status) {
  final raw = (status == null || status.isEmpty) ? 'active' : status;
  final label = raw
      .replaceAll('_', ' ')
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
  return StatusChip(
    label: label,
    color: sellerStatusColor(status),
    dense: true,
  );
}

/// Formats an integer ZAR amount as "R 2,450,000". Used for the numeric
/// monetary fields (market_value, area_average) that have no *_display string.
String sellerMoney(num value) {
  final s = value.round().abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final fromEnd = s.length - i;
    buf.write(s[i]);
    if (fromEnd > 1 && (fromEnd - 1) % 3 == 0) buf.write(',');
  }
  final sign = value < 0 ? '-' : '';
  return 'R $sign$buf';
}
