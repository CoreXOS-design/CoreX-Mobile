import 'package:flutter/material.dart';

import '../../models/gallery_tags.dart';
import '../../services/api_service.dart';
import '../../theme.dart';

/// Outcome of [showAddCustomTagDialog]: the property's refreshed tag list
/// and the name the server actually filed the new tag under.
///
/// [tag] is resolved from [tags] rather than echoed from the text field
/// because the server may normalise what the agent typed (trim, casing).
/// Filing photos under the typed spelling would then 422 as an unknown tag
/// a moment after the tag was created.
class AddedCustomTag {
  final GalleryTagsData tags;
  final String tag;

  const AddedCustomTag({required this.tags, required this.tag});
}

/// The "Add custom tag" prompt, shared by the property edit screen's Custom
/// Tags manager and both gallery "File under…" pickers, so a tag can be
/// invented at the moment it is needed rather than only from the edit form.
///
/// Posts to `/gallery/tags` itself and returns `null` when dismissed;
/// validation errors stay inline in the dialog so the agent can correct the
/// name without starting over.
Future<AddedCustomTag?> showAddCustomTagDialog(
  BuildContext context, {
  required ApiService api,
  required int propertyId,
}) {
  return showDialog<AddedCustomTag>(
    context: context,
    builder: (_) => _AddCustomTagDialog(api: api, propertyId: propertyId),
  );
}

/// A widget rather than a `StatefulBuilder` closure so the text controller
/// is disposed with the dialog's own element — after the close transition
/// has finished drawing the field — instead of the moment the route pops.
class _AddCustomTagDialog extends StatefulWidget {
  final ApiService api;
  final int propertyId;

  const _AddCustomTagDialog({required this.api, required this.propertyId});

  @override
  State<_AddCustomTagDialog> createState() => _AddCustomTagDialogState();
}

class _AddCustomTagDialogState extends State<_AddCustomTagDialog> {
  final TextEditingController _controller = TextEditingController();
  String? _errorText;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final input = _controller.text.trim();
    if (input.isEmpty) {
      setState(() => _errorText = 'Tag cannot be empty');
      return;
    }
    setState(() {
      _busy = true;
      _errorText = null;
    });
    try {
      final updated = await widget.api.addGalleryTag(widget.propertyId, input);
      if (!mounted) return;
      Navigator.of(context).pop(AddedCustomTag(
        tags: updated,
        tag: _resolveTag(updated.availableTags, input),
      ));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText =
            e.statusCode == 422 && e.message.toLowerCase().contains('exist')
                ? 'Tag already exists'
                : e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _errorText = "Couldn't add tag — check your connection";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface(context),
      title: const Text('Add custom tag'),
      content: TextField(
        controller: _controller,
        maxLength: 40,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: InputDecoration(
          hintText: 'e.g. Sea View',
          errorText: _errorText,
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _busy ? null : _submit,
          // The app's button theme forces a full-width 56dp minimum, which
          // overflows an AlertDialog's action row.
          style: ElevatedButton.styleFrom(minimumSize: const Size(0, 40)),
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text('Add'),
        ),
      ],
    );
  }
}

/// The server's spelling of [input] in [available], falling back to [input]
/// itself when the list doesn't carry it (older server, or a response that
/// omitted `available_tags`).
String _resolveTag(List<String> available, String input) {
  final wanted = input.trim().toLowerCase();
  for (final t in available) {
    if (t.trim().toLowerCase() == wanted) return t;
  }
  return input;
}
