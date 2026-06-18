import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tabler_icons/tabler_icons.dart';

import '../../config/env.dart';
import '../../providers/feature_flags_provider.dart';
import '../../services/ai_api.dart';
import '../../services/api_service.dart';
import 'ai_badge.dart';

/// Driver for the AI-suggestions panel. Hold one of these alongside the
/// property edit form so newly-uploaded photos can be added to the polling
/// batch from the upload flow.
class AiSuggestionsController extends ChangeNotifier {
  final int propertyId;
  final AiApi _api = AiApi();

  AiSuggestions _data = AiSuggestions.empty;
  bool _loading = false;
  bool _polling = false;
  bool _timedOut = false;
  String? _error;
  Timer? _poll;
  DateTime? _pollStarted;
  final Set<String> _rejected = <String>{};
  final Set<String> _confirmed = <String>{};
  bool _userTouched = false;

  static const Duration _interval = Duration(seconds: 2);
  static const Duration _maxWait = Duration(seconds: 90);
  static const int _maxConsecutiveFailures = 5;
  int _consecutiveFailures = 0;

  /// Set in [dispose]. Guards every post-await `notifyListeners()` and timer
  /// scheduling so an in-flight load/poll can't touch a disposed controller
  /// (the section is torn down when the agent leaves the Spaces step while
  /// the AI features request is still outstanding).
  bool _disposed = false;

  AiSuggestionsController(this.propertyId);

  /// Notifies listeners only while still alive — a no-op once disposed.
  void _safeNotify() {
    if (_disposed) return;
    _safeNotify();
  }

  AiSuggestions get data => _data;
  bool get loading => _loading;
  bool get polling => _polling;
  bool get timedOut => _timedOut;
  String? get error => _error;

  Set<String> get confirmed => Set.unmodifiable(_confirmed);
  Set<String> get rejected => Set.unmodifiable(_rejected);

  bool isSelected(String token) => _confirmed.contains(token);

  void toggle(String token) {
    _userTouched = true;
    if (_confirmed.contains(token)) {
      _confirmed.remove(token);
      _rejected.add(token);
    } else {
      _rejected.remove(token);
      _confirmed.add(token);
    }
    _safeNotify();
  }

  /// Initial load (e.g. when opening the property edit screen with existing
  /// analyses already complete).
  Future<void> load() async {
    _loading = true;
    _error = null;
    _safeNotify();
    try {
      _data = await _api.getAiSuggestions(propertyId);
      _applyDefaultSelection();
    } on ApiException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = e.toString();
    }
    // The section may have been torn down while the request was in flight.
    if (_disposed) return;
    _loading = false;
    _safeNotify();
    if (_data.stillRunning) startPolling();
  }

  /// Kick off (or extend) polling after an upload batch finishes.
  void startPolling() {
    if (_disposed || _polling) return;
    _polling = true;
    _timedOut = false;
    _pollStarted = DateTime.now();
    _safeNotify();
    _scheduleNext();
  }

  void _scheduleNext({Duration? delay}) {
    if (_disposed) return;
    _poll?.cancel();
    _poll = Timer(delay ?? _interval, _tick);
  }

  Future<void> _tick() async {
    if (_disposed) return;
    if (_pollStarted != null &&
        DateTime.now().difference(_pollStarted!) > _maxWait) {
      _polling = false;
      _timedOut = true;
      _safeNotify();
      return;
    }
    try {
      final next = await _api.getAiSuggestions(propertyId);
      if (_disposed) return;
      _data = next;
      _consecutiveFailures = 0;
      _applyDefaultSelection();
      if (!next.stillRunning) {
        _polling = false;
        _safeNotify();
        return;
      }
    } on ApiException catch (e) {
      _error = e.message;
      _polling = false;
      _safeNotify();
      return;
    } catch (_) {
      // Transient (timeout / socket / parse). Back off exponentially and give
      // up after a cap, so a sustained outage can't hammer the endpoint every
      // _interval for the whole _maxWait window.
      _consecutiveFailures++;
      if (_consecutiveFailures >= _maxConsecutiveFailures) {
        _error = 'Could not reach the server while analysing. Pull to retry.';
        _polling = false;
        _timedOut = true;
        _safeNotify();
        return;
      }
      _safeNotify();
      _scheduleNext(delay: _interval * (1 << (_consecutiveFailures - 1)));
      return;
    }
    _safeNotify();
    _scheduleNext();
  }

  void _applyDefaultSelection() {
    if (_userTouched) return;
    // Pre-select tokens at confidence >= 0.5
    _confirmed
      ..clear()
      ..addAll(
        _data.features.where((t) => t.confidence >= 0.5).map((t) => t.token),
      );
    _rejected.clear();
  }

  /// POST `/features/merge-ai` with the current confirmed/rejected sets.
  Future<Map<String, dynamic>> apply() async {
    final confirmedList = _confirmed.toList();
    // Rejected = tokens AI suggested but user unticked.
    final suggested = _data.features.map((t) => t.token).toSet();
    final rejectedList =
        suggested.difference(_confirmed.toSet()).toList();
    return _api.mergeAiFeatures(
      propertyId,
      confirmed: confirmedList,
      rejected: rejectedList,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _poll?.cancel();
    super.dispose();
  }
}

/// Visual panel rendered between gallery and the manual features checklist.
///
/// Hidden when the image-AI flag is off OR no analyses exist yet (silent).
class AiSuggestionsSection extends StatefulWidget {
  final AiSuggestionsController controller;
  final VoidCallback? onApplied;

  const AiSuggestionsSection({
    super.key,
    required this.controller,
    this.onApplied,
  });

  @override
  State<AiSuggestionsSection> createState() => _AiSuggestionsSectionState();
}

class _AiSuggestionsSectionState extends State<AiSuggestionsSection> {
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onUpdate);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final flags = context.watch<FeatureFlagsProvider>();
    if (!flags.aiImageRecognition) return const SizedBox.shrink();

    final c = widget.controller;
    final hasContent =
        c.data.features.isNotEmpty || c.data.spaces.isNotEmpty;

    if (!c.loading && !c.polling && !hasContent && c.error == null) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AiBadge(),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'AI suggestions from your photos',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
              if (c.polling)
                const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            c.timedOut
                ? 'Still analysing — features can be reviewed on the property later.'
                : (c.polling
                    ? 'Analysing photos… (${c.data.complete}/${c.data.total} done)'
                    : 'Tap a chip to inspect or untick.'),
            style: TextStyle(
              fontSize: 12,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
            ),
          ),
          if (c.error != null) ...[
            const SizedBox(height: 8),
            Text(c.error!,
                style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
          ],
          if (c.data.features.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Features',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
                )),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: c.data.features
                  .map((t) => _FeatureChip(
                        token: t,
                        selected: c.isSelected(t.token),
                        onTap: () => c.toggle(t.token),
                        onInspect: () => _openSources(t),
                      ))
                  .toList(),
            ),
          ],
          if (c.data.spaces.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(TablerIcons.layout_grid,
                    size: 14,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
                const SizedBox(width: 4),
                Text(
                  'Spaces (advisory)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: c.data.spaces
                  .map((t) => Chip(
                        backgroundColor: theme.colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.6),
                        side: BorderSide(color: theme.dividerColor),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        label: Text(
                          '${_humanize(t.token)} · ${t.count ?? 1}',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ))
                  .toList(),
            ),
          ],
          if (c.data.features.isNotEmpty) ...[
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _applying ? null : _apply,
                icon: _applying
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(TablerIcons.sparkles, size: 16),
                label: const Text('Apply AI features'),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _apply() async {
    setState(() => _applying = true);
    try {
      await widget.controller.apply();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI features applied.')),
      );
      widget.onApplied?.call();
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 403) {
        await context.read<FeatureFlagsProvider>().refresh();
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  void _openSources(AiSuggestionToken token) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(6)),
      ),
      builder: (_) => _SourceImagesSheet(token: token),
    );
  }
}

class _FeatureChip extends StatelessWidget {
  final AiSuggestionToken token;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onInspect;

  const _FeatureChip({
    required this.token,
    required this.selected,
    required this.onTap,
    required this.onInspect,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    final base = selected
        ? accent.withValues(alpha: 0.15)
        : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4);
    return InkWell(
      onTap: onTap,
      onLongPress: onInspect,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? accent : theme.dividerColor,
            width: selected ? 1.2 : 0.6,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              selected
                  ? TablerIcons.circle_check_filled
                  : TablerIcons.circle,
              size: 14,
              color: selected ? accent : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              _humanize(token.token),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 6),
            const AiBadge(scale: 0.85),
            const SizedBox(width: 6),
            ConfidencePips(confidence: token.confidence),
            const SizedBox(width: 4),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onInspect,
              child: Icon(
                TablerIcons.eye,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceImagesSheet extends StatelessWidget {
  final AiSuggestionToken token;
  const _SourceImagesSheet({required this.token});

  String _resolveUrl(String path) {
    if (path.startsWith('http://') || path.startsWith('https://')) return path;
    final base = Env.apiBaseUrl;
    // Strip the `/api` suffix (and any trailing slash) to reach the host root
    // where Laravel serves the storage symlink.
    final host =
        base.replaceFirst(RegExp(r'/api/?$'), '').replaceAll(RegExp(r'/+$'), '');
    final rel = path.startsWith('/') ? path : '/$path';
    return '$host$rel';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                const AiBadge(),
                const SizedBox(width: 8),
                Text(
                  _humanize(token.token),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(width: 8),
                ConfidencePips(confidence: token.confidence),
              ],
            ),
            const SizedBox(height: 12),
            if (token.sources.isEmpty)
              Text(
                'No source images recorded.',
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              )
            else
              SizedBox(
                height: 120,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: token.sources.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final s = token.sources[i];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.network(
                            _resolveUrl(s.imagePath),
                            width: 110,
                            height: 90,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(
                              width: 110,
                              height: 90,
                              color: theme.colorScheme.surfaceContainerHighest,
                              alignment: Alignment.center,
                              child: const Icon(TablerIcons.photo_off, size: 24),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        ConfidencePips(confidence: s.confidence),
                      ],
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _humanize(String token) {
  return token
      .split(RegExp(r'[_\s-]+'))
      .where((p) => p.isNotEmpty)
      .map((p) => p[0].toUpperCase() + p.substring(1))
      .join(' ');
}
