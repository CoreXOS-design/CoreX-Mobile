import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/contact.dart';
import '../../models/visibility.dart';
import '../../providers/visibility_provider.dart';
import '../../services/api_service.dart';
import '../../models/branding.dart';
import '../../theme.dart';
import '../../widgets/agent_filter_bar.dart';
import '../../widgets/ui/glow_button.dart';
import '../../widgets/ui/list_row.dart';
import '../../widgets/ui/status_chip.dart';
import 'contact_show_screen.dart';
import 'new_contact_screen.dart';

class ContactsListScreen extends StatefulWidget {
  const ContactsListScreen({super.key});

  @override
  State<ContactsListScreen> createState() => _ContactsListScreenState();
}

class _ContactsListScreenState extends State<ContactsListScreen> {
  final ApiService _api = ApiService();
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  List<Contact> _contacts = const [];
  bool _loading = true;
  String? _error;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final filter = context.read<VisibilityProvider>().contactsFilter;
      final list = await _api.listContacts(
          search: _search.isEmpty ? null : _search, agentFilter: filter);
      if (!mounted) return;
      setState(() {
        _contacts = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// Pull-to-refresh also re-pulls the visibility descriptor (per spec),
  /// which resets the filter back to Mine.
  Future<void> _refresh() async {
    await context.read<VisibilityProvider>().refresh();
    await _load();
  }

  void _onFilterChanged(AgentFilter f) {
    context.read<VisibilityProvider>().setContactsFilter(f);
    _load();
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _search = v.trim();
      _load();
    });
  }

  Future<void> _openNew() async {
    final created = await Navigator.of(context).push<Contact>(
      MaterialPageRoute(builder: (_) => const NewContactScreen()),
    );
    if (created != null && mounted) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ContactShowScreen(contactId: created.id),
        ),
      );
      await _load();
    }
  }

  void _openContact(int id) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ContactShowScreen(contactId: id)),
    ).then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Contacts')),
      floatingActionButton: _GlowFab(onPressed: _openNew),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search contacts…',
                prefixIcon:
                    Icon(Icons.search_rounded, color: AppTheme.textMuted(context)),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchCtrl.clear();
                          _onSearchChanged('');
                        },
                      )
                    : null,
              ),
            ),
          ),
          AgentFilterBar(
            noun: 'Contacts',
            module: context.watch<VisibilityProvider>().contacts,
            selected: context.watch<VisibilityProvider>().contactsFilter,
            onChanged: _onFilterChanged,
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: _buildList(),
            ),
          ),
          ],
        ),
      ),
    );
  }

  Widget _buildList() {
    if (_loading && _contacts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _contacts.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          EmptyState(
            icon: Icons.error_outline_rounded,
            title: 'Could not load contacts',
            subtitle: _error,
            action: SizedBox(
              width: 180,
              child: GlowButton(
                  onPressed: _load, child: const Text('Retry')),
            ),
          ),
        ],
      );
    }
    if (_contacts.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          EmptyState(
            icon: Icons.person_add_alt_1_rounded,
            title: _search.isEmpty ? 'No contacts yet' : 'No matches',
            subtitle: _search.isEmpty
                ? 'Tap + to add your first contact.'
                : 'No contacts match "$_search".',
          ),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _contacts.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, i) => _tile(_contacts[i]),
    );
  }

  Widget _tile(Contact c) {
    final brand = BrandColors.of(context);
    return ListRow(
      onTap: () => _openContact(c.id),
      leading: CircleAvatar(
        radius: 20,
        backgroundColor: brand.defaultColor,
        child: Text(
          _initials(c.fullName),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: Branding.onColor(brand.defaultColor),
          ),
        ),
      ),
      title: c.fullName,
      subtitle: c.phone?.isNotEmpty == true ? c.phone : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (c.contactTypeName != null && c.contactTypeName!.isNotEmpty) ...[
            StatusChip(label: c.contactTypeName!, color: brand.button, dense: true),
            const SizedBox(width: 6),
          ],
          if (c.whatsappCount > 0)
            StatusChip(
              label: '${c.whatsappCount}',
              color: const Color(0xFF22C55E),
              icon: Icons.chat_rounded,
              dense: true,
            ),
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts.first.isNotEmpty && parts.last.isNotEmpty) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}

class _GlowFab extends StatelessWidget {
  final VoidCallback onPressed;
  const _GlowFab({required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final brand = BrandColors.of(context);
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: AppTheme.brandGlow(brand.button, intensity: 0.35),
      ),
      child: FloatingActionButton(
        backgroundColor: brand.button,
        foregroundColor: Branding.onColor(brand.button),
        onPressed: onPressed,
        elevation: 0,
        child: const Icon(Icons.add_rounded),
      ),
    );
  }
}
