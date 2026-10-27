import 'package:flutter/material.dart';
import 'package:tabler_icons/tabler_icons.dart';

import '../../../services/rentals/rentals_http.dart';
import '../../../services/rentals/staff_rentals_api.dart';
import '../widgets/rentals_actions.dart';
import '../widgets/rentals_ui.dart';
import 'staff_lease_picker.dart';

// Rental applications on the phone: create the applicant, create the
// application, send it out (or hand the link over / re-issue it). That is
// all (Johan): reviewing the documents, the assessment and authorising stay
// on the web, so there is no screen for them here.

final _api = StaffRentalsApi.instance;
const _deny = 'rental_applications.create';

/// Start a rental application: applicant first, then the application, then
/// the send / share step.
Future<void> startRentalApplication(BuildContext context) async {
  final contactId = await _applicant(context);
  if (contactId == null || !context.mounted) return;
  PickedLease? property;
  final link = await showDialog<bool>(
    context: context,
    builder: (d) => AlertDialog(
      title: const Text('Link a property?'),
      content: const Text('Optional: the property the applicant is applying for.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Skip')),
        TextButton(onPressed: () => Navigator.pop(d, true), child: const Text('Choose')),
      ],
    ),
  );
  if (!context.mounted) return;
  if (link == true) {
    property = await pickLease(context);
    if (!context.mounted) return;
  }
  final r = await showActionForm(context,
      title: 'Create the application',
      denyKey: _deny,
      intro: property == null ? null : 'Property: ${property.address}',
      fields: const [
        ActionField('contact_email', 'Applicant email (to send it to)', maxLength: 150),
      ],
      submit: (v) => _api.act('POST', '/mobile/rental-applications', {
            'contact_id': contactId,
            if (property != null) 'property_id': property.propertyId,
            ...v.values,
          }));
  final id = idFromRedirect(r?.str('redirect'));
  if (id != null && context.mounted) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => RentalApplicationSendScreen(applicationId: id)));
  }
}

/// Create (or reuse) the applicant contact. The server answers a likely
/// duplicate with its candidates (422 `duplicates`, no message): the agent
/// picks one, or creates a new contact anyway.
Future<int?> _applicant(BuildContext context) async {
  ActionFormValues? last;
  Future<Json> create(ActionFormValues v, {bool bypass = false}) async {
    last = v;
    try {
      return await _api.act('POST', '/mobile/rental-applications/contacts/quick-create', {
        ...v.values,
        if (bypass) 'bypass_duplicate_check': true,
      });
    } on RentalsApiException catch (e) {
      // Not a refusal: the server is asking "is it one of these?".
      if (e.statusCode == 422 && e.body['duplicates'] is List) return e.body;
      rethrow;
    }
  }

  final r = await showActionForm(context,
      title: 'The applicant',
      denyKey: _deny,
      fields: const [
        ActionField('first_name', 'First name', required: true, maxLength: 100),
        ActionField('last_name', 'Last name', required: true, maxLength: 100),
        ActionField('phone', 'Phone', maxLength: 30),
        ActionField('email', 'Email', maxLength: 150),
      ],
      submit: create);
  if (r == null || !context.mounted) return null;
  final contact = r.obj('contact')?.integer('id');
  if (contact != null) return contact;
  final dupes = r.objs('duplicates');
  if (dupes.isEmpty) return null;
  final picked = await showModalBottomSheet<Object>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ListView(shrinkWrap: true, children: [
        const ListTile(title: Text('This may already be a contact')),
        for (final d in dupes)
          ListTile(
            leading: const Icon(TablerIcons.user),
            title: Text(d.str('name') ?? ''),
            subtitle: Text([d.str('phone'), d.str('email')]
                .whereType<String>()
                .where((e) => e.isNotEmpty)
                .join(' · ')),
            onTap: d.flag('can_view') ? () => Navigator.pop(ctx, d.integer('id')) : null,
          ),
        ListTile(
          leading: const Icon(TablerIcons.user_plus),
          title: const Text('None of these — create a new contact'),
          onTap: () => Navigator.pop(ctx, 'new'),
        ),
      ]),
    ),
  );
  if (picked is int) return picked;
  if (picked != 'new' || last == null || !context.mounted) return null;
  final again = await runServerAction(context,
      denyKey: _deny, call: () => create(last!, bypass: true));
  return again?.obj('contact')?.integer('id');
}

/// After creating: send it by email, hand the link over yourself, or
/// re-issue it. The server's sentence says what happened.
class RentalApplicationSendScreen extends StatelessWidget {
  final int applicationId;
  const RentalApplicationSendScreen({super.key, required this.applicationId});

  @override
  Widget build(BuildContext context) {
    final path = '/mobile/rental-applications/$applicationId';
    return RentalsPage(
      title: 'Rental application',
      body: ListView(
        padding: const EdgeInsets.only(top: 4, bottom: 32),
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: RentalsAlert('Reviewing the documents and authorising the '
                'application are done on the web.'),
          ),
          RentalsActionsSection(actions: [
            ServerActionButton(
              icon: TablerIcons.send,
              label: 'Send to the applicant',
              denyKey: _deny,
              onPressed: () => runServerAction(context,
                  denyKey: _deny,
                  confirmTitle: 'Email the application to the applicant?',
                  confirmLabel: 'Send',
                  call: () => _api.act('POST', '$path/send')),
            ),
            ServerActionButton(
              icon: TablerIcons.link,
              label: 'I will share the link myself',
              denyKey: _deny,
              onPressed: () => runServerAction(context,
                  denyKey: _deny, call: () => _api.act('POST', '$path/share-link')),
            ),
            ServerActionButton(
              icon: TablerIcons.refresh,
              label: 'Re-issue the link',
              denyKey: _deny,
              onPressed: () => runServerAction(context,
                  denyKey: _deny,
                  confirmTitle: 'Issue a fresh link?',
                  confirmBody: 'The old link stops working.',
                  confirmLabel: 'Re-issue',
                  call: () => _api.act('POST', '$path/reissue-link')),
            ),
          ]),
        ],
      ),
    );
  }
}
