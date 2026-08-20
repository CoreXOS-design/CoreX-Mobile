import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:corex_mobile/providers/branding_provider.dart';
import 'package:corex_mobile/services/app_update_service.dart';
import 'package:corex_mobile/widgets/update_available_dialog.dart';

/// The optional update prompt exists inside an app whose standing UX rule is
/// "no intrusive auto-popups on launch". What keeps it on the right side of
/// that line is a single guarantee: **it never asks twice for the same
/// release.** These tests pin that guarantee, because the failure mode — a
/// dialog on every single launch — is the exact thing the rule was written
/// against.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('snooze silences a release, not the feature', () {
    test('a never-seen release prompts', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await AppUpdateService.shouldPromptFor(20), isTrue);
    });

    test('"Later" silences that build for good', () async {
      SharedPreferences.setMockInitialValues({});
      await AppUpdateService.snooze(20);
      expect(await AppUpdateService.shouldPromptFor(20), isFalse);
    });

    test('a newer release breaks through an earlier snooze', () async {
      SharedPreferences.setMockInitialValues({});
      await AppUpdateService.snooze(20);
      expect(await AppUpdateService.shouldPromptFor(21), isTrue,
          reason: 'dismissing one release must not opt the user out of every '
              'future release notice');
    });

    test('an older build never re-prompts after a newer snooze', () async {
      SharedPreferences.setMockInitialValues({'update_prompt_snoozed_build': 25});
      expect(await AppUpdateService.shouldPromptFor(24), isFalse);
    });
  });

  group('the dialog', () {
    const status = AppUpdateStatus(
      updateRequired: false,
      updateAvailable: true,
      updateUrl: 'https://play.google.com/store/apps/details?id=za.co.corex_mobile',
      latestBuild: 20,
      latestVersion: '1.1.0',
    );

    Widget host(Widget child) => MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => BrandingProvider()),
          ],
          child: MaterialApp(home: Scaffold(body: child)),
        );

    testWidgets('renders both a way forward and a way out', (tester) async {
      await tester.pumpWidget(host(
        const Center(child: UpdateAvailableDialog(status: status)),
      ));

      expect(find.text('Update available'), findsOneWidget);
      expect(find.textContaining('1.1.0'), findsOneWidget);
      // "Later" is not optional garnish — without it this becomes the forced
      // gate, which is a different feature with different rules.
      expect(find.text('Update now'), findsOneWidget);
      expect(find.text('Later'), findsOneWidget);
      // Two full-width buttons in an AlertDialog's action bar must stack, not
      // overflow. Any layout error would have been thrown by the pump above.
      expect(tester.takeException(), isNull);
    });

    testWidgets('falls back to the build number with no version name',
        (tester) async {
      await tester.pumpWidget(host(
        const Center(
          child: UpdateAvailableDialog(
            status: AppUpdateStatus(
              updateRequired: false,
              updateAvailable: true,
              updateUrl: 'https://example.test/app',
              latestBuild: 20,
            ),
          ),
        ),
      ));

      expect(find.textContaining('build 20'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('maybeShow stays quiet when there is nothing to announce',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      late BuildContext ctx;
      await tester.pumpWidget(host(Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      })));

      await UpdateAvailableDialog.maybeShow(ctx, AppUpdateStatus.allowed);
      await tester.pumpAndSettle();

      expect(find.text('Update available'), findsNothing);
    });

    testWidgets('maybeShow stays quiet for an already-dismissed release',
        (tester) async {
      SharedPreferences.setMockInitialValues({'update_prompt_snoozed_build': 20});
      late BuildContext ctx;
      await tester.pumpWidget(host(Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      })));

      await UpdateAvailableDialog.maybeShow(ctx, status);
      await tester.pumpAndSettle();

      expect(find.text('Update available'), findsNothing);
    });

    testWidgets('maybeShow records the release once shown', (tester) async {
      SharedPreferences.setMockInitialValues({});
      late BuildContext ctx;
      await tester.pumpWidget(host(Builder(builder: (c) {
        ctx = c;
        return const SizedBox();
      })));

      final shown = UpdateAvailableDialog.maybeShow(ctx, status);
      await tester.pumpAndSettle();
      expect(find.text('Update available'), findsOneWidget);

      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();
      await shown;

      // The whole anti-nag contract in one assertion.
      expect(await AppUpdateService.shouldPromptFor(20), isFalse);
    });
  });
}
