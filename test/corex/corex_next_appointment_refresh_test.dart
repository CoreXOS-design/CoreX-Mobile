import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:corex_mobile/models/dashboard_data.dart';
import 'package:corex_mobile/providers/dashboard_provider.dart';
import 'package:corex_mobile/theme/corex_accent_theme.dart';
import 'package:corex_mobile/theme/corex_tokens.dart';
import 'package:corex_mobile/utils/route_observer.dart';
import 'package:corex_mobile/widgets/corex/corex_next_appointment.dart';

/// Regression: the Home "Next appointment" card used to fetch once in
/// initState and never again. Home stays mounted under anything pushed from
/// it (Ellie, Notifications, module screens), so an appointment created on
/// one of those screens never reached the card until the app was relaunched.
class _FakeDash extends DashboardProvider {
  int loads = 0;
  List<CalendarEvent> served = const [];
  List<CalendarEvent> _current = const [];

  @override
  List<CalendarEvent> get events => _current;

  @override
  Future<void> loadEventsRange(
      {required DateTime start, required DateTime end}) async {
    loads++;
    _current = served;
    notifyListeners();
  }
}

CalendarEvent _laterToday(String title) => CalendarEvent(
      id: 1,
      title: title,
      eventDate: DateTime.now().add(const Duration(hours: 3)),
    );

Widget _app(_FakeDash dash) {
  return ChangeNotifierProvider<DashboardProvider>.value(
    value: dash,
    child: MaterialApp(
      navigatorObservers: [corexRouteObserver],
      theme: ThemeData(
        brightness: Brightness.dark,
        extensions: [
          const CorexAccentTheme(
            accent: Color(0xFF0EA5E9),
            accentMoney: Color(0xFFE8B86D),
          ),
          CorexTokens.darkPalette,
        ],
      ),
      home: const Scaffold(body: CorexNextAppointment()),
    ),
  );
}

void main() {
  testWidgets('re-fetches when a route pushed over Home pops', (tester) async {
    final dash = _FakeDash();
    await tester.pumpWidget(_app(dash));
    await tester.pump();

    expect(dash.loads, 1);
    expect(find.text('Your schedule is clear for the rest of the day'),
        findsOneWidget);

    // Something on top of Home (e.g. Ellie) creates an appointment.
    dash.served = [_laterToday('Viewing at Hibiscus Road')];
    final nav = tester.state<NavigatorState>(find.byType(Navigator));
    nav.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Ellie'))));
    await tester.pumpAndSettle();
    expect(dash.loads, 1, reason: 'pushing must not fetch');

    nav.pop();
    await tester.pumpAndSettle();

    expect(dash.loads, 2);
    expect(find.text('Viewing at Hibiscus Road'), findsOneWidget);
  });

  testWidgets('re-fetches when the app returns to the foreground',
      (tester) async {
    final dash = _FakeDash();
    await tester.pumpWidget(_app(dash));
    await tester.pump();
    expect(dash.loads, 1);

    dash.served = [_laterToday('Valuation')];
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(dash.loads, 2);
    expect(find.text('Valuation'), findsOneWidget);
  });

  testWidgets('does not keep polling while idle', (tester) async {
    final dash = _FakeDash();
    await tester.pumpWidget(_app(dash));
    await tester.pump();

    // The minute tick only re-evaluates; it never hits the network.
    await tester.pump(const Duration(minutes: 5));
    expect(dash.loads, 1);
  });
}
