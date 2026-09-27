import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Bottom padding for content at the foot of a modal bottom sheet.
///
/// A modal sheet is not inside the Scaffold's [SafeArea], so nothing keeps its
/// last row clear of the system gesture bar. Padding by `viewInsets.bottom`
/// alone — which is what most of this app did — only accounts for the
/// keyboard, so an Apply/Save button at the bottom of a sheet ends up sitting
/// under the home indicator on any gesture-navigation device.
///
/// Takes the LARGER of the two insets rather than adding them: when the
/// keyboard is open it already covers the gesture area, so stacking them
/// leaves a visible gap the height of the home bar above the keyboard.
///
/// Uses [MediaQueryData.padding], not `viewPadding`, so it composes with
/// [SafeArea]. A SafeArea consumes `padding` for its descendants but leaves
/// `viewPadding` untouched — so a sheet that has both a SafeArea and this
/// helper would pad twice off `viewPadding` and sit a gesture-bar's height
/// too high. Off `padding` it reads 0 inside a SafeArea and the full inset
/// outside one, which is right either way. `padding` also drops to 0 while
/// the keyboard is up, which the max() below then covers.
///
/// [extra] is the sheet's own visual padding, applied on top.
double sheetBottomInset(BuildContext context, {double extra = 0}) {
  final mq = MediaQuery.of(context);
  return math.max(mq.viewInsets.bottom, mq.padding.bottom) + extra;
}
