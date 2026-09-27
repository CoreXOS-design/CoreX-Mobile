import 'dart:async';
import 'package:flutter/material.dart';
import '../../utils/sheet_insets.dart';
import '../../models/calendar_form.dart' show AttendeeSearchResult;
import '../../models/contact_notes_testimonials.dart';
import '../../services/api_service.dart';
import '../../theme.dart';
import '../../utils/app_time.dart';

const Color _kDanger = Color(0xFFDC2626);
const Color _kStar = Color(0xFFF59E0B);

/// Embedded Notes & Testimonials section for the Contact detail screen — full
/// parity with the web cockpit's "Notes & Testimonials" contact tab. Both
/// clients write to the same DB rows via the same endpoints, so there is no
/// client-side merge logic: [refresh] just re-fetches.
///
/// Self-contained: fetches its own data on mount and manages its own
/// optimistic add/edit/delete. The host screen drives pull-to-refresh by
/// calling [refresh] (via a [GlobalKey]) from its own reload.
class ContactNotesTestimonialsSection extends StatefulWidget {
  final int contactId;
  final ApiService api;

  const ContactNotesTestimonialsSection({
    super.key,
    required this.contactId,
    required this.api,
  });

  @override
  State<ContactNotesTestimonialsSection> createState() =>
      ContactNotesTestimonialsSectionState();
}

class ContactNotesTestimonialsSectionState
    extends State<ContactNotesTestimonialsSection> {
  bool _loading = true;
  String? _error;

  /// Flips false the moment any write 403s — the assistant-narrower-than-view
  /// case (contact visible, not editable). Add/Edit/Delete disable rather than
  /// keep retrying; a fresh mount/refresh gives it another chance.
  bool _canEdit = true;

  List<ContactNote> _notes = [];
  List<ContactTestimonial> _testimonials = [];

  /// Negative, decrementing ids for optimistic entries — never collide with a
  /// real server id.
  int _nextTempId = -1;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    var canEdit = true;
    var notes = _notes;
    var testimonials = _testimonials;
    String? error;

    try {
      notes = await widget.api.getContactNotes(widget.contactId);
    } on ApiException catch (e) {
      if (e.statusCode == 403) {
        canEdit = false;
        notes = const [];
      } else {
        error = e.message;
      }
    } catch (e) {
      error = e.toString();
    }

    try {
      testimonials = await widget.api.getContactTestimonials(widget.contactId);
    } on ApiException catch (e) {
      if (e.statusCode == 403) {
        canEdit = false;
        testimonials = const [];
      } else {
        error ??= e.message;
      }
    } catch (e) {
      error ??= e.toString();
    }

    if (!mounted) return;
    setState(() {
      _notes = notes;
      _testimonials = testimonials;
      _canEdit = canEdit;
      _error = error;
      _loading = false;
    });
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // --- Notes ---

  Future<void> _addNote() async {
    final result = await showModalBottomSheet<Map<String, String?>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _NoteFormSheet(),
    );
    if (result == null || !mounted) return;

    final type = result['type'];
    final body = result['body'];
    final tempId = _nextTempId--;
    final optimistic = ContactNote(
      id: tempId,
      contactId: widget.contactId,
      type: type,
      body: (body == null || body.isEmpty) ? null : body,
      userId: 0,
      userName: 'You',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    setState(() => _notes = [optimistic, ..._notes]);

    try {
      final created = await widget.api
          .createContactNote(widget.contactId, type: type, body: body);
      if (!mounted) return;
      setState(
          () => _notes = [created, ..._notes.where((n) => n.id != tempId)]);
    } on ContactSubresourceStaleException {
      if (!mounted) return;
      setState(() => _notes = _notes.where((n) => n.id != tempId).toList());
      _toast('This contact could not be found — refreshing.');
      await refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _notes = _notes.where((n) => n.id != tempId).toList();
        if (e.statusCode == 403) _canEdit = false;
      });
      _toast(e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _notes = _notes.where((n) => n.id != tempId).toList());
      _toast('Could not add note: $e');
    }
  }

  Future<void> _editNote(ContactNote n) async {
    final result = await showModalBottomSheet<Map<String, String?>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NoteFormSheet(initialType: n.type, initialBody: n.body),
    );
    if (result == null || !mounted) return;

    final type = result['type'];
    final body = result['body'];
    final updated = ContactNote(
      id: n.id,
      contactId: n.contactId,
      type: type,
      body: (body == null || body.isEmpty) ? null : body,
      userId: n.userId,
      userName: n.userName,
      createdAt: n.createdAt,
      updatedAt: DateTime.now(),
    );
    setState(
        () => _notes = _notes.map((x) => x.id == n.id ? updated : x).toList());

    try {
      final saved = await widget.api
          .updateContactNote(widget.contactId, n.id, type: type, body: body);
      if (!mounted) return;
      setState(
          () => _notes = _notes.map((x) => x.id == n.id ? saved : x).toList());
    } on ContactSubresourceStaleException {
      if (!mounted) return;
      setState(() => _notes = _notes.map((x) => x.id == n.id ? n : x).toList());
      _toast('This note is out of date — refreshing.');
      await refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _notes = _notes.map((x) => x.id == n.id ? n : x).toList();
        if (e.statusCode == 403) _canEdit = false;
      });
      _toast(e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _notes = _notes.map((x) => x.id == n.id ? n : x).toList());
      _toast('Could not update note: $e');
    }
  }

  Future<void> _deleteNote(ContactNote n) async {
    final confirmed = await _confirmDelete('note');
    if (confirmed != true || !mounted) return;

    final prev = _notes;
    setState(() => _notes = _notes.where((x) => x.id != n.id).toList());
    try {
      await widget.api.deleteContactNote(widget.contactId, n.id);
    } on ContactSubresourceStaleException {
      _toast('Already removed.');
      await refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _notes = prev;
        if (e.statusCode == 403) _canEdit = false;
      });
      _toast(e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _notes = prev);
      _toast('Could not delete note: $e');
    }
  }

  // --- Testimonials ---

  Future<void> _addTestimonial() async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TestimonialFormSheet(api: widget.api),
    );
    if (result == null || !mounted) return;

    final body = result['body'] as String;
    final displayName = result['displayName'] as String?;
    final rating = result['rating'] as int?;
    final agentId = result['agentId'] as int?;
    final agentName = result['agentName'] as String?;
    final tempId = _nextTempId--;
    final optimistic = ContactTestimonial(
      id: tempId,
      contactId: widget.contactId,
      body: body,
      displayName: displayName,
      rating: rating,
      agentId: agentId,
      agentName: agentName,
      userId: 0,
      userName: 'You',
      published: false,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    setState(() => _testimonials = [optimistic, ..._testimonials]);

    try {
      final created = await widget.api.createContactTestimonial(
        widget.contactId,
        body: body,
        displayName: displayName,
        rating: rating,
        agentId: agentId,
      );
      if (!mounted) return;
      setState(() => _testimonials = [
            created,
            ..._testimonials.where((t) => t.id != tempId)
          ]);
    } on ContactSubresourceStaleException {
      if (!mounted) return;
      setState(() =>
          _testimonials = _testimonials.where((t) => t.id != tempId).toList());
      _toast('This contact could not be found — refreshing.');
      await refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _testimonials = _testimonials.where((t) => t.id != tempId).toList();
        if (e.statusCode == 403) _canEdit = false;
      });
      _toast(e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() =>
          _testimonials = _testimonials.where((t) => t.id != tempId).toList());
      _toast('Could not add testimonial: $e');
    }
  }

  Future<void> _editTestimonial(ContactTestimonial t) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TestimonialFormSheet(
        api: widget.api,
        initialBody: t.body,
        initialDisplayName: t.displayName,
        initialRating: t.rating,
        initialAgentId: t.agentId,
        initialAgentName: t.agentName,
      ),
    );
    if (result == null || !mounted) return;

    final body = result['body'] as String;
    final displayName = result['displayName'] as String?;
    final rating = result['rating'] as int?;
    final agentId = result['agentId'] as int?;
    final agentName = result['agentName'] as String?;
    final updated = ContactTestimonial(
      id: t.id,
      contactId: t.contactId,
      body: body,
      displayName: displayName,
      rating: rating,
      agentId: agentId,
      agentName: agentName,
      userId: t.userId,
      userName: t.userName,
      published: t.published,
      createdAt: t.createdAt,
      updatedAt: DateTime.now(),
    );
    setState(() => _testimonials =
        _testimonials.map((x) => x.id == t.id ? updated : x).toList());

    try {
      final saved = await widget.api.updateContactTestimonial(
        widget.contactId,
        t.id,
        body: body,
        displayName: displayName,
        rating: rating,
        agentId: agentId,
      );
      if (!mounted) return;
      setState(() => _testimonials =
          _testimonials.map((x) => x.id == t.id ? saved : x).toList());
    } on ContactSubresourceStaleException {
      if (!mounted) return;
      setState(() => _testimonials =
          _testimonials.map((x) => x.id == t.id ? t : x).toList());
      _toast('This testimonial is out of date — refreshing.');
      await refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _testimonials = _testimonials.map((x) => x.id == t.id ? t : x).toList();
        if (e.statusCode == 403) _canEdit = false;
      });
      _toast(e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _testimonials =
          _testimonials.map((x) => x.id == t.id ? t : x).toList());
      _toast('Could not update testimonial: $e');
    }
  }

  Future<void> _deleteTestimonial(ContactTestimonial t) async {
    final confirmed = await _confirmDelete('testimonial');
    if (confirmed != true || !mounted) return;

    final prev = _testimonials;
    setState(() =>
        _testimonials = _testimonials.where((x) => x.id != t.id).toList());
    try {
      await widget.api.deleteContactTestimonial(widget.contactId, t.id);
    } on ContactSubresourceStaleException {
      _toast('Already removed.');
      await refresh();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _testimonials = prev;
        if (e.statusCode == 403) _canEdit = false;
      });
      _toast(e.message);
    } catch (e) {
      if (!mounted) return;
      setState(() => _testimonials = prev);
      _toast('Could not delete testimonial: $e');
    }
  }

  Future<bool?> _confirmDelete(String noun) => showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Delete $noun?'),
          content: const Text('This cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Delete', style: TextStyle(color: _kDanger)),
            ),
          ],
        ),
      );

  // --- Build ---

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_error != null) _errorBanner(),
        if (!_canEdit) _permissionBanner(),
        _heading('Notes'),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _canEdit ? _addNote : null,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add Note'),
          ),
        ),
        const SizedBox(height: 12),
        if (_notes.isEmpty)
          _emptyHint('No notes yet.')
        else
          ..._notes.map(_noteTile),
        const SizedBox(height: 24),
        _heading('Testimonials'),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _canEdit ? _addTestimonial : null,
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Add Testimonial'),
          ),
        ),
        const SizedBox(height: 12),
        if (_testimonials.isEmpty)
          _emptyHint('No testimonials yet.')
        else
          ..._testimonials.map(_testimonialTile),
      ],
    );
  }

  Widget _heading(String text) => Text(
        text,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: AppTheme.textPrimary(context),
        ),
      );

  Widget _emptyHint(String text) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
        decoration: BoxDecoration(
          color: AppTheme.surface(context),
          borderRadius: BorderRadius.circular(AppTheme.radius),
          border: Border.all(color: AppTheme.borderColor(context)),
        ),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style:
              TextStyle(fontSize: 13, color: AppTheme.textSecondary(context)),
        ),
      );

  Widget _errorBanner() => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _kDanger.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppTheme.radius),
          border: Border.all(color: _kDanger.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(_error!,
                  style: const TextStyle(fontSize: 12, color: _kDanger)),
            ),
            TextButton(onPressed: refresh, child: const Text('Retry')),
          ],
        ),
      );

  Widget _permissionBanner() => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFB45309).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(AppTheme.radius),
        ),
        child: const Text(
          "You don't have permission to edit this contact.",
          style: TextStyle(fontSize: 12, color: Color(0xFFB45309)),
        ),
      );

  Widget _pill(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w600, color: color),
        ),
      );

  Widget _noteTile(ContactNote n) {
    final rel = relativeTime(n.createdAt.toIso8601String());
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  n.userName.isNotEmpty ? n.userName : 'Unknown',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
              ),
              if (rel != null)
                Text(rel,
                    style: TextStyle(
                        fontSize: 11, color: AppTheme.textMuted(context))),
            ],
          ),
          if (n.type != null) ...[
            const SizedBox(height: 6),
            _pill(n.type!, AppTheme.brand),
          ],
          if (n.body != null && n.body!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(n.body!,
                style: TextStyle(
                    fontSize: 13, color: AppTheme.textPrimary(context))),
          ],
          if (_canEdit) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                    onPressed: () => _editNote(n), child: const Text('Edit')),
                TextButton(
                  onPressed: () => _deleteNote(n),
                  child:
                      const Text('Delete', style: TextStyle(color: _kDanger)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _testimonialTile(ContactTestimonial t) {
    final rel = relativeTime(t.createdAt.toIso8601String());
    final meta = [
      'By ${t.userName.isNotEmpty ? t.userName : 'Unknown'}',
      if (rel != null) rel,
      if (t.agentName != null && t.agentName!.isNotEmpty)
        'About ${t.agentName}',
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: BorderRadius.circular(AppTheme.radius),
        border: Border.all(color: AppTheme.borderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  t.displayName?.isNotEmpty == true
                      ? t.displayName!
                      : 'Anonymous',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _pill('Not published', AppTheme.textMuted(context)),
            ],
          ),
          if (t.rating != null) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                for (var i = 1; i <= 5; i++)
                  Icon(
                    t.rating! >= i
                        ? Icons.star_rounded
                        : Icons.star_border_rounded,
                    size: 14,
                    color: _kStar,
                  ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          Text(t.body,
              style: TextStyle(
                  fontSize: 13, color: AppTheme.textPrimary(context))),
          const SizedBox(height: 6),
          Text(meta,
              style:
                  TextStyle(fontSize: 11, color: AppTheme.textMuted(context))),
          if (_canEdit) ...[
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                    onPressed: () => _editTestimonial(t),
                    child: const Text('Edit')),
                TextButton(
                  onPressed: () => _deleteTestimonial(t),
                  child:
                      const Text('Delete', style: TextStyle(color: _kDanger)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Add/Edit sheet for a note: a body textarea plus the fixed quick-pick type
/// chips. Pops `{'type': String?, 'body': String?}`, or null on cancel.
class _NoteFormSheet extends StatefulWidget {
  final String? initialType;
  final String? initialBody;

  const _NoteFormSheet({this.initialType, this.initialBody});

  @override
  State<_NoteFormSheet> createState() => _NoteFormSheetState();
}

class _NoteFormSheetState extends State<_NoteFormSheet> {
  late String? _type = widget.initialType;
  late final TextEditingController _body =
      TextEditingController(text: widget.initialBody ?? '');

  @override
  void dispose() {
    _body.dispose();
    super.dispose();
  }

  bool get _valid =>
      (_type != null && _type!.isNotEmpty) || _body.text.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initialType != null || widget.initialBody != null;
    return Padding(
      padding: EdgeInsets.only(bottom: sheetBottomInset(context)),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    isEdit ? 'Edit note' : 'Add note',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary(context),
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: Icon(Icons.close,
                        color: AppTheme.textSecondary(context)),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in kContactNoteTypes)
                    ChoiceChip(
                      label: Text(t),
                      selected: _type == t,
                      onSelected: (sel) =>
                          setState(() => _type = sel ? t : null),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _body,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(hintText: 'What happened?'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton(
                  onPressed: _valid
                      ? () => Navigator.of(context)
                          .pop({'type': _type, 'body': _body.text.trim()})
                      : null,
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Add/Edit sheet for a testimonial. Pops a map with `body` (String, always
/// present), `displayName`, `rating`, `agentId`, `agentName` — or null on
/// cancel.
class _TestimonialFormSheet extends StatefulWidget {
  final ApiService api;
  final String? initialBody;
  final String? initialDisplayName;
  final int? initialRating;
  final int? initialAgentId;
  final String? initialAgentName;

  const _TestimonialFormSheet({
    required this.api,
    this.initialBody,
    this.initialDisplayName,
    this.initialRating,
    this.initialAgentId,
    this.initialAgentName,
  });

  @override
  State<_TestimonialFormSheet> createState() => _TestimonialFormSheetState();
}

class _TestimonialFormSheetState extends State<_TestimonialFormSheet> {
  late final TextEditingController _body =
      TextEditingController(text: widget.initialBody ?? '');
  late final TextEditingController _displayName =
      TextEditingController(text: widget.initialDisplayName ?? '');
  int? _rating;
  int? _agentId;
  String? _agentName;

  @override
  void initState() {
    super.initState();
    _rating = widget.initialRating;
    _agentId = widget.initialAgentId;
    _agentName = widget.initialAgentName;
  }

  @override
  void dispose() {
    _body.dispose();
    _displayName.dispose();
    super.dispose();
  }

  bool get _valid => _body.text.trim().isNotEmpty;

  Future<void> _pickAgent() async {
    final result = await showModalBottomSheet<AttendeeSearchResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AgentPickerSheet(api: widget.api),
    );
    if (result == null || !mounted) return;
    setState(() {
      _agentId = result.id;
      _agentName = result.name;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.initialBody != null;
    return Padding(
      padding: EdgeInsets.only(bottom: sheetBottomInset(context)),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface(context),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        ),
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.85),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      isEdit ? 'Edit testimonial' : 'Add testimonial',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: Icon(Icons.close,
                          color: AppTheme.textSecondary(context)),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                _StarPicker(
                    rating: _rating,
                    onChanged: (r) => setState(() => _rating = r)),
                const SizedBox(height: 12),
                TextField(
                  controller: _body,
                  minLines: 2,
                  maxLines: 5,
                  decoration:
                      const InputDecoration(hintText: 'What did they say?'),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _displayName,
                  decoration: const InputDecoration(
                      hintText: 'Display name (optional)'),
                ),
                const SizedBox(height: 12),
                _agentId == null
                    ? SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _pickAgent,
                          icon: const Icon(Icons.badge_outlined, size: 16),
                          label: const Text('About which agent (optional)'),
                        ),
                      )
                    : Align(
                        alignment: Alignment.centerLeft,
                        child: Chip(
                          label: Text(_agentName ?? 'Agent'),
                          onDeleted: () => setState(() {
                            _agentId = null;
                            _agentName = null;
                          }),
                        ),
                      ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    onPressed: _valid
                        ? () => Navigator.of(context).pop({
                              'body': _body.text.trim(),
                              'displayName': _displayName.text.trim().isEmpty
                                  ? null
                                  : _displayName.text.trim(),
                              'rating': _rating,
                              'agentId': _agentId,
                              'agentName': _agentName,
                            })
                        : null,
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StarPicker extends StatelessWidget {
  final int? rating;
  final ValueChanged<int?> onChanged;

  const _StarPicker({required this.rating, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 1; i <= 5; i++)
          IconButton(
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            icon: Icon(
              (rating ?? 0) >= i
                  ? Icons.star_rounded
                  : Icons.star_border_rounded,
              color: (rating ?? 0) >= i ? _kStar : AppTheme.textMuted(context),
            ),
            // Tapping the currently-selected star clears the rating.
            onPressed: () => onChanged(rating == i ? null : i),
          ),
      ],
    );
  }
}

/// Debounced agent search (300ms, min 2 chars) reusing the same
/// `/calendar/search/attendees` endpoint the add-event flow uses, filtered to
/// agents only. Scoped server-side to the agent's own visibility, so this
/// already only offers agents the picker should show.
class _AgentPickerSheet extends StatefulWidget {
  final ApiService api;
  const _AgentPickerSheet({required this.api});

  @override
  State<_AgentPickerSheet> createState() => _AgentPickerSheetState();
}

class _AgentPickerSheetState extends State<_AgentPickerSheet> {
  final _controller = TextEditingController();
  Timer? _debounce;
  int _reqSeq = 0;

  List<AttendeeSearchResult> _items = const [];
  bool _loading = false;
  bool _searched = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String q) {
    _debounce?.cancel();
    final text = q.trim();
    if (text.length < 2) {
      setState(() {
        _items = const [];
        _loading = false;
        _searched = false;
        _error = null;
      });
      return;
    }
    setState(() => _loading = true);
    _debounce = Timer(const Duration(milliseconds: 300), () => _query(text));
  }

  Future<void> _query(String q) async {
    final reqId = ++_reqSeq;
    try {
      final results = await widget.api.searchAttendees(q);
      if (!mounted || reqId != _reqSeq) return;
      setState(() {
        _items = results.where((r) => r.isAgent).toList();
        _loading = false;
        _searched = true;
        _error = null;
      });
    } catch (e) {
      if (!mounted || reqId != _reqSeq) return;
      setState(() {
        _loading = false;
        _searched = true;
        _error = 'Search failed. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
      padding: EdgeInsets.only(bottom: sheetBottomInset(context)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
            child: Row(
              children: [
                Text(
                  'About which agent',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary(context),
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon:
                      Icon(Icons.close, color: AppTheme.textSecondary(context)),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              controller: _controller,
              autofocus: true,
              onChanged: _onChanged,
              decoration: const InputDecoration(
                hintText: 'Search agents…',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Flexible(child: _results()),
        ],
      ),
    );
  }

  Widget _results() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) return _hint(_error!);
    if (!_searched) return _hint('Type at least 2 characters to search.');
    if (_items.isEmpty) return _hint('No agents found.');
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
      itemCount: _items.length,
      separatorBuilder: (_, __) =>
          Divider(height: 1, color: AppTheme.borderColor(context)),
      itemBuilder: (context, i) {
        final a = _items[i];
        return ListTile(
          title: Text(a.name),
          onTap: () => Navigator.of(context).pop(a),
        );
      },
    );
  }

  Widget _hint(String text) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        child: Center(
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: AppTheme.textMuted(context)),
          ),
        ),
      );
}
