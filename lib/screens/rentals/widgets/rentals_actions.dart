import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:tabler_icons/tabler_icons.dart';

import '../../../services/rentals/rentals_http.dart';
import '../../../theme.dart';
import 'rentals_ui.dart';

// The online-only staff actions of the parity addendum (hfc-dash
// `.ai/specs/at-508-mobile-parity-addendum.md`): each one is the web's own
// action, so the phone shows what the server answers and decides nothing.
//
//  * 200/201 `{ok, message, warning, redirect}` → show `message`; `warning`
//    is a yellow note (the action still happened); `redirect` names the web
//    page it would have opened, which is where a new record's id is read.
//  * 422 → field errors under the fields.  409 → the web's sentence as is.
//  * 403 → no permission: the button disappears for this session.
//  * 410 → archived meanwhile.  None of these are queued: they need signal.

/// Actions the server refused with 403 this session. A button whose key is
/// here is hidden rather than shown greyed out.
class RentalsDenied {
  RentalsDenied._();
  static final ValueNotifier<Set<String>> keys = ValueNotifier(const {});

  static bool has(String? key) => key != null && keys.value.contains(key);

  static void mark(String? key) {
    if (key == null || keys.value.contains(key)) return;
    keys.value = {...keys.value, key};
  }
}

/// The id of the record a web action created, read from its `redirect`
/// (e.g. `/corex/rental-applications/57` → 57): the last number in the path.
int? idFromRedirect(Object? redirect) {
  if (redirect is! String) return null;
  final path = Uri.tryParse(redirect)?.path ?? redirect;
  final m = RegExp(r'/(\d+)(?=/|$)').allMatches(path);
  return m.isEmpty ? null : int.tryParse(m.last.group(1)!);
}

const String kNeedsSignal =
    'This needs signal. Pull down to refresh once you are connected.';

/// Shows the server's `message` and, when present, its yellow `warning`.
void showServerResult(BuildContext context, Map<String, dynamic> body,
    {String? fallback}) {
  final messenger = ScaffoldMessenger.of(context);
  final message = body.str('message') ?? fallback;
  if (message != null && message.isNotEmpty) {
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
  final warning = body.str('warning') ?? body.str('notice_warning');
  if (warning != null && warning.isNotEmpty) {
    messenger.showSnackBar(SnackBar(
      backgroundColor: const Color(0xFFF59E0B),
      duration: const Duration(seconds: 8),
      content: Text(warning, style: const TextStyle(color: Colors.black)),
    ));
  }
}

/// The plain sentence for a refusal: the server's own words, except where
/// there was no reply at all.
String refusalText(RentalsApiException e) =>
    e.isNetwork ? kNeedsSignal : e.message;

void _handleRefusal(BuildContext context, RentalsApiException e,
    {String? denyKey}) {
  if (e.statusCode == 403) RentalsDenied.mark(denyKey);
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(refusalText(e))));
}

/// Runs one online-only action: optional confirmation first, then the call.
/// Returns the server's body on success (already shown), null otherwise.
Future<Map<String, dynamic>?> runServerAction(
  BuildContext context, {
  required Future<Map<String, dynamic>> Function() call,
  String? denyKey,
  String? confirmTitle,
  String? confirmBody,
  String confirmLabel = 'Yes',
  String? successFallback,
}) async {
  if (!RentalsHttp.instance.reachable.value) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text(kNeedsSignal)));
    return null;
  }
  if (confirmTitle != null) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(confirmTitle),
        content: confirmBody == null ? null : Text(confirmBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(d, true),
              child: Text(confirmLabel)),
        ],
      ),
    );
    if (ok != true || !context.mounted) return null;
  }
  try {
    final body = await call();
    if (context.mounted) showServerResult(context, body, fallback: successFallback);
    return body;
  } on RentalsApiException catch (e) {
    if (context.mounted) _handleRefusal(context, e, denyKey: denyKey);
    return null;
  }
}

/// Downloads a server PDF (report, print-for-signature, site form) with the
/// staff token and opens it. A refusal (e.g. the web's "only once everyone
/// has signed") is shown in the server's words.
Future<void> openServerFile(BuildContext context, String path,
    {required String fileName}) async {
  final messenger = ScaffoldMessenger.of(context);
  messenger.showSnackBar(const SnackBar(content: Text('Opening…')));
  try {
    final dir = await getTemporaryDirectory();
    final f = await RentalsHttp.instance
        .download(RentalsAudience.staff, path, dir: dir, fileName: fileName);
    await OpenFilex.open(f.path);
  } on RentalsApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(refusalText(e))));
  }
}

// ── Action buttons ─────────────────────────────────────────────────────────

/// One action button: hidden once the server said 403 for [denyKey],
/// disabled while there is no signal.
class ServerActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? denyKey;
  final VoidCallback? onPressed;
  final bool danger;

  const ServerActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.denyKey,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Set<String>>(
      valueListenable: RentalsDenied.keys,
      builder: (context, denied, _) {
        if (denyKey != null && denied.contains(denyKey)) {
          return const SizedBox.shrink();
        }
        return ValueListenableBuilder<bool>(
          valueListenable: RentalsHttp.instance.reachable,
          builder: (context, online, _) => FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 44),
              foregroundColor: danger ? const Color(0xFFC41E3A) : null,
            ),
            icon: Icon(icon, size: 18),
            label: Text(label),
            onPressed: online ? onPressed : null,
          ),
        );
      },
    );
  }
}

/// A section of [ServerActionButton]s with the offline line above them.
class RentalsActionsSection extends StatelessWidget {
  final String title;
  final List<Widget> actions;
  const RentalsActionsSection(
      {super.key, this.title = 'Actions', required this.actions});

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();
    return RentalsSection(
      title: title,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ValueListenableBuilder<bool>(
            valueListenable: RentalsHttp.instance.reachable,
            builder: (context, online, _) => online
                ? const SizedBox.shrink()
                : const Padding(
                    padding: EdgeInsets.only(bottom: 10),
                    child: BodyText(kNeedsSignal, muted: true),
                  ),
          ),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      ),
    );
  }
}

// ── Forms ──────────────────────────────────────────────────────────────────

enum ActionFieldKind { text, multiline, number, date, time, choice, toggle, photo }

/// One field of an [ActionForm]: [name] is the server's field name.
class ActionField {
  final String name;
  final String label;
  final ActionFieldKind kind;
  final bool required;
  final List<(String value, String label)> options;
  final Object? initial;
  final String? help;
  final int? maxLength;

  const ActionField(
    this.name,
    this.label, {
    this.kind = ActionFieldKind.text,
    this.required = false,
    this.options = const [],
    this.initial,
    this.help,
    this.maxLength,
  });
}

/// Values of a submitted form: [values] by field name (dates `YYYY-MM-DD`,
/// times `HH:MM`, toggles bool, blanks left out); [files] photo paths.
class ActionFormValues {
  final Map<String, dynamic> values;
  final Map<String, String> files;
  const ActionFormValues(this.values, this.files);
}

/// Opens a form sheet for one web action. A 422 keeps the sheet open with
/// the server's errors under the fields; any other refusal is shown in the
/// sheet in the server's words. On success the sheet closes, the server's
/// message is shown and its body returned.
Future<Map<String, dynamic>?> showActionForm(
  BuildContext context, {
  required String title,
  required List<ActionField> fields,
  required Future<Map<String, dynamic>> Function(ActionFormValues v) submit,
  String submitLabel = 'Save',
  String? intro,
  String? denyKey,
  String? successText,
}) async {
  if (!RentalsHttp.instance.reachable.value) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text(kNeedsSignal)));
    return null;
  }
  final body = await showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ActionFormSheet(
      title: title,
      intro: intro,
      fields: fields,
      submit: submit,
      submitLabel: submitLabel,
      denyKey: denyKey,
    ),
  );
  if (body != null && context.mounted) {
    showServerResult(context, body, fallback: successText);
  }
  return body;
}

class _ActionFormSheet extends StatefulWidget {
  final String title;
  final String? intro;
  final List<ActionField> fields;
  final Future<Map<String, dynamic>> Function(ActionFormValues v) submit;
  final String submitLabel;
  final String? denyKey;

  const _ActionFormSheet({
    required this.title,
    required this.fields,
    required this.submit,
    required this.submitLabel,
    this.intro,
    this.denyKey,
  });

  @override
  State<_ActionFormSheet> createState() => _ActionFormSheetState();
}

class _ActionFormSheetState extends State<_ActionFormSheet> {
  final _text = <String, TextEditingController>{};
  final _values = <String, dynamic>{};
  final _files = <String, XFile>{};
  Map<String, String> _errors = const {};
  String? _refusal;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      switch (f.kind) {
        case ActionFieldKind.text:
        case ActionFieldKind.multiline:
        case ActionFieldKind.number:
          _text[f.name] =
              TextEditingController(text: f.initial?.toString() ?? '');
        default:
          if (f.initial != null) _values[f.name] = f.initial;
      }
    }
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _complete => widget.fields.every((f) {
        if (!f.required) return true;
        if (_text.containsKey(f.name)) return _text[f.name]!.text.trim().isNotEmpty;
        if (f.kind == ActionFieldKind.photo) return _files.containsKey(f.name);
        if (f.kind == ActionFieldKind.toggle) return _values[f.name] == true;
        return _values[f.name] != null;
      });

  Future<void> _submit() async {
    final values = <String, dynamic>{};
    for (final f in widget.fields) {
      if (_text.containsKey(f.name)) {
        final t = _text[f.name]!.text.trim();
        if (t.isNotEmpty) values[f.name] = t;
      } else if (f.kind == ActionFieldKind.toggle) {
        values[f.name] = _values[f.name] == true;
      } else if (_values[f.name] != null) {
        values[f.name] = _values[f.name];
      }
    }
    setState(() {
      _busy = true;
      _errors = const {};
      _refusal = null;
    });
    try {
      final body = await widget.submit(ActionFormValues(
          values, {for (final e in _files.entries) e.key: e.value.path}));
      if (mounted) Navigator.pop(context, body);
    } on RentalsApiException catch (e) {
      if (!mounted) return;
      if (e.statusCode == 403) RentalsDenied.mark(widget.denyKey);
      final known = widget.fields.map((f) => f.name).toSet();
      final mine = {
        for (final x in e.fieldErrors.entries)
          if (known.contains(x.key.split('.').first)) x.key.split('.').first: x.value,
      };
      setState(() {
        _busy = false;
        _errors = mine;
        // Errors about fields this form has sit under them; anything else
        // (a 409, a 403, a field the form does not show) goes on top.
        _refusal = e.statusCode == 422 && mine.length == e.fieldErrors.length
            ? null
            : refusalText(e);
      });
    }
  }

  Widget _field(ActionField f) {
    final error = _errors[f.name];
    final label = f.required ? '${f.label} *' : f.label;
    switch (f.kind) {
      case ActionFieldKind.text:
      case ActionFieldKind.multiline:
      case ActionFieldKind.number:
        return TextField(
          controller: _text[f.name],
          maxLength: f.maxLength,
          minLines: f.kind == ActionFieldKind.multiline ? 2 : 1,
          maxLines: f.kind == ActionFieldKind.multiline ? 6 : 1,
          keyboardType: f.kind == ActionFieldKind.number
              ? const TextInputType.numberWithOptions(decimal: true)
              : null,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
              labelText: label, helperText: f.help, errorText: error),
        );
      case ActionFieldKind.choice:
        return DropdownButtonFormField<String>(
          initialValue: _values[f.name] as String?,
          isExpanded: true,
          decoration: InputDecoration(
              labelText: label, helperText: f.help, errorText: error),
          items: [
            for (final o in f.options)
              DropdownMenuItem(value: o.$1, child: Text(o.$2)),
          ],
          onChanged: (v) => setState(() => _values[f.name] = v),
        );
      case ActionFieldKind.toggle:
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(label),
          subtitle: error != null
              ? Text(error, style: const TextStyle(color: Color(0xFFC41E3A)))
              : (f.help == null ? null : Text(f.help!)),
          value: _values[f.name] == true,
          onChanged: (v) => setState(() => _values[f.name] = v),
        );
      case ActionFieldKind.date:
      case ActionFieldKind.time:
        final v = _values[f.name] as String?;
        final isDate = f.kind == ActionFieldKind.date;
        return InputDecorator(
          decoration: InputDecoration(
              labelText: label, helperText: f.help, errorText: error),
          child: InkWell(
            onTap: () async {
              if (isDate) {
                final now = DateTime.now();
                final d = await showDatePicker(
                  context: context,
                  firstDate: DateTime(now.year - 5),
                  lastDate: DateTime(now.year + 5),
                  initialDate: DateTime.tryParse(v ?? '') ?? now,
                );
                if (d != null) setState(() => _values[f.name] = ymd(d));
              } else {
                final t = await showTimePicker(
                    context: context, initialTime: TimeOfDay.now());
                if (t != null) {
                  setState(() => _values[f.name] =
                      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}');
                }
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text(v == null ? 'Choose' : (isDate ? fmtDate(v) : v)),
            ),
          ),
        );
      case ActionFieldKind.photo:
        final file = _files[f.name];
        return InputDecorator(
          decoration: InputDecoration(
              labelText: label, helperText: f.help, errorText: error),
          child: InkWell(
            onTap: () async {
              final x = await PhotoPickerRow.takeOne(context);
              if (x != null) setState(() => _files[f.name] = x);
            },
            child: Row(children: [
              const Icon(TablerIcons.camera, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(file == null ? 'Take or choose a photo' : file.name)),
            ]),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.title,
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              if (widget.intro != null) ...[
                BodyText(widget.intro!, muted: true),
                const SizedBox(height: 12),
              ],
              if (_refusal != null) ...[
                RentalsAlert(_refusal!, tone: RentalsAlertTone.danger),
                const SizedBox(height: 12),
              ],
              for (final f in widget.fields) ...[
                _field(f),
                const SizedBox(height: 12),
              ],
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    backgroundColor: AppTheme.brand),
                onPressed: _busy || !_complete ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(widget.submitLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
