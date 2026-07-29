import 'package:flutter/material.dart';
import '../../widgets/ui/content_width.dart';
import '../../models/contact.dart';
import '../../services/api_service.dart';
import '../../theme.dart';
import 'contact_show_screen.dart';

class NewContactScreen extends StatefulWidget {
  const NewContactScreen({super.key});

  @override
  State<NewContactScreen> createState() => _NewContactScreenState();
}

class _NewContactScreenState extends State<NewContactScreen> {
  final ApiService _api = ApiService();
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _idNumber = TextEditingController();
  final _notes = TextEditingController();

  List<ContactType> _types = const [];
  int? _typeId;
  bool _saving = false;
  bool _loadingTypes = true;
  Map<String, String> _fieldErrors = const {};

  @override
  void initState() {
    super.initState();
    _loadTypes();
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _phone.dispose();
    _email.dispose();
    _idNumber.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _loadTypes() async {
    try {
      final t = await _api.getContactOptions();
      if (!mounted) return;
      setState(() {
        _types = t;
        _loadingTypes = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingTypes = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _fieldErrors = const {};
    });
    String? s(TextEditingController c) {
      final t = c.text.trim();
      return t.isEmpty ? null : t;
    }

    final body = <String, dynamic>{
      'first_name': _firstName.text.trim(),
      'last_name': _lastName.text.trim(),
      'phone': _phone.text.trim(),
      if (s(_email) != null) 'email': s(_email),
      if (s(_idNumber) != null) 'id_number': s(_idNumber),
      if (_typeId != null) 'contact_type_id': _typeId,
      if (s(_notes) != null) 'notes': s(_notes),
    };

    try {
      final created = await _api.createContact(body);
      if (!mounted) return;
      Navigator.of(context).pop(created);
    } on DuplicateContactException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _showDuplicateDialog(e.duplicateId);
    } on ValidationException catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _fieldErrors = e.fieldErrors;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Save failed: $e')),
      );
    }
  }

  Future<void> _showDuplicateDialog(int dupId) async {
    final action = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface(context),
        title: Text('This contact already exists',
            style: TextStyle(color: AppTheme.textPrimary(context))),
        content: Text(
          'A contact with this phone or ID is already on file.',
          style: TextStyle(color: AppTheme.textSecondary(context)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('close'),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop('open'),
            child: const Text('Open contact'),
          ),
        ],
      ),
    );
    if (action == 'open' && mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ContactShowScreen(contactId: dupId)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('New Contact')),
      body: ContentSafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
          _label('First Name *'),
          _field(_firstName, 'first_name'),
          _label('Last Name *'),
          _field(_lastName, 'last_name'),
          _label('Phone *'),
          _field(_phone, 'phone', keyboard: TextInputType.phone),
          _label('Email'),
          _field(_email, 'email', keyboard: TextInputType.emailAddress),
          _label('ID Number'),
          _field(_idNumber, 'id_number'),
          _label('Contact Type'),
          if (_loadingTypes)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: LinearProgressIndicator(minHeight: 2),
            )
          else
            DropdownButtonFormField<int?>(
              initialValue: _typeId,
              isExpanded: true,
              decoration: const InputDecoration(),
              dropdownColor: AppTheme.surface(context),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('— None —'),
                ),
                ..._types.map(
                  (t) => DropdownMenuItem<int?>(value: t.id, child: Text(t.name)),
                ),
              ],
              onChanged: (v) => setState(() => _typeId = v),
            ),
          _label('Notes'),
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: InputDecoration(errorText: _fieldErrors['notes']),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Create Contact'),
            ),
          ),
          ],
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppTheme.textSecondary(context),
          ),
        ),
      );

  Widget _field(TextEditingController c, String field,
      {TextInputType? keyboard}) {
    return TextField(
      controller: c,
      keyboardType: keyboard,
      decoration: InputDecoration(errorText: _fieldErrors[field]),
      onChanged: (_) {
        if (_fieldErrors.containsKey(field)) {
          setState(() => _fieldErrors = {..._fieldErrors}..remove(field));
        }
      },
    );
  }
}
