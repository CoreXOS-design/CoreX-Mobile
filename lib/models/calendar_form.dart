// Models backing the full "Add / Edit Event" calendar flow.
//
// These mirror the `/api/v1/command-center/calendar/*` add-event API at parity
// with the web cockpit. They're intentionally separate from `CalendarEvent`
// (which models the read-only month/day feed): the form needs the richer
// picker payloads (event classes, property/attendee search results, property
// owners) and a mutable working-state shape for selected attendees.
import 'dart:convert';

int? _asInt(dynamic v) =>
    v is int ? v : (v is num ? v.toInt() : int.tryParse(v?.toString() ?? ''));

String _asString(dynamic v) => v?.toString() ?? '';

bool _asBool(dynamic v) => v == true || v == 1 || v == '1' || v == 'true';

/// One selectable event class from `GET .../calendar/options`.
class EventClassOption {
  final String eventClass; // submitted as `category`
  final String label;
  final bool allowMultipleProperties;
  final String? actorRole;
  final String? completionBehaviour;

  const EventClassOption({
    required this.eventClass,
    required this.label,
    this.allowMultipleProperties = true,
    this.actorRole,
    this.completionBehaviour,
  });

  factory EventClassOption.fromJson(Map<String, dynamic> json) {
    // The backend's `calendarOptions` keys the class as `value`; older/parity
    // shapes use `event_class`. Accept either so the picker never comes up empty.
    final cls = _asString(json['event_class']).isNotEmpty
        ? _asString(json['event_class'])
        : _asString(json['value']);
    return EventClassOption(
      eventClass: cls,
      label: _asString(json['label']).isNotEmpty
          ? _asString(json['label'])
          : cls,
      // Default to true so an unknown/missing flag never silently blocks the
      // multi-property picker — the backend also caps single-property classes.
      allowMultipleProperties: json['allow_multiple_properties'] == null
          ? true
          : _asBool(json['allow_multiple_properties']),
      actorRole: json['actor_role']?.toString(),
      completionBehaviour: json['completion_behaviour']?.toString(),
    );
  }
}

/// A selectable attendee role from `GET .../calendar/options`.
class AttendeeRoleOption {
  final String key;
  final String label;

  const AttendeeRoleOption({required this.key, required this.label});

  factory AttendeeRoleOption.fromJson(Map<String, dynamic> json) {
    final key = _asString(json['key']);
    return AttendeeRoleOption(
      key: key,
      label: _asString(json['label']).isNotEmpty ? _asString(json['label']) : key,
    );
  }
}

/// Bootstrap payload for the add-event form.
class CalendarOptions {
  final List<EventClassOption> classes;
  final List<String> priorities;
  final List<AttendeeRoleOption> attendeeRoles;

  const CalendarOptions({
    this.classes = const [],
    this.priorities = const ['low', 'normal', 'high', 'critical'],
    this.attendeeRoles = const [],
  });

  /// Contact roles the backend accepts on create when the server doesn't ship
  /// its own `attendee_roles` list. Mirrors the create validator's enum
  /// (`attendee`, `buyer_contact`, `seller_contact`); `agent_contact` is
  /// auto-assigned server-side for agents and never offered for contacts.
  static const List<AttendeeRoleOption> defaultAttendeeRoles = [
    AttendeeRoleOption(key: 'attendee', label: 'Attendee'),
    AttendeeRoleOption(key: 'buyer_contact', label: 'Buyer'),
    AttendeeRoleOption(key: 'seller_contact', label: 'Seller'),
  ];

  factory CalendarOptions.fromJson(Map<String, dynamic> json) {
    final priorities = (json['priorities'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const ['low', 'normal', 'high', 'critical'];
    // The backend emits `categories`; parity/older shapes use `classes`.
    final rawClasses = (json['classes'] ?? json['categories']) as List? ?? const [];
    final roles = (json['attendee_roles'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => AttendeeRoleOption.fromJson(Map<String, dynamic>.from(e)))
        .toList();
    return CalendarOptions(
      classes: rawClasses
          .whereType<Map>()
          .map((e) => EventClassOption.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      priorities: priorities.isEmpty
          ? const ['low', 'normal', 'high', 'critical']
          : priorities,
      // Fall back to the built-in set when the server omits roles, so the
      // contact-role picker still works instead of silently disappearing.
      attendeeRoles: roles.isEmpty ? defaultAttendeeRoles : roles,
    );
  }
}

/// A property hit from `GET /v1/mobile/properties?q=`.
class PropertySearchResult {
  final int id;
  final String address;
  final String? priceDisplay;
  final String? thumbnail;
  final int? beds;
  final num? baths;

  const PropertySearchResult({
    required this.id,
    required this.address,
    this.priceDisplay,
    this.thumbnail,
    this.beds,
    this.baths,
  });

  factory PropertySearchResult.fromJson(Map<String, dynamic> json) {
    return PropertySearchResult(
      id: _asInt(json['id']) ?? 0,
      address: _asString(json['address'] ?? json['display_address']),
      priceDisplay: json['price_display']?.toString(),
      thumbnail: json['thumbnail']?.toString(),
      beds: _asInt(json['beds']),
      baths: json['baths'] is num
          ? json['baths'] as num
          : num.tryParse(json['baths']?.toString() ?? ''),
    );
  }
}

/// A property owner offered as a one-tap attendee suggestion when a property is
/// added — from `GET .../calendar/properties/{id}/owners`.
class PropertyOwner {
  final int id;
  final String name;
  final String? firstName;
  final String? lastName;
  final String? phone;
  final String? email;
  final String type; // 'contact' (always, in practice)
  final String role; // pre-set role, e.g. 'seller_contact'
  final String? roleLabel;

  const PropertyOwner({
    required this.id,
    required this.name,
    this.firstName,
    this.lastName,
    this.phone,
    this.email,
    this.type = 'contact',
    this.role = 'attendee',
    this.roleLabel,
  });

  factory PropertyOwner.fromJson(Map<String, dynamic> json) {
    final first = json['first_name']?.toString();
    final last = json['last_name']?.toString();
    final name = _asString(json['name']).isNotEmpty
        ? _asString(json['name'])
        : [first, last].whereType<String>().where((s) => s.isNotEmpty).join(' ');
    return PropertyOwner(
      id: _asInt(json['id']) ?? 0,
      name: name,
      firstName: first,
      lastName: last,
      phone: json['phone']?.toString(),
      email: json['email']?.toString(),
      type: _asString(json['type']).isNotEmpty ? _asString(json['type']) : 'contact',
      role: _asString(json['role']).isNotEmpty ? _asString(json['role']) : 'attendee',
      roleLabel: json['role_label']?.toString(),
    );
  }
}

/// An attendee hit from `GET .../calendar/search/attendees?q=` — a contact or
/// an agent.
class AttendeeSearchResult {
  final int id;
  final String name;
  final String? phone;
  final String? email;
  final String? identifier;
  final String? contactType;
  final String type; // 'contact' | 'agent'

  const AttendeeSearchResult({
    required this.id,
    required this.name,
    this.phone,
    this.email,
    this.identifier,
    this.contactType,
    this.type = 'contact',
  });

  bool get isAgent => type == 'agent';

  factory AttendeeSearchResult.fromJson(Map<String, dynamic> json) {
    return AttendeeSearchResult(
      id: _asInt(json['id']) ?? 0,
      name: _asString(json['name']),
      phone: json['phone']?.toString(),
      email: json['email']?.toString(),
      identifier: json['identifier']?.toString(),
      contactType: json['contact_type']?.toString(),
      type: _asString(json['type']).isNotEmpty ? _asString(json['type']) : 'contact',
    );
  }
}

/// A property selected on the form. Chip-rendered; only the `id` is submitted.
class SelectedProperty {
  final int id;
  final String address;
  final String? priceDisplay;
  final String? thumbnail;

  const SelectedProperty({
    required this.id,
    required this.address,
    this.priceDisplay,
    this.thumbnail,
  });

  factory SelectedProperty.fromSearch(PropertySearchResult p) => SelectedProperty(
        id: p.id,
        address: p.address,
        priceDisplay: p.priceDisplay,
        thumbnail: p.thumbnail,
      );
}

/// Mutable working-state for an attendee selected on the form. `role` is
/// editable for contacts via the attendee-role picker; for agents it's left
/// effectively unset (the backend assigns `agent_contact`) and not submitted.
class SelectedAttendee {
  final int id;
  final String type; // 'contact' | 'agent'
  String role;
  final String name;
  final String? invitationStatus; // populated on edit (agents)
  final int? invitationId;

  SelectedAttendee({
    required this.id,
    required this.type,
    required this.role,
    required this.name,
    this.invitationStatus,
    this.invitationId,
  });

  bool get isAgent => type == 'agent';

  /// Identity key used to dedupe across search/owner/edit sources.
  String get key => '$type:$id';

  factory SelectedAttendee.fromSearch(AttendeeSearchResult a) => SelectedAttendee(
        id: a.id,
        type: a.type,
        // Contacts default to `attendee`; agents leave role unset.
        role: a.isAgent ? '' : 'attendee',
        name: a.name,
      );

  factory SelectedAttendee.fromOwner(PropertyOwner o) => SelectedAttendee(
        id: o.id,
        type: o.type,
        role: o.role,
        name: o.name,
      );

  /// Submit shape: `{id, type, role?}` — role only sent for contacts.
  Map<String, dynamic> toBody() => {
        'id': id,
        'type': type,
        if (!isAgent && role.isNotEmpty) 'role': role,
      };
}

/// Full event payload from `GET .../calendar/{id}` used to pre-fill the edit
/// sheet. Permissive parsing — missing fields fall back rather than throw.
class EventFormData {
  final int id;
  final String title;
  final String? description;
  final DateTime eventDate;
  final DateTime? endDate;
  final bool allDay;
  final String? category;
  final String priority;
  final String status;
  final bool sendReminder;
  final bool isEditable;
  final String? sourceType;
  final bool isPrivate;
  final int? dealId;
  final List<SelectedProperty> linkedProperties;
  final List<SelectedAttendee> attendees;

  const EventFormData({
    required this.id,
    required this.title,
    this.description,
    required this.eventDate,
    this.endDate,
    this.allDay = false,
    this.category,
    this.priority = 'normal',
    this.status = 'pending',
    this.sendReminder = true,
    this.isEditable = true,
    this.sourceType,
    this.isPrivate = false,
    this.dealId,
    this.linkedProperties = const [],
    this.attendees = const [],
  });

  /// Whether this event may be opened in the edit sheet.
  ///
  /// The server's `is_editable` is authoritative when true. The fallback below
  /// exists because that flag is computed as
  /// `in_array(source_type, ['manual', 'manual:demo'])`, which is **false for a
  /// NULL source_type** — so a plain user-created event whose creation path
  /// never stamped the column (voice scheduling, older rows) came back
  /// read-only even though `PUT .../calendar/{id}` accepts the edit. Nothing
  /// here keys off `status`: a completed event is as editable as a pending one.
  ///
  /// A blank source_type means "not generated from another record", so it's
  /// manual. Genuinely source-driven events (a deal step, a portal expiry) stay
  /// locked — their fields are recomputed from the source and an edit here
  /// would just be overwritten. A private event redacted for a non-creator
  /// carries `is_private: true` and is never editable.
  bool get canEdit {
    if (isEditable) return true;
    if (isPrivate) return false;
    final s = (sourceType ?? '').trim();
    return s.isEmpty || s == 'manual' || s == 'manual:demo';
  }

  factory EventFormData.fromJson(Map<String, dynamic> json) {
    // Linked properties: prefer the explicit array; fall back to the single
    // property_id/property_address pair the legacy shape carries.
    final linked = <SelectedProperty>[];
    final lp = json['linked_properties'];
    if (lp is List) {
      for (final e in lp.whereType<Map>()) {
        final m = Map<String, dynamic>.from(e);
        final id = _asInt(m['id']);
        if (id == null) continue;
        linked.add(SelectedProperty(
          id: id,
          address: _asString(m['address'] ?? m['display_address']),
        ));
      }
    }
    if (linked.isEmpty && _asInt(json['property_id']) != null) {
      linked.add(SelectedProperty(
        id: _asInt(json['property_id'])!,
        address: _asString(json['property_address']),
      ));
    }

    final attendees = <SelectedAttendee>[];
    final at = json['attendees'];
    if (at is List) {
      for (final e in at.whereType<Map>()) {
        final m = Map<String, dynamic>.from(e);
        final id = _asInt(m['id']);
        if (id == null) continue;
        final type = _asString(m['type']).isNotEmpty ? _asString(m['type']) : 'contact';
        final first = m['first_name']?.toString();
        final last = m['last_name']?.toString();
        final name = _asString(m['name']).isNotEmpty
            ? _asString(m['name'])
            : [first, last]
                .whereType<String>()
                .where((s) => s.isNotEmpty)
                .join(' ');
        attendees.add(SelectedAttendee(
          id: id,
          type: type,
          role: _asString(m['role']),
          name: name,
          invitationStatus: m['invitation_status']?.toString(),
          invitationId: _asInt(m['invitation_id']),
        ));
      }
    }

    return EventFormData(
      id: _asInt(json['id']) ?? 0,
      title: _asString(json['title']),
      description: json['description']?.toString(),
      eventDate: DateTime.tryParse(
              (json['event_date'] ?? json['starts_at'] ?? '').toString()) ??
          DateTime.now(),
      endDate: (json['end_date'] ?? json['ends_at']) == null
          ? null
          : DateTime.tryParse((json['end_date'] ?? json['ends_at']).toString()),
      allDay: _asBool(json['all_day']),
      category: json['category']?.toString(),
      priority: _asString(json['priority']).isNotEmpty
          ? _asString(json['priority'])
          : 'normal',
      status: _asString(json['status']).isNotEmpty
          ? _asString(json['status'])
          : 'pending',
      // Default true: a missing flag shouldn't lock a freshly-created event.
      sendReminder:
          json['send_reminder'] == null ? true : _asBool(json['send_reminder']),
      isEditable:
          json['is_editable'] == null ? true : _asBool(json['is_editable']),
      sourceType: json['source_type']?.toString(),
      isPrivate: _asBool(json['is_private']),
      dealId: _asInt(json['deal_id']),
      linkedProperties: linked,
      attendees: attendees,
    );
  }

  static EventFormData fromResponseBody(String body) {
    final decoded = jsonDecode(body);
    final map = decoded is Map && decoded['event'] is Map
        ? Map<String, dynamic>.from(decoded['event'] as Map)
        : Map<String, dynamic>.from(decoded as Map);
    return EventFormData.fromJson(map);
  }
}
