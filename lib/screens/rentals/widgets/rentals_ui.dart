export '../../../models/rentals/paged_result.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:tabler_icons/tabler_icons.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../models/rentals/paged_result.dart';
import '../../../services/api_service.dart' show ApiException;
import '../../../services/rentals/rental_write_queue.dart';
import '../../../services/rentals/rentals_http.dart';
import '../../../theme.dart';
import '../../../theme/corex_accent_theme.dart';
import '../../../theme/corex_tokens.dart';
import '../../../widgets/ui/content_width.dart';
import '../../../widgets/ui/list_row.dart';
import '../../../widgets/ui/status_chip.dart';

// Shared building blocks for every rentals screen (staff, owner, tenant).
//
// Rule for all of them: the server decides, the app displays. Labels, status
// wording and empty-state sentences come from the payload; nothing here maps a
// status to business meaning beyond picking a colour for it.

// ── Formatting ─────────────────────────────────────────────────────────────

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// `2026-10-25` → `25 Oct 2026`. Returns the input unchanged if it isn't a date.
String fmtDate(String? ymd) {
  if (ymd == null || ymd.isEmpty) return '';
  final d = DateTime.tryParse(ymd);
  if (d == null) return ymd;
  return '${d.day} ${_months[d.month - 1]} ${d.year}';
}

/// An ISO moment → `25 Oct 2026, 09:30` in the phone's local time.
String fmtMoment(String? iso) {
  if (iso == null || iso.isEmpty) return '';
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return iso;
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  return '${d.day} ${_months[d.month - 1]} ${d.year}, $hh:$mm';
}

String ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Colour for a server status key. Purely cosmetic: unknown keys are neutral.
Color statusColor(BuildContext context, String? status) {
  final s = (status ?? '').toLowerCase();
  const red = Color(0xFFEF4444);
  const amber = Color(0xFFF59E0B);
  const green = Color(0xFF22C55E);
  if (s.contains('emergency') ||
      s.contains('overdue') ||
      s.contains('declined') ||
      s.contains('disputed') ||
      s.contains('refused') ||
      s.contains('rejected')) {
    return red;
  }
  if (s.contains('urgent') ||
      s.contains('await') ||
      s.contains('review') ||
      s.contains('received') ||
      s.contains('due') ||
      s.contains('notice') ||
      s.contains('renewal') ||
      s.contains('draft') ||
      s.contains('reported') ||
      s.contains('pending')) {
    return amber;
  }
  if (s.contains('resolved') ||
      s.contains('completed') ||
      s.contains('approved') ||
      s.contains('active') ||
      s.contains('running') ||
      s.contains('signed') ||
      s.contains('accepted') ||
      s.contains('done') ||
      s.contains('renewed')) {
    return green;
  }
  if (s.contains('cancel') || s.contains('ended') || s.contains('expired')) {
    return CorexTokens.textTertiary(context);
  }
  return CorexAccentTheme.of(context).accentText;
}

// ── Page chrome ────────────────────────────────────────────────────────────

/// Page used by every rentals screen: CoreX backlight, a back button, a title
/// and optional actions, then the body.
class RentalsPage extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget body;
  final Widget? floatingActionButton;
  final Widget? bottomBar;
  final bool showBack;

  const RentalsPage({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.actions = const [],
    this.floatingActionButton,
    this.bottomBar,
    this.showBack = true,
  });

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: Theme.of(context).brightness == Brightness.light
          ? SystemUiOverlayStyle.dark
          : SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor: CorexTokens.pageBase(context),
        floatingActionButton: floatingActionButton,
        bottomNavigationBar: bottomBar,
        body: Container(
          decoration:
              BoxDecoration(gradient: CorexTokens.pageBacklight(context)),
          child: ContentSafeArea(
            bottom: bottomBar == null,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 56,
                  child: Row(
                    children: [
                      if (showBack)
                        IconButton(
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: Icon(TablerIcons.arrow_left,
                              color: CorexTokens.textPrimary(context)),
                        )
                      else
                        const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: CorexTokens.textPrimary(context),
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                              ),
                            ),
                            if (subtitle != null && subtitle!.isNotEmpty)
                              Text(
                                subtitle!,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: CorexTokens.textSecondary(context),
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      ),
                      ...actions,
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
                Expanded(child: body),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The detail-screen card the rest of the app uses (contact, property): flat
/// surface, hairline border, [AppTheme.radius]. No gradient, no shadow.
class RentalsCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;

  const RentalsCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // The app's card recipe (ListRow, Home): soft gradient + soft shadow,
    // no outline.
    final radius = BorderRadius.circular(AppTheme.radius);
    return Container(
      decoration: BoxDecoration(
        gradient: AppTheme.cardGradient(context),
        borderRadius: radius,
        boxShadow: AppTheme.softShadow(context),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// A titled card group on a detail screen, titled like the property and
/// contact screens' sections (sentence case, 15 bold).
class RentalsSection extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  const RentalsSection({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(16, 0, 16, 16),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            // Room for icon actions without the title row jumping.
            height: 36,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary(context),
                    ),
                  ),
                ),
                if (trailing != null) trailing!,
              ],
            ),
          ),
          const SizedBox(height: 4),
          RentalsCard(child: child),
        ],
      ),
    );
  }
}

/// Icon-only action beside a section title (Photo, Note, Add item) —
/// icon-only on mobile, with the label as its tooltip.
class RentalsSectionAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  const RentalsSectionAction(
      {super.key,
      required this.icon,
      required this.tooltip,
      required this.onPressed});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        icon: Icon(icon, size: 20, color: AppTheme.brand),
      );
}

/// A row that opens something, inside a section card — the app's
/// "Compliance" row: tinted icon circle, title, muted subtitle, chevron.
class RentalsNavRow extends StatelessWidget {
  final IconData? icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const RentalsNavRow({
    super.key,
    this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          if (icon != null) ...[
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppTheme.brand.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppTheme.brand, size: 20),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary(context),
                    )),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.textSecondary(context),
                      )),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded,
                size: 18, color: AppTheme.textMuted(context)),
          ],
        ]),
      ),
    );
  }
}

/// A quick action in a 2-up grid — the contact screen's secondary action
/// buttons: surface2 fill, button radius, icon + label.
class RentalsActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const RentalsActionTile(
      {super.key,
      required this.icon,
      required this.label,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppTheme.radiusButton);
    return Material(
      color: AppTheme.surface2(context),
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(children: [
              Icon(icon, size: 18, color: AppTheme.textPrimary(context)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary(context),
                    )),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The app's choice chip (property list, match editor): surface2 fill,
/// brand fill when chosen, no outline.
class RentalsChoiceChip extends StatelessWidget {
  final Widget label;
  final bool selected;
  final ValueChanged<bool>? onSelected;

  /// A server-given tint (e.g. a condition's severity): a light wash when
  /// not chosen, the full colour when chosen. Null keeps the brand look.
  final Color? color;
  const RentalsChoiceChip(
      {super.key,
      required this.label,
      required this.selected,
      this.onSelected,
      this.color});

  @override
  Widget build(BuildContext context) => ChoiceChip(
        label: label,
        selected: selected,
        onSelected: onSelected,
        backgroundColor:
            color?.withValues(alpha: 0.14) ?? AppTheme.surface2(context),
        selectedColor: color ?? AppTheme.brand,
        checkmarkColor: Colors.white,
        labelStyle: TextStyle(
          fontWeight: FontWeight.w600,
          color: selected ? Colors.white : AppTheme.textPrimary(context),
        ),
        side: BorderSide.none,
      );
}

/// The web's own severity colours (`RentalInspectionSetting::SEVERITY_COLORS`).
const _kSeverityColors = <String, Color>{
  'blue': Color(0xFF0EA5E9),
  'red': Color(0xFFC41E3A),
  'amber': Color(0xFFF59E0B),
  'grey': Color(0xFF6B7280),
};

/// Colour of a condition [key], read from the agency's `condition_states`
/// (`severity`). As on the web, a key the list does not know — or a
/// severity it does not know — is red.
Color conditionColor(List<Json> conditionStates, String? key) {
  for (final c in conditionStates) {
    if (c.str('key') == key) {
      return _kSeverityColors[c.str('severity')] ?? _kSeverityColors['red']!;
    }
  }
  return _kSeverityColors['red']!;
}

/// The label the agency gave a condition [key]; the key itself only when
/// the list does not know it.
String conditionLabel(List<Json> conditionStates, String? key) {
  for (final c in conditionStates) {
    if (c.str('key') == key) return c.str('label') ?? key ?? '';
  }
  return key ?? '';
}

/// A small label inside a section card ("Room photos", "Note").
class RentalsSubLabel extends StatelessWidget {
  final String text;
  const RentalsSubLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary(context),
            )),
      );
}

enum RentalsAlertTone { info, warning, danger }

/// An inline notice block (design system §3.9): tinted fill, tinted
/// hairline, icon + sentence.
class RentalsAlert extends StatelessWidget {
  final String message;
  final RentalsAlertTone tone;
  const RentalsAlert(this.message,
      {super.key, this.tone = RentalsAlertTone.info});

  @override
  Widget build(BuildContext context) {
    final (tint, icon) = switch (tone) {
      RentalsAlertTone.info => (AppTheme.brand, TablerIcons.info_circle),
      RentalsAlertTone.warning =>
        (const Color(0xFFF59E0B), TablerIcons.alert_triangle),
      RentalsAlertTone.danger =>
        (const Color(0xFFDC2626), TablerIcons.alert_octagon),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: tint),
        const SizedBox(width: 10),
        Expanded(
          child: Text(message,
              style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: AppTheme.textPrimary(context))),
        ),
      ]),
    );
  }
}

/// A server value ("in_progress", "landlord") for display only.
String displayValue(String? v) {
  if (v == null || v.isEmpty) return '';
  final s = v.replaceAll('_', ' ');
  return s[0].toUpperCase() + s.substring(1);
}

/// Label on the left, value on the right. Hidden when [value] is empty, so a
/// payload's nulls never render as blank rows.
class KeyValueRow extends StatelessWidget {
  final String label;
  final String? value;
  final VoidCallback? onTap;
  final IconData? icon;

  const KeyValueRow(this.label, this.value,
      {super.key, this.onTap, this.icon});

  @override
  Widget build(BuildContext context) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return const SizedBox.shrink();
    final t = CorexAccentTheme.of(context);
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: TextStyle(
                    fontSize: 13, color: CorexTokens.textSecondary(context))),
          ),
          Expanded(
            child: Text(
              v,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: onTap != null
                    ? t.accentText
                    : CorexTokens.textPrimary(context),
              ),
            ),
          ),
          if (icon != null) Icon(icon, size: 16, color: t.accentText),
        ],
      ),
    );
    return onTap == null
        ? row
        : InkWell(onTap: onTap, borderRadius: BorderRadius.circular(8), child: row);
  }
}

/// Plain paragraph inside a section.
class BodyText extends StatelessWidget {
  final String text;
  final bool muted;
  const BodyText(this.text, {super.key, this.muted = false});

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: TextStyle(
          fontSize: 13,
          height: 1.4,
          color: muted
              ? CorexTokens.textSecondary(context)
              : CorexTokens.textPrimary(context),
        ),
      );
}

class RentalsStatusChip extends StatelessWidget {
  final String label;
  final String? statusKey;
  final IconData? icon;

  /// A colour the server decided (e.g. a condition's severity); wins over
  /// [statusKey].
  final Color? color;
  const RentalsStatusChip(this.label,
      {super.key, this.statusKey, this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    if (label.isEmpty) return const SizedBox.shrink();
    return StatusChip(
      label: label,
      color: color ?? statusColor(context, statusKey ?? label),
      icon: icon,
      dense: true,
    );
  }
}

// ── States ─────────────────────────────────────────────────────────────────

class RentalsLoading extends StatelessWidget {
  const RentalsLoading({super.key});
  @override
  Widget build(BuildContext context) =>
      const Center(child: CircularProgressIndicator());
}

/// A failed load: the server's sentence and a Retry.
class RentalsError extends StatelessWidget {
  final Object error;
  final VoidCallback onRetry;
  const RentalsError({super.key, required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final e = error;
    final msg = e is ApiException
        ? e.message
        : 'Something went wrong loading this.';
    return ListView(
      children: [
        EmptyState(
          icon: TablerIcons.cloud_off,
          title: 'Could not load',
          subtitle: msg,
          action: OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size(120, 44)),
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ),
      ],
    );
  }
}

/// The server's `meta.empty_reason`, as-is.
class RentalsEmpty extends StatelessWidget {
  final String? reason;
  final IconData icon;
  final Widget? action;
  const RentalsEmpty(
      {super.key, this.reason, this.icon = TablerIcons.inbox, this.action});

  @override
  Widget build(BuildContext context) => EmptyState(
        icon: icon,
        title: reason?.isNotEmpty == true ? reason! : 'Nothing here yet.',
        action: action,
      );
}

/// Loads a future once with pull-to-refresh, loading and error states.
class RentalsFutureView<T> extends StatefulWidget {
  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data, Future<void> Function() reload)
      builder;

  /// Bumped by a parent to force a reload (e.g. after an action).
  final Listenable? refresh;

  const RentalsFutureView(
      {super.key, required this.load, required this.builder, this.refresh});

  @override
  State<RentalsFutureView<T>> createState() => _RentalsFutureViewState<T>();
}

class _RentalsFutureViewState<T> extends State<RentalsFutureView<T>> {
  T? _data;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    widget.refresh?.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    widget.refresh?.removeListener(_reload);
    super.dispose();
  }

  Future<void> _reload() async {
    if (!mounted) return;
    setState(() {
      _loading = _data == null;
      _error = null;
    });
    try {
      final d = await widget.load();
      if (!mounted) return;
      setState(() {
        _data = d;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const RentalsLoading();
    if (_error != null && _data == null) {
      return RentalsError(error: _error!, onRetry: _reload);
    }
    return RefreshIndicator(
      onRefresh: _reload,
      child: widget.builder(context, _data as T, _reload),
    );
  }
}

// ── Paged lists ────────────────────────────────────────────────────────────

/// A single-select filter offered above a list. [options] are exactly the
/// values the endpoint documents (an unknown value is a 422).
class ListFilter {
  final String param;
  final String label;
  final List<(String value, String label)> options;
  const ListFilter(
      {required this.param, required this.label, required this.options});
}

/// Search (debounced ~400 ms) + filter chips + infinite scroll over a
/// paginated rentals list. Shows the server's `empty_reason` when empty.
class RentalsPagedList<T> extends StatefulWidget {
  final Future<PagedResult<T>> Function(int page, Map<String, String> query)
      fetch;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final List<ListFilter> filters;
  final Map<String, String> initialFilters;
  final String searchHint;
  final bool searchable;
  final Listenable? refresh;
  final Widget? header;

  const RentalsPagedList({
    super.key,
    required this.fetch,
    required this.itemBuilder,
    this.filters = const [],
    this.initialFilters = const {},
    this.searchHint = 'Search',
    this.searchable = true,
    this.refresh,
    this.header,
  });

  @override
  State<RentalsPagedList<T>> createState() => _RentalsPagedListState<T>();
}

class _RentalsPagedListState<T> extends State<RentalsPagedList<T>> {
  final _items = <T>[];
  final _scroll = ScrollController();
  final _search = TextEditingController();
  late Map<String, String> _filters;
  Timer? _debounce;
  int _page = 0;
  int _lastPage = 1;
  int _total = 0;
  String? _emptyReason;
  bool _loading = false;
  Object? _error;

  /// Guards against a slow page-1 answer landing after a newer search.
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    _filters = Map.of(widget.initialFilters);
    _scroll.addListener(_onScroll);
    widget.refresh?.addListener(_reset);
    _reset();
  }

  @override
  void dispose() {
    widget.refresh?.removeListener(_reset);
    _debounce?.cancel();
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 300) {
      _loadMore();
    }
  }

  Map<String, String> get _query => {
        ..._filters,
        if (_search.text.trim().isNotEmpty) 'q': _search.text.trim(),
      };

  Future<void> _reset() async {
    _generation++;
    setState(() {
      _items.clear();
      _page = 0;
      _lastPage = 1;
      _error = null;
      _emptyReason = null;
    });
    await _loadMore(force: true);
  }

  Future<void> _loadMore({bool force = false}) async {
    if (_loading && !force) return;
    if (_page >= _lastPage && _page > 0) return;
    final gen = _generation;
    setState(() => _loading = true);
    try {
      final res = await widget.fetch(_page + 1, _query);
      if (!mounted || gen != _generation) return;
      setState(() {
        _items.addAll(res.items);
        _page = res.page;
        _lastPage = res.lastPage;
        _total = res.total;
        _emptyReason = res.emptyReason;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _reset);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.searchable)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: _onSearch,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: widget.searchHint,
                prefixIcon: const Icon(TablerIcons.search, size: 18),
                isDense: true,
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(TablerIcons.x, size: 16),
                        onPressed: () {
                          _search.clear();
                          _reset();
                        },
                      ),
              ),
            ),
          ),
        if (widget.filters.isNotEmpty)
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final f in widget.filters) ...[
                  _FilterChip(
                    filter: f,
                    value: _filters[f.param],
                    onChanged: (v) {
                      setState(() {
                        if (v == null) {
                          _filters.remove(f.param);
                        } else {
                          _filters[f.param] = v;
                        }
                      });
                      _reset();
                    },
                  ),
                  const SizedBox(width: 8),
                ],
              ],
            ),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _reset,
            child: _body(context),
          ),
        ),
      ],
    );
  }

  Widget _body(BuildContext context) {
    if (_items.isEmpty) {
      if (_loading) return const RentalsLoading();
      if (_error != null) return RentalsError(error: _error!, onRetry: _reset);
      return ListView(children: [
        if (widget.header != null) widget.header!,
        RentalsEmpty(reason: _emptyReason),
      ]);
    }
    final extra = (widget.header != null ? 1 : 0);
    final more = _page < _lastPage || _loading || _error != null;
    return ListView.separated(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      itemCount: _items.length + extra + (more ? 1 : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        if (widget.header != null && i == 0) return widget.header!;
        final idx = i - extra;
        if (idx >= _items.length) {
          if (_error != null) {
            return TextButton(
                onPressed: () => _loadMore(force: true),
                child: const Text('Could not load more. Tap to retry.'));
          }
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return widget.itemBuilder(context, _items[idx]);
      },
    );
  }

  int get total => _total;
}

class _FilterChip extends StatelessWidget {
  final ListFilter filter;
  final String? value;
  final ValueChanged<String?> onChanged;
  const _FilterChip(
      {required this.filter, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    String? selectedLabel;
    for (final o in filter.options) {
      if (o.$1 == value) selectedLabel = o.$2;
    }
    final active = value != null;
    final fg = active ? Colors.white : AppTheme.textPrimary(context);
    return ActionChip(
      avatar: Icon(TablerIcons.filter, size: 14, color: fg),
      label: Text(active ? '${filter.label}: $selectedLabel' : filter.label),
      labelStyle: TextStyle(fontWeight: FontWeight.w600, color: fg),
      backgroundColor: active ? AppTheme.brand : AppTheme.surface2(context),
      side: BorderSide.none,
      onPressed: () async {
        final picked = await showModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          builder: (ctx) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(
                  title: Text('Any ${filter.label.toLowerCase()}'),
                  trailing: value == null ? const Icon(Icons.check) : null,
                  onTap: () => Navigator.pop(ctx, '\u0000'),
                ),
                for (final o in filter.options)
                  ListTile(
                    title: Text(o.$2),
                    trailing:
                        o.$1 == value ? const Icon(Icons.check) : null,
                    onTap: () => Navigator.pop(ctx, o.$1),
                  ),
              ],
            ),
          ),
        );
        if (picked == null) return;
        onChanged(picked == '\u0000' ? null : picked);
      },
    );
  }
}

/// A tappable list card: title, a secondary line, a status chip and an
/// optional trailing badge.
class RentalsListCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? meta;
  final String? statusLabel;
  final String? statusKey;
  final List<Widget> badges;
  final VoidCallback? onTap;
  final bool highlight;

  const RentalsListCard({
    super.key,
    required this.title,
    this.subtitle,
    this.meta,
    this.statusLabel,
    this.statusKey,
    this.badges = const [],
    this.onTap,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    // The app's list-row recipe (ListRow): soft card gradient and shadow,
    // AppTheme.radius, no outline — status shows in the chip.
    final radius = BorderRadius.circular(AppTheme.radius);
    return Container(
      decoration: BoxDecoration(
        gradient: AppTheme.cardGradient(context),
        borderRadius: radius,
        boxShadow: AppTheme.softShadow(context),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: _content(context),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (highlight)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(top: 7, right: 8),
                  decoration: BoxDecoration(
                    color: statusColor(context, 'urgent'),
                    shape: BoxShape.circle,
                  ),
                ),
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: CorexTokens.textPrimary(context),
                  ),
                ),
              ),
              if (statusLabel != null && statusLabel!.isNotEmpty) ...[
                const SizedBox(width: 8),
                RentalsStatusChip(statusLabel!, statusKey: statusKey),
              ],
            ],
          ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(subtitle!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13, color: CorexTokens.textSecondary(context))),
          ],
          if ((meta != null && meta!.isNotEmpty) || badges.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ...badges,
                if (meta != null && meta!.isNotEmpty)
                  Text(meta!,
                      style: TextStyle(
                          fontSize: 12,
                          color: CorexTokens.textTertiary(context))),
              ],
            ),
          ],
        ],
    );
  }
}

// ── Timeline ───────────────────────────────────────────────────────────────

/// The server's `timeline[]`: one row per step, done ones ticked, the
/// current one highlighted, never reordered.
class RentalsTimeline extends StatelessWidget {
  final List<Map<String, dynamic>> steps;
  const RentalsTimeline(this.steps, {super.key});

  @override
  Widget build(BuildContext context) {
    final t = CorexAccentTheme.of(context);
    return Column(
      children: [
        for (var i = 0; i < steps.length; i++)
          _row(context, t, steps[i], last: i == steps.length - 1),
      ],
    );
  }

  Widget _row(BuildContext context, CorexAccentTheme t,
      Map<String, dynamic> s,
      {required bool last}) {
    final done = s['state'] == 'done';
    final current = s['current'] == true;
    final color = current
        ? t.accent
        : done
            ? const Color(0xFF22C55E)
            : CorexTokens.textMuted(context);
    final at = fmtMoment(s['at']?.toString());
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 24,
            child: Column(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done ? color : Colors.transparent,
                    border: Border.all(color: color, width: 2),
                  ),
                  child: done
                      ? const Icon(Icons.check, size: 12, color: Colors.white)
                      : null,
                ),
                if (!last)
                  Expanded(
                    child: Container(
                        width: 2, color: CorexTokens.surfaceBorder(context)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (s['label'] ?? '').toString(),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: current ? FontWeight.w700 : FontWeight.w500,
                      color: done || current
                          ? CorexTokens.textPrimary(context)
                          : CorexTokens.textTertiary(context),
                    ),
                  ),
                  if (at.isNotEmpty)
                    Text(at,
                        style: TextStyle(
                            fontSize: 12,
                            color: CorexTokens.textTertiary(context))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Photos ─────────────────────────────────────────────────────────────────

/// Network photo grid (signed URLs: never long-cached, re-fetched with the
/// detail). Tap to view full screen; swipe between the grid's photos there.
class RentalsPhotoGrid extends StatelessWidget {
  final List<String> urls;

  /// Per photo, shown under it in the viewer (e.g. when it was taken).
  final List<String?>? captions;

  /// Photos still on this phone (queued), shown after [urls] marked waiting.
  final List<String> pendingFiles;

  /// A thumbnail failed to load — usually an expired signed link. The screen
  /// re-fetches its detail (once) for fresh links. Called after the frame.
  final VoidCallback? onLoadError;

  /// Shown when there is nothing at all; null shows nothing.
  final String? emptyText;

  const RentalsPhotoGrid(
    this.urls, {
    super.key,
    this.captions,
    this.pendingFiles = const [],
    this.onLoadError,
    this.emptyText = 'No photos.',
  });

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty && pendingFiles.isEmpty) {
      return emptyText == null
          ? const SizedBox.shrink()
          : BodyText(emptyText!, muted: true);
    }
    Widget broken() => Container(
          width: 92,
          height: 92,
          color: AppTheme.surface2(context),
          child: Icon(TablerIcons.photo_off,
              color: AppTheme.textMuted(context)),
        );
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (var i = 0; i < urls.length; i++)
          GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => RentalsPhotoViewer(
                  urls: urls, captions: captions, initialIndex: i),
            )),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                urls[i],
                width: 92,
                height: 92,
                fit: BoxFit.cover,
                cacheWidth: 276,
                errorBuilder: (_, __, ___) {
                  final cb = onLoadError;
                  if (cb != null) {
                    WidgetsBinding.instance.addPostFrameCallback((_) => cb());
                  }
                  return broken();
                },
              ),
            ),
          ),
        for (final p in pendingFiles)
          Stack(children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Opacity(
                opacity: 0.6,
                child: Image.file(File(p),
                    width: 92,
                    height: 92,
                    fit: BoxFit.cover,
                    cacheWidth: 276,
                    errorBuilder: (_, __, ___) => broken()),
              ),
            ),
            const Positioned(
              right: 4,
              bottom: 4,
              child: CircleAvatar(
                radius: 11,
                backgroundColor: Colors.black54,
                child: Icon(TablerIcons.clock, size: 13, color: Colors.white),
              ),
            ),
          ]),
      ],
    );
  }
}

/// Full-screen photos: pinch to zoom, swipe between them, caption below.
class RentalsPhotoViewer extends StatefulWidget {
  final List<String> urls;
  final List<String?>? captions;
  final int initialIndex;
  const RentalsPhotoViewer(
      {super.key, required this.urls, this.captions, this.initialIndex = 0});

  @override
  State<RentalsPhotoViewer> createState() => _RentalsPhotoViewerState();
}

class _RentalsPhotoViewerState extends State<RentalsPhotoViewer> {
  late final PageController _pages =
      PageController(initialPage: widget.initialIndex);
  late int _index = widget.initialIndex;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final captions = widget.captions;
    final caption = captions != null && _index < captions.length
        ? captions[_index]
        : null;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: widget.urls.length > 1
            ? Text('${_index + 1} of ${widget.urls.length}',
                style: const TextStyle(color: Colors.white, fontSize: 15))
            : null,
      ),
      body: Column(children: [
        Expanded(
          child: PageView.builder(
            controller: _pages,
            itemCount: widget.urls.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) => InteractiveViewer(
              child: Center(
                child: Image.network(
                  widget.urls[i],
                  errorBuilder: (_, __, ___) => const Icon(
                      TablerIcons.photo_off,
                      color: Colors.white54,
                      size: 48),
                ),
              ),
            ),
          ),
        ),
        if (caption != null && caption.isNotEmpty)
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Text(caption,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70)),
            ),
          ),
      ]),
    );
  }
}

/// Picks photos from the camera (or library) for a write. Compression happens
/// in the picker itself (`imageQuality` + `maxWidth`), so what goes in the
/// queue is already phone-sized; HEIC is sent as-is and converted server-side.
class PhotoPickerRow extends StatelessWidget {
  final List<XFile> photos;
  final ValueChanged<List<XFile>> onChanged;
  final int max;

  const PhotoPickerRow({
    super.key,
    required this.photos,
    required this.onChanged,
    this.max = 10,
  });

  static final ImagePicker _picker = ImagePicker();

  static Future<XFile?> takeOne(BuildContext context,
      {bool allowLibrary = true}) async {
    ImageSource source = ImageSource.camera;
    if (allowLibrary) {
      final picked = await showModalBottomSheet<ImageSource>(
        context: context,
        showDragHandle: true,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(TablerIcons.camera),
                title: const Text('Take a photo'),
                onTap: () => Navigator.pop(ctx, ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(TablerIcons.photo),
                title: const Text('Choose from library'),
                onTap: () => Navigator.pop(ctx, ImageSource.gallery),
              ),
            ],
          ),
        ),
      );
      if (picked == null) return null;
      source = picked;
    }
    try {
      return await _picker.pickImage(
        source: source,
        imageQuality: 82,
        maxWidth: 2400,
        maxHeight: 2400,
        requestFullMetadata: false,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not open the camera: $e')));
      }
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final p in photos)
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(File(p.path),
                    width: 80, height: 80, fit: BoxFit.cover, cacheWidth: 240),
              ),
              Positioned(
                right: 2,
                top: 2,
                child: InkWell(
                  onTap: () => onChanged(List.of(photos)..remove(p)),
                  child: const CircleAvatar(
                    radius: 11,
                    backgroundColor: Colors.black54,
                    child: Icon(Icons.close, size: 14, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        if (photos.length < max)
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () async {
              final f = await takeOne(context);
              if (f != null) onChanged([...photos, f]);
            },
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: AppTheme.surface2(context),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(TablerIcons.camera_plus,
                      color: CorexTokens.textSecondary(context)),
                  const SizedBox(height: 2),
                  Text('${photos.length}/$max',
                      style: TextStyle(
                          fontSize: 11,
                          color: CorexTokens.textTertiary(context))),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ── Offline queue ──────────────────────────────────────────────────────────

/// "3 waiting to send" strip with a sheet listing what is queued and what the
/// server refused (retry / discard). Also surfaces the queue's notices
/// (e.g. something dropped because it was archived) as a snackbar.
class RentalsQueueBanner extends StatefulWidget {
  /// Limit to one group (e.g. `inspection:358`); null shows everything.
  final String? group;
  const RentalsQueueBanner({super.key, this.group});

  @override
  State<RentalsQueueBanner> createState() => _RentalsQueueBannerState();
}

class _RentalsQueueBannerState extends State<RentalsQueueBanner> {
  final _q = RentalWriteQueue.instance;

  @override
  void initState() {
    super.initState();
    _q.addListener(_changed);
    _q.notice.addListener(_onNotice);
  }

  @override
  void dispose() {
    _q.removeListener(_changed);
    _q.notice.removeListener(_onNotice);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _onNotice() {
    final msg = _q.notice.value;
    if (msg == null || !mounted) return;
    _q.notice.value = null;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  List<QueuedRentalWrite> get _items =>
      widget.group == null ? _q.items : _q.itemsIn(widget.group!);

  @override
  Widget build(BuildContext context) {
    final items = _items;
    if (items.isEmpty) return const SizedBox.shrink();
    final failed =
        items.where((e) => e.state == QueuedWriteState.failed).length;
    final color = failed > 0 ? const Color(0xFFEF4444) : const Color(0xFFF59E0B);
    final text = failed > 0
        ? '$failed could not be sent · ${items.length - failed} waiting'
        : '${items.length} waiting to send';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Material(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => _showSheet(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                    failed > 0
                        ? TablerIcons.alert_triangle
                        : TablerIcons.cloud_upload,
                    size: 18,
                    color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(text,
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w600,
                          fontSize: 13)),
                ),
                Icon(TablerIcons.chevron_right, size: 16, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => AnimatedBuilder(
        animation: _q,
        builder: (ctx, _) {
          final items = _items;
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.7),
              child: ListView(
                shrinkWrap: true,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Text(
                      'Saved on this phone. Items send themselves when there '
                      'is signal; anything the server refused waits for you.',
                    ),
                  ),
                  if (items.isEmpty)
                    const ListTile(title: Text('Everything has been sent.')),
                  for (final e in items)
                    ListTile(
                      leading: Icon(
                        e.state == QueuedWriteState.failed
                            ? TablerIcons.alert_triangle
                            : e.state == QueuedWriteState.sending
                                ? TablerIcons.loader
                                : TablerIcons.clock,
                      ),
                      title: Text(e.label),
                      subtitle: e.error == null ? null : Text(e.error!),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Send now',
                            icon: const Icon(TablerIcons.refresh),
                            onPressed: () => _q.retry(e.id),
                          ),
                          IconButton(
                            tooltip: 'Discard',
                            icon: const Icon(TablerIcons.trash),
                            onPressed: () async {
                              final ok = await showDialog<bool>(
                                context: ctx,
                                builder: (d) => AlertDialog(
                                  title: const Text('Discard this?'),
                                  content: Text(
                                      '"${e.label}" has not reached the server. '
                                      'Discarding removes it from this phone.'),
                                  actions: [
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.pop(d, false),
                                        child: const Text('Keep')),
                                    TextButton(
                                        onPressed: () => Navigator.pop(d, true),
                                        child: const Text('Discard')),
                                  ],
                                ),
                              );
                              if (ok == true) await _q.discard(e.id);
                            },
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Snackbar text for a [SubmitOutcome]. Returns true when the server took it
/// (or it is safely queued), so a form can close.
bool showSubmitOutcome(BuildContext context, SubmitOutcome o,
    {String sentText = 'Sent.'}) {
  final messenger = ScaffoldMessenger.of(context);
  switch (o) {
    case SubmitSent():
      messenger.showSnackBar(SnackBar(content: Text(sentText)));
      return true;
    case SubmitQueued(:final reason):
      messenger.showSnackBar(SnackBar(content: Text(reason)));
      return true;
    case SubmitArchived(:final message):
      messenger.showSnackBar(SnackBar(content: Text(message)));
      return true;
    case SubmitRefused(:final error):
      messenger.showSnackBar(SnackBar(content: Text(error.message)));
      return false;
  }
}

/// Runs an online-only action, shows the server's sentence on refusal, and
/// returns the body on success (null otherwise).
Future<Map<String, dynamic>?> runAction(
  BuildContext context,
  Future<Map<String, dynamic>> Function() call, {
  String? successText,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final res = await call();
    if (successText != null) {
      messenger.showSnackBar(SnackBar(content: Text(successText)));
    }
    return res;
  } on RentalsApiException catch (e) {
    messenger.showSnackBar(SnackBar(
        content: Text(e.isNetwork
            ? 'No connection. This needs signal — please try again.'
            : e.message)));
    return null;
  }
}

// ── Contact taps ───────────────────────────────────────────────────────────

Future<void> dialPhone(String phone) async {
  final cleaned = phone.replaceAll(RegExp(r'[^0-9+]'), '');
  if (cleaned.isEmpty) return;
  await launchUrl(Uri(scheme: 'tel', path: cleaned));
}

Future<void> sendEmail(String email) async {
  if (email.trim().isEmpty) return;
  await launchUrl(Uri(scheme: 'mailto', path: email.trim()));
}

