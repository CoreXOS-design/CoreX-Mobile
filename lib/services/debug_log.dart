import 'package:flutter/foundation.dart';

/// In-memory log buffer so the splash screen can render what's happening
/// during cold-start when we can't attach `flutter logs` to a release APK.
class DebugLog {
  DebugLog._();
  static final DebugLog instance = DebugLog._();

  final ValueNotifier<List<String>> entries = ValueNotifier<List<String>>([]);

  void add(String msg) {
    final ts = DateTime.now().toIso8601String().substring(11, 23);
    final line = '$ts  $msg';
    entries.value = [...entries.value, line];
    // Also print to the dart console so `flutter logs` picks it up when attached.
    debugPrint(line);
  }

  String dump() => entries.value.join('\n');
}
