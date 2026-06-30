import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/branding.dart';
import '../providers/dashboard_provider.dart';
import '../providers/notifications_provider.dart';
import '../theme.dart';
import '../widgets/bell_icon.dart';
import 'calendar_screen.dart';
import 'tasks_screen.dart';
import 'today/today_screen.dart';

/// App-wide 3-tab shell. After login the agent lands here on Today.
/// The legacy Inbox tab was removed when the `/dashboard` surface was
/// retired — Today's `overdue_items` card now covers that workflow.
class MainTabsScreen extends StatefulWidget {
  const MainTabsScreen({super.key});

  @override
  State<MainTabsScreen> createState() => _MainTabsScreenState();
}

class _MainTabsScreenState extends State<MainTabsScreen> {
  int _index = 0;

  static const _titles = ['Today', 'Calendar', 'Tasks'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DashboardProvider>().loadToday();
      final notes = context.read<NotificationsProvider>();
      notes.loadFeed();
      notes.loadOverdue();
    });
  }

  void _jumpTo(int i) {
    if (i != _index) HapticFeedback.selectionClick();
    setState(() => _index = i);
  }

  @override
  Widget build(BuildContext context) {
    final brand = BrandColors.of(context);

    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(
        title: Text(_titles[_index]),
        // Only show a back affordance when there's actually something to pop.
        // On a root tab destination a back arrow would eject the user from the
        // app, so suppress it (AppBar's automatic leading is also disabled).
        automaticallyImplyLeading: false,
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: Icon(Icons.arrow_back_rounded,
                    color: AppTheme.textPrimary(context)),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        actions: const [BellIcon()],
      ),
      body: IndexedStack(
        index: _index,
        children: const [
          TodayScreen(),
          CalendarScreen(embedded: true),
          TasksScreen(embedded: true),
        ],
      ),
      bottomNavigationBar: _GlowNavBar(
        index: _index,
        onTap: _jumpTo,
        accent: brand.button,
        items: const [
          _NavItem(icon: Icons.today_rounded, label: 'Today'),
          _NavItem(icon: Icons.calendar_month_rounded, label: 'Calendar'),
          _NavItem(icon: Icons.checklist_rounded, label: 'Tasks'),
        ],
      ),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}

class _GlowNavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  final Color accent;
  final List<_NavItem> items;

  const _GlowNavBar({
    required this.index,
    required this.onTap,
    required this.accent,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final muted = AppTheme.textMuted(context);
    return Container(
      padding: EdgeInsets.fromLTRB(
          12, 10, 12, MediaQuery.of(context).padding.bottom + 10),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        border: Border(
          top: BorderSide(color: AppTheme.borderColor(context)),
        ),
      ),
      child: Row(
        children: List.generate(items.length, (i) {
          final active = i == index;
          final color = active ? accent : muted;
          return Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(AppTheme.radius),
              onTap: () => onTap(i),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOut,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      decoration: BoxDecoration(
                        color: active
                            ? accent.withValues(alpha: 0.16)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: active
                            ? AppTheme.brandGlow(accent,
                                intensity: 0.35, blur: 18)
                            : null,
                      ),
                      child: Icon(items[i].icon, color: color, size: 22),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      items[i].label,
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight:
                            active ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
