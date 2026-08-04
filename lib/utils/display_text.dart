/// Presentation casing for machine-shaped values.
///
/// The API returns enum-ish values in their storage form — `active`,
/// `under_offer`, `not_started`, `sole_mandate` — and several screens rendered
/// them straight into a chip or badge, so the UI read "active" and
/// "under_offer" next to properly-cased copy. This is the single place that
/// turns those into label case.
///
/// Deliberately conservative: it only ever *raises* the first letter of a word
/// and never lowers anything. That keeps acronyms and codes the server already
/// capitalised intact — `FICA`, `OTP`, `P24`, `VAT` — where a naive
/// `toLowerCase()`-then-capitalise pass would mangle them into `Fica` and
/// `P24` into `P24` only by luck.
///
/// Not for user-authored text. Names, descriptions and notes are typed by a
/// person and must render exactly as entered.
library;

/// `active` → `Active`, `under_offer` → `Under Offer`, `FICA` → `FICA`.
///
/// Separators (`_`, `-`) become spaces and runs of whitespace collapse, so
/// `not__started` and `not started` land on the same label. Returns [fallback]
/// for null/blank input.
String titleCaseLabel(String? raw, {String fallback = ''}) {
  final source = (raw ?? '').replaceAll('_', ' ').replaceAll('-', ' ').trim();
  if (source.isEmpty) return fallback;

  return source
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .map(_capitaliseFirst)
      .join(' ');
}

/// Like [titleCaseLabel] but only the first word is raised, for values that sit
/// inside a sentence rather than standing alone in a chip.
String sentenceCaseLabel(String? raw, {String fallback = ''}) {
  final source = (raw ?? '').replaceAll('_', ' ').replaceAll('-', ' ').trim();
  if (source.isEmpty) return fallback;

  final collapsed = source.split(RegExp(r'\s+')).join(' ');
  return _capitaliseFirst(collapsed);
}

/// Raises the first character and leaves the rest of the word untouched, so an
/// already-capitalised acronym survives.
String _capitaliseFirst(String word) =>
    word.isEmpty ? word : word[0].toUpperCase() + word.substring(1);
