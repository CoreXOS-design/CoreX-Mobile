import 'package:flutter/material.dart';

import '../../theme.dart';
import 'content_width.dart';

/// One tab in a [TabbedDetailScaffold].
///
/// [children] are laid out as a padded vertical list, so a tab body is written
/// exactly the way these screens already wrote their sections — no slivers at
/// the call site.
class DetailTab {
  final String label;

  /// Shown after the label, e.g. `Drive · 27`. Null hides it; 0 is rendered,
  /// because "Matches 0" is information, not noise.
  final int? count;

  final List<Widget> children;

  const DetailTab({
    required this.label,
    this.count,
    required this.children,
  });
}

/// Detail-page shell: a collapsing hero, a pinned tab bar, and one scroll view
/// per tab.
///
/// Both the property and contact pages had grown into a single column of a
/// dozen-plus stacked sections — six phone screens of scrolling on a property,
/// with two sections (Compliance, Drive) that have no height limit at all. This
/// splits that column into tabs so each one is roughly a screen, and keeps the
/// two pages structurally identical.
///
/// Behaviour worth knowing:
///
///  * Each tab scrolls independently and **keeps its scroll position** when you
///    switch away and back, via a [PageStorageKey] on the tab's label.
///  * Pull-to-refresh works on every tab and calls the same [onRefresh]; the
///    parent owns the data, so switching tabs costs nothing and never refetches.
///  * The tab bar is pinned, so it stays reachable once the hero scrolls away.
class TabbedDetailScaffold extends StatelessWidget {
  final String title;
  final List<Widget> actions;

  /// Collapses away as the user scrolls. Must be happy at any height between
  /// its natural size and zero — [FlexibleSpaceBar] clips it during collapse.
  final Widget? hero;
  final double heroHeight;

  final List<DetailTab> tabs;
  final Future<void> Function() onRefresh;

  const TabbedDetailScaffold({
    super.key,
    required this.title,
    required this.tabs,
    required this.onRefresh,
    this.actions = const [],
    this.hero,
    this.heroHeight = 220,
  });

  /// Fixed so the header's expanded height can be computed exactly. Left to
  /// [TabBar] itself it varies with label metrics, and the hero then overflows
  /// or hides behind the tabs.
  static const double _tabBarHeight = 48;

  @override
  Widget build(BuildContext context) {
    // The controller's length can't change in place, so key it on the tab count
    // — a property that turns out to have rental inspections gains a tab and
    // gets a fresh controller instead of throwing.
    return DefaultTabController(
      key: ValueKey('tabs-${tabs.length}'),
      length: tabs.length,
      child: ContentSafeArea(
        top: false,
        child: NestedScrollView(
          headerSliverBuilder: (context, innerBoxIsScrolled) => [
            SliverOverlapAbsorber(
              handle:
                  NestedScrollView.sliverOverlapAbsorberHandleFor(context),
              sliver: SliverAppBar(
                pinned: true,
                forceElevated: innerBoxIsScrolled,
                // expandedHeight covers the toolbar row and the tab bar as well
                // as the hero, so the hero gets exactly [heroHeight].
                expandedHeight: hero == null
                    ? null
                    : heroHeight + kToolbarHeight + _tabBarHeight,
                actions: actions,
                title: Text(title, overflow: TextOverflow.ellipsis),
                flexibleSpace: hero == null
                    ? null
                    : FlexibleSpaceBar(
                        collapseMode: CollapseMode.parallax,
                        background: Padding(
                          // Clear the app bar row above and the tab bar below,
                          // so the hero never renders under either.
                          padding: EdgeInsets.only(
                            top: MediaQuery.paddingOf(context).top +
                                kToolbarHeight,
                            bottom: _tabBarHeight,
                            left: 16,
                            right: 16,
                          ),
                          child: hero,
                        ),
                      ),
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(_tabBarHeight),
                  child: TabBar(
                    isScrollable: tabs.length > 3,
                    tabAlignment: tabs.length > 3
                        ? TabAlignment.start
                        : TabAlignment.fill,
                    indicatorColor: AppTheme.brand,
                    indicatorWeight: 2.5,
                    labelColor: AppTheme.brand,
                    unselectedLabelColor: AppTheme.textSecondary(context),
                    labelStyle: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w700),
                    unselectedLabelStyle: const TextStyle(
                        fontSize: 13.5, fontWeight: FontWeight.w600),
                    tabs: [
                      for (final t in tabs)
                        Tab(
                          height: _tabBarHeight - 4,
                          text: t.count == null
                              ? t.label
                              : '${t.label} · ${t.count}',
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          body: TabBarView(
            children: [
              for (final t in tabs) _TabBody(tab: t, onRefresh: onRefresh),
            ],
          ),
        ),
      ),
    );
  }
}

class _TabBody extends StatelessWidget {
  final DetailTab tab;
  final Future<void> Function() onRefresh;

  const _TabBody({required this.tab, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    // Builder gives each tab a context beneath the NestedScrollView, which is
    // what sliverOverlapAbsorberHandleFor needs to find the handle.
    return Builder(
      builder: (context) => RefreshIndicator(
        color: AppTheme.brand,
        backgroundColor: AppTheme.surface(context),
        onRefresh: onRefresh,
        child: CustomScrollView(
          key: PageStorageKey<String>(tab.label),
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // Reserves the space the pinned header overlaps, or the first item
            // of every tab hides behind the tab bar.
            SliverOverlapInjector(
              handle: NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              sliver: SliverList(
                delegate: SliverChildListDelegate(tab.children),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
