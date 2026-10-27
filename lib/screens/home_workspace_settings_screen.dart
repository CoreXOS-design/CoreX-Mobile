import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/branding.dart';
import '../providers/home_workspace_provider.dart';
import '../providers/rentals_access_provider.dart';
import '../theme.dart';
import '../widgets/ui/content_width.dart';
import '../widgets/ui/icon_badge.dart';
import '../widgets/ui/section_header.dart';
import 'home/workspace_modules.dart';

/// Picks which modules appear in the Home "Workspace" grid — at least
/// [HomeWorkspaceProvider.min], at most [HomeWorkspaceProvider.max] — and the
/// order they appear in. Reached from Settings and from the settings icon
/// beside the Home heading.
class HomeWorkspaceSettingsScreen extends StatelessWidget {
  const HomeWorkspaceSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final brand = BrandColors.of(context);
    final rentals = context.watch<RentalsAccess>().staff;
    final workspace = context.watch<HomeWorkspaceProvider>();
    final shown = workspace.visible(rentals: rentals);
    final more = HomeWorkspaceProvider.available(rentals: rentals)
        .where((m) => !shown.contains(m))
        .toList();

    Widget row(WorkspaceModule m, {required bool enabled, int? dragIndex}) =>
        _ModuleRow(
          module: m,
          tint: brand.icon,
          activeColour: brand.button,
          enabled: enabled,
          dragIndex: dragIndex,
          onChanged: (v) => _toggle(context, m, v, rentals),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Home workspace')),
      body: ContentSafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(child: SectionHeader(label: 'On Home')),
                  Text(
                    '${shown.length} of ${HomeWorkspaceProvider.max}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textMuted(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _Card(
                child: ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  // Only the handle starts a drag, so a tap or a slight
                  // drag on the switch never picks the row up.
                  buildDefaultDragHandles: false,
                  itemCount: shown.length,
                  onReorder: (from, to) => context
                      .read<HomeWorkspaceProvider>()
                      .reorder(from, to, rentals: rentals),
                  // The card's gradient stays behind in the list, so the
                  // lifted row needs a surface of its own.
                  proxyDecorator: (child, _, __) => Material(
                    color: AppTheme.surface(context),
                    elevation: 6,
                    borderRadius: BorderRadius.circular(AppTheme.radius),
                    child: child,
                  ),
                  itemBuilder: (context, i) => KeyedSubtree(
                    key: ValueKey(shown[i]),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (i > 0) const _RowDivider(),
                        row(shown[i], enabled: true, dragIndex: i),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Drag to reorder. Home shows these in this order.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: AppTheme.textMuted(context),
                ),
              ),
              if (more.isNotEmpty) ...[
                const SizedBox(height: 24),
                const SectionHeader(label: 'More modules'),
                const SizedBox(height: 12),
                _Card(
                  child: Column(
                    children: [
                      for (var i = 0; i < more.length; i++) ...[
                        if (i > 0) const _RowDivider(),
                        row(more[i], enabled: false),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Choose ${HomeWorkspaceProvider.min} to '
                  '${HomeWorkspaceProvider.max} modules. Everything else '
                  'stays under Workspace → All.',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.textMuted(context),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggle(BuildContext context, WorkspaceModule module,
      bool enabled, bool rentals) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await context
        .read<HomeWorkspaceProvider>()
        .setEnabled(module, enabled, rentals: rentals);
    if (ok) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(enabled
            ? 'Home fits ${HomeWorkspaceProvider.max} — turn one off first'
            : 'Keep at least one module on Home'),
      ));
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppTheme.cardGradient(context),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        boxShadow: AppTheme.softShadow(context),
      ),
      child: child,
    );
  }
}

class _RowDivider extends StatelessWidget {
  const _RowDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
        height: 1,
        indent: 14,
        endIndent: 14,
        color: AppTheme.borderColor(context));
  }
}

class _ModuleRow extends StatelessWidget {
  final WorkspaceModule module;
  final Color tint;
  final Color activeColour;
  final bool enabled;
  final ValueChanged<bool> onChanged;

  /// Index in the reorderable "On Home" list; null for rows that can't be
  /// dragged, which then show no handle.
  final int? dragIndex;

  const _ModuleRow({
    required this.module,
    required this.tint,
    required this.activeColour,
    required this.enabled,
    required this.onChanged,
    this.dragIndex,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onChanged(!enabled),
      borderRadius: BorderRadius.circular(AppTheme.radius),
      child: Padding(
        padding: EdgeInsets.fromLTRB(dragIndex == null ? 14 : 4, 10, 14, 10),
        child: Row(
          children: [
            if (dragIndex != null)
              ReorderableDragStartListener(
                index: dragIndex!,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                  child: Icon(Icons.drag_indicator_rounded,
                      size: 20, color: AppTheme.textMuted(context)),
                ),
              ),
            IconBadge(icon: module.icon, tint: tint, size: 36, iconSize: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                module.label,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary(context),
                ),
              ),
            ),
            Switch.adaptive(
              value: enabled,
              activeTrackColor: activeColour,
              activeThumbColor: Colors.white,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
    );
  }
}
