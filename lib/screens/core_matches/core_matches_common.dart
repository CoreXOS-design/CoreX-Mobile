import 'package:flutter/material.dart';
import '../../utils/display_text.dart';
import '../../widgets/ui/status_chip.dart';

const Color kReactionInterested = Color(0xFF22C55E);
const Color kReactionNotInterested = Color(0xFFEF4444);
const Color kReactionSaved = Color(0xFFF59E0B);

const Color kStatusActive = Color(0xFF0EA5E9);
const Color kStatusPaused = Color(0xFF8890A4);
const Color kStatusFulfilled = Color(0xFF22C55E);
const Color kStatusExpired = Color(0xFFEF4444);

const List<String> kStatuses = ['active', 'paused', 'fulfilled', 'expired'];

Color statusColor(String? s) {
  switch (s) {
    case 'paused':
      return kStatusPaused;
    case 'fulfilled':
      return kStatusFulfilled;
    case 'expired':
      return kStatusExpired;
    default:
      return kStatusActive;
  }
}

Widget statusPill(String? status) {
  return StatusChip(
    label: titleCaseLabel(status, fallback: 'Active'),
    color: statusColor(status),
    dense: true,
  );
}

const Color kTierStrong = Color(0xFF22C55E);
const Color kTierGood = Color(0xFF0EA5E9);
const Color kTierFair = Color(0xFFF59E0B);

/// Resolves a tier colour from the API `match_tier` string, falling back to
/// score thresholds when the tier is absent (legacy payloads).
Color tierColor(String? tier, {int? score}) {
  switch (tier) {
    case 'strong':
      return kTierStrong;
    case 'good':
      return kTierGood;
    case 'fair':
      return kTierFair;
  }
  if (score != null) {
    if (score >= 80) return kTierStrong;
    if (score >= 65) return kTierGood;
  }
  return kTierFair;
}

String tierLabel(String? tier, {int? score}) {
  switch (tier) {
    case 'strong':
      return 'Strong matches';
    case 'good':
      return 'Good matches';
    case 'fair':
      return 'Fair matches';
  }
  if (score != null) {
    if (score >= 80) return 'Strong matches';
    if (score >= 65) return 'Good matches';
  }
  return 'Fair matches';
}

/// Compact percentage badge for a property's match score, colour-coded by tier.
Widget matchScoreBadge(int score, String? tier) {
  final c = tierColor(tier, score: score);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      '$score%',
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: c,
      ),
    ),
  );
}

Widget reactionBadge(String reaction) {
  late Color c;
  late String label;
  switch (reaction) {
    case 'interested':
      c = kReactionInterested;
      label = 'Interested';
      break;
    case 'not_interested':
      c = kReactionNotInterested;
      label = 'Not for me';
      break;
    case 'saved':
      c = kReactionSaved;
      label = 'Saved';
      break;
    default:
      return const SizedBox.shrink();
  }
  return StatusChip(label: label, color: c);
}
