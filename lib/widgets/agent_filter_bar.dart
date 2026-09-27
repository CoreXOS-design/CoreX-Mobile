import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/sheet_insets.dart';
import '../models/branding.dart';
import '../models/visibility.dart';
import '../theme.dart';

/// Agent-filter selector for the Contacts / Properties lists.
///
/// Renders nothing unless [module.canPickAgent] is true. Two rows on phones:
///   Row 1 — segmented toggle: "My {noun}" | "All {noun}"
///   Row 2 — full-width agent picker (only shown when picking a specific
///           agent is actually possible / useful).
class AgentFilterBar extends StatelessWidget {
  final ModuleVisibility module;
  final AgentFilter selected;
  final ValueChanged<AgentFilter> onChanged;
  final String noun;

  const AgentFilterBar({
    super.key,
    required this.module,
    required this.selected,
    required this.onChanged,
    required this.noun,
  });

  @override
  Widget build(BuildContext context) {
    if (!module.canPickAgent) return const SizedBox.shrink();

    final sel = selected;
    final selectedAgentId = sel is SpecificAgentFilter ? sel.agentId : null;
    final hasAgents = module.agents.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SegmentedToggle(
            options: [
              _SegmentOption(
                label: 'My $noun',
                selected: sel is MineFilter,
                onTap: () => onChanged(const MineFilter()),
              ),
              _SegmentOption(
                label: 'All $noun',
                selected: sel is AllAgentsFilter,
                onTap: () => onChanged(const AllAgentsFilter()),
              ),
            ],
          ),
          if (hasAgents) ...[
            const SizedBox(height: 8),
            _AgentPicker(
              agents: module.agents,
              selectedAgentId: selectedAgentId,
              onPicked: (id) => onChanged(SpecificAgentFilter(id)),
              onCleared: () => onChanged(const MineFilter()),
            ),
          ],
        ],
      ),
    );
  }
}

class _SegmentOption {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _SegmentOption({
    required this.label,
    required this.selected,
    required this.onTap,
  });
}

class _SegmentedToggle extends StatelessWidget {
  final List<_SegmentOption> options;
  const _SegmentedToggle({required this.options});

  @override
  Widget build(BuildContext context) {
    final brand = BrandColors.of(context);
    return Container(
      height: 40,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppTheme.surface2(context),
        borderRadius: BorderRadius.circular(AppTheme.radius),
      ),
      child: Row(
        children: [
          for (final o in options)
            Expanded(
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  o.onTap();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  decoration: BoxDecoration(
                    color: o.selected ? brand.button : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppTheme.radius - 4),
                    boxShadow: o.selected
                        ? AppTheme.brandGlow(brand.button,
                            intensity: 0.22, blur: 14, spread: -4)
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    o.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.1,
                      color: o.selected
                          ? Branding.onColor(brand.button)
                          : AppTheme.textPrimary(context),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AgentPicker extends StatelessWidget {
  final List<VisAgent> agents;
  final int? selectedAgentId;
  final ValueChanged<int> onPicked;
  final VoidCallback onCleared;

  const _AgentPicker({
    required this.agents,
    required this.selectedAgentId,
    required this.onPicked,
    required this.onCleared,
  });

  VisAgent? get _selected {
    if (selectedAgentId == null) return null;
    for (final a in agents) {
      if (a.id == selectedAgentId) return a;
    }
    return null;
  }

  Future<void> _open(BuildContext context) async {
    final picked = await showModalBottomSheet<_PickResult>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => _AgentPickerSheet(
        agents: agents,
        selectedAgentId: selectedAgentId,
      ),
    );
    if (picked == null) return;
    if (picked.cleared) {
      onCleared();
    } else if (picked.agentId != null) {
      onPicked(picked.agentId!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final brand = BrandColors.of(context);
    final picked = _selected;
    final active = picked != null;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppTheme.radius),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppTheme.radius),
        onTap: () => _open(context),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: active
                ? brand.button.withValues(alpha: 0.14)
                : AppTheme.surface2(context),
            borderRadius: BorderRadius.circular(AppTheme.radius),
            border: active
                ? Border.all(
                    color: brand.button.withValues(alpha: 0.5), width: 1)
                : null,
          ),
          child: Row(
            children: [
              Icon(Icons.person_search_rounded,
                  size: 18,
                  color:
                      active ? brand.button : AppTheme.textSecondary(context)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  picked?.name ?? 'Filter by agent',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color:
                        active ? brand.button : AppTheme.textPrimary(context),
                  ),
                ),
              ),
              if (active)
                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onCleared();
                  },
                  child: Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(Icons.close_rounded,
                        size: 18, color: brand.button),
                  ),
                )
              else
                Icon(Icons.expand_more_rounded,
                    size: 20, color: AppTheme.textMuted(context)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PickResult {
  final int? agentId;
  final bool cleared;
  const _PickResult({this.agentId, this.cleared = false});
}

class _AgentPickerSheet extends StatefulWidget {
  final List<VisAgent> agents;
  final int? selectedAgentId;

  const _AgentPickerSheet({
    required this.agents,
    required this.selectedAgentId,
  });

  @override
  State<_AgentPickerSheet> createState() => _AgentPickerSheetState();
}

class _AgentPickerSheetState extends State<_AgentPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final brand = BrandColors.of(context);
    final q = _query.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.agents
        : widget.agents.where((a) => a.name.toLowerCase().contains(q)).toList();

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 16,
            bottom: sheetBottomInset(context) + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.textMuted(context).withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Filter by agent',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: AppTheme.textPrimary(context),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  hintText: 'Search agents',
                  prefixIcon: Icon(Icons.search_rounded, size: 20),
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (_, i) {
                    final a = filtered[i];
                    final selected = a.id == widget.selectedAgentId;
                    return Material(
                      color: selected
                          ? brand.button.withValues(alpha: 0.14)
                          : AppTheme.surface2(context),
                      borderRadius: BorderRadius.circular(AppTheme.radius),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AppTheme.radius),
                        onTap: () =>
                            Navigator.pop(context, _PickResult(agentId: a.id)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  a.name,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: selected
                                        ? brand.button
                                        : AppTheme.textPrimary(context),
                                  ),
                                ),
                              ),
                              if (selected)
                                Icon(Icons.check_circle_rounded,
                                    size: 20, color: brand.button),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (widget.selectedAgentId != null) ...[
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: () =>
                      Navigator.pop(context, const _PickResult(cleared: true)),
                  icon: const Icon(Icons.close_rounded, size: 18),
                  label: const Text('Clear agent filter'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
