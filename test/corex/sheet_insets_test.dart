import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:corex_mobile/utils/sheet_insets.dart';

/// Guards the bottom padding of modal sheets.
///
/// The bug this came from: an Apply button at the foot of the Properties and
/// Contacts filter sheets sat underneath the Android gesture bar, because the
/// sheets padded by `viewInsets.bottom` (the keyboard) and nothing else.
void main() {
  const gestureBar = 48.0;
  const keyboard = 300.0;

  /// Pumps [child] under a MediaQuery describing a gesture-nav device, with
  /// the keyboard optionally open. Mirrors how Flutter itself derives
  /// `padding` — viewPadding minus whatever the keyboard has covered.
  Future<double> measure(
    WidgetTester tester, {
    required bool keyboardOpen,
    required bool insideSafeArea,
  }) async {
    late double result;

    Widget probe = Builder(
      builder: (context) {
        result = sheetBottomInset(context, extra: 16);
        return const SizedBox.shrink();
      },
    );
    if (insideSafeArea) probe = SafeArea(child: probe);

    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(
          viewPadding: const EdgeInsets.only(bottom: gestureBar),
          padding: EdgeInsets.only(bottom: keyboardOpen ? 0 : gestureBar),
          viewInsets: EdgeInsets.only(bottom: keyboardOpen ? keyboard : 0),
        ),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: probe,
        ),
      ),
    );
    return result;
  }

  testWidgets('clears the gesture bar when there is no keyboard',
      (tester) async {
    final pad =
        await measure(tester, keyboardOpen: false, insideSafeArea: false);
    // The old code returned just the 16 here, which is the whole bug.
    expect(pad, gestureBar + 16);
  });

  testWidgets('clears the keyboard, without stacking the gesture bar on top',
      (tester) async {
    final pad =
        await measure(tester, keyboardOpen: true, insideSafeArea: false);
    // Not keyboard + gestureBar + 16 — the keyboard already covers that area,
    // and adding both floats the sheet above the keyboard.
    expect(pad, keyboard + 16);
  });

  testWidgets('does not double up inside a SafeArea', (tester) async {
    final pad =
        await measure(tester, keyboardOpen: false, insideSafeArea: true);
    // SafeArea has already inset the content, so the helper must add nothing
    // but the sheet's own visual padding. Reading `viewPadding` instead of
    // `padding` would return gestureBar + 16 and push the content up twice.
    expect(pad, 16);
  });

  testWidgets('still clears the keyboard inside a SafeArea', (tester) async {
    final pad = await measure(tester, keyboardOpen: true, insideSafeArea: true);
    // SafeArea consumes `padding` but never `viewInsets`, so the keyboard
    // still has to be handled here.
    expect(pad, keyboard + 16);
  });
}
