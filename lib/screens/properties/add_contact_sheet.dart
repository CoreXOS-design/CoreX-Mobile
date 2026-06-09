import 'package:flutter/material.dart';
import '../../models/contact.dart';
import '../../services/api_service.dart';
import '../../theme.dart';

/// Bottom sheet for linking a contact to a property. Two tabs:
/// "Pick existing" (sends `contact_id`) and "New contact" (creates + links).
/// Pops `true` once a contact has been linked so the caller can refresh.
class AddContactSheet extends StatefulWidget {
  final int propertyId;
  final ApiService api;

  const AddContactSheet({
    super.key,
    required this.propertyId,
    required this.api,
  });

  /// Shows the sheet; resolves `true` when a contact was linked.
  static Future<bool> show(
    BuildContext context, {
    required int propertyId,
    required ApiService api,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddContactSheet(propertyId: propertyId, api: api),
    );
    return result == true;
  }

  @override
  State<AddContactSheet> createState() => _AddContactSheetState();
}

const List<String> _roleSuggestions = [
  'owner',
  'seller',
  'landlord',
  'lessor',
  'buyer',
  'tenant',
];

class _AddContactSheetState extends State<AddContactSheet> {
  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return DefaultTabController(
      length: 2,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.surface(context),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.9,
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppTheme.textMuted(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Add contact',
                      style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700)),
                ),
              ),
              const TabBar(
                tabs: [
                  Tab(text: 'Pick existing'),
                  Tab(text: 'New contact'),
                ],
              ),
              Flexible(
                child: TabBarView(
                  children: [
                    _PickExistingTab(
                        propertyId: widget.propertyId, api: widget.api),
                    _NewContactTab(
                        propertyId: widget.propertyId, api: widget.api),
                  ],
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

/// Shared role picker — a free-text field seeded with common suggestions.
class _RolePicker extends StatelessWidget {
  final TextEditingController controller;
  const _RolePicker({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: controller,
          maxLength: 50,
          decoration: const InputDecoration(
            labelText: 'Role (optional)',
            hintText: 'e.g. seller',
            counterText: '',
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: _roleSuggestions
              .map((r) => ActionChip(
                    label: Text(r),
                    onPressed: () => controller.text = r,
                  ))
              .toList(),
        ),
      ],
    );
  }
}

class _PickExistingTab extends StatefulWidget {
  final int propertyId;
  final ApiService api;
  const _PickExistingTab({required this.propertyId, required this.api});

  @override
  State<_PickExistingTab> createState() => _PickExistingTabState();
}

class _PickExistingTabState extends State<_PickExistingTab> {
  final _searchCtrl = TextEditingController();
  final _roleCtrl = TextEditingController();
  List<Contact> _results = [];
  Contact? _selected;
  bool _loading = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _search('');
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _roleCtrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    setState(() => _loading = true);
    try {
      final r = await widget.api.listContacts(search: q, perPage: 30);
      if (!mounted) return;
      setState(() {
        _results = r;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_msg(e))));
    }
  }

  Future<void> _link() async {
    if (_selected == null) return;
    setState(() => _submitting = true);
    try {
      await widget.api.addPropertyContact(widget.propertyId, {
        'contact_id': _selected!.id,
        if (_roleCtrl.text.trim().isNotEmpty) 'role': _roleCtrl.text.trim(),
      });
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_msg(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'Search contacts',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchCtrl.text.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchCtrl.clear();
                        _search('');
                      },
                    ),
            ),
            onChanged: (v) {
              setState(() {});
              _search(v);
            },
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _results.isEmpty
                    ? Center(
                        child: Text('No contacts found',
                            style: TextStyle(
                                color: AppTheme.textSecondary(context))))
                    : ListView.builder(
                        itemCount: _results.length,
                        itemBuilder: (_, i) {
                          final c = _results[i];
                          final sel = _selected?.id == c.id;
                          return ListTile(
                            dense: true,
                            selected: sel,
                            leading: Icon(
                              sel
                                  ? Icons.check_circle
                                  : Icons.person_outline,
                              color: sel ? AppTheme.brand : null,
                            ),
                            title: Text(c.fullName),
                            subtitle: Text([
                              if ((c.phone ?? '').isNotEmpty) c.phone,
                              if ((c.email ?? '').isNotEmpty) c.email,
                            ].whereType<String>().join('  ·  ')),
                            onTap: () => setState(() => _selected = c),
                          );
                        },
                      ),
          ),
          if (_selected != null) ...[
            const SizedBox(height: 8),
            _RolePicker(controller: _roleCtrl),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _link,
                child: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : Text('Link ${_selected!.fullName}'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _NewContactTab extends StatefulWidget {
  final int propertyId;
  final ApiService api;
  const _NewContactTab({required this.propertyId, required this.api});

  @override
  State<_NewContactTab> createState() => _NewContactTabState();
}

class _NewContactTabState extends State<_NewContactTab> {
  final _formKey = GlobalKey<FormState>();
  final _first = TextEditingController();
  final _last = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _idNumber = TextEditingController();
  final _roleCtrl = TextEditingController();
  List<ContactType> _types = [];
  int? _typeId;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _loadTypes();
  }

  @override
  void dispose() {
    for (final c in [_first, _last, _phone, _email, _idNumber, _roleCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadTypes() async {
    try {
      final t = await widget.api.getContactOptions();
      if (mounted) setState(() => _types = t);
    } catch (_) {/* type is optional — leave list empty */}
  }

  Map<String, dynamic> _body({int? linkExistingId}) => {
        if (linkExistingId != null) 'contact_id': linkExistingId,
        if (linkExistingId == null) ...{
          'first_name': _first.text.trim(),
          'last_name': _last.text.trim(),
          'phone': _phone.text.trim(),
          if (_email.text.trim().isNotEmpty) 'email': _email.text.trim(),
          if (_idNumber.text.trim().isNotEmpty)
            'id_number': _idNumber.text.trim(),
          if (_typeId != null) 'contact_type_id': _typeId,
        },
        if (_roleCtrl.text.trim().isNotEmpty) 'role': _roleCtrl.text.trim(),
      };

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    try {
      await widget.api.addPropertyContact(widget.propertyId, _body());
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on DuplicateContactException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      final link = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Contact already exists'),
          content: Text(
              '${e.message}\n\nLink the existing contact to this property instead?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel')),
            ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Link existing')),
          ],
        ),
      );
      if (link != true || !mounted) return;
      setState(() => _submitting = true);
      try {
        await widget.api.addPropertyContact(
            widget.propertyId, _body(linkExistingId: e.duplicateId));
        if (!mounted) return;
        Navigator.of(context).pop(true);
      } catch (e2) {
        if (!mounted) return;
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_msg(e2))));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_msg(e))));
    }
  }

  String? _req(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextFormField(
              controller: _first,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'First name *'),
              validator: _req,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _last,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Last name *'),
              validator: _req,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Phone *'),
              validator: _req,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _idNumber,
              decoration: const InputDecoration(labelText: 'ID number'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              initialValue: _typeId,
              isExpanded: true,
              decoration:
                  const InputDecoration(labelText: 'Contact type'),
              items: _types
                  .map((t) => DropdownMenuItem(
                      value: t.id, child: Text(t.name)))
                  .toList(),
              onChanged: (v) => setState(() => _typeId = v),
            ),
            const SizedBox(height: 10),
            _RolePicker(controller: _roleCtrl),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Create & link'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _msg(Object e) =>
    e is ApiException ? e.message : 'Something went wrong';
