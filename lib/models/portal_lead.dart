import '../utils/app_time.dart';

class PortalLead {
  final int id;
  final String portal;
  final String portalLabel;
  final String? leadType;
  final String? name;
  final String? email;
  final String? phone;
  final bool isWhatsapp;
  final int? listingId;
  final String? listingPortalRef;
  final String? listingTitle;
  final int? contactId;
  final bool contactExists;
  final String? existingAgent;
  final DateTime? receivedAt;
  final DateTime? notifiedAt;
  final bool isUnread;
  final String? message;
  final String? leadSourceRaw;

  PortalLead({
    required this.id,
    required this.portal,
    required this.portalLabel,
    this.leadType,
    this.name,
    this.email,
    this.phone,
    this.isWhatsapp = false,
    this.listingId,
    this.listingPortalRef,
    this.listingTitle,
    this.contactId,
    this.contactExists = false,
    this.existingAgent,
    this.receivedAt,
    this.notifiedAt,
    this.isUnread = false,
    this.message,
    this.leadSourceRaw,
  });

  factory PortalLead.fromJson(Map<String, dynamic> j) {
    DateTime? p(dynamic v) {
      if (v is! String || v.isEmpty) return null;
      final parsed = DateTime.tryParse(v);
      return parsed == null ? null : jhb(parsed);
    }
    int? i(dynamic v) => v is num ? v.toInt() : (v is String ? int.tryParse(v) : null);
    return PortalLead(
      id: i(j['id']) ?? 0,
      portal: j['portal']?.toString() ?? '',
      portalLabel: j['portal_label']?.toString() ?? '',
      leadType: j['lead_type']?.toString(),
      name: j['name']?.toString(),
      email: j['email']?.toString(),
      phone: j['phone']?.toString(),
      isWhatsapp: j['is_whatsapp'] == true,
      listingId: i(j['listing_id']),
      listingPortalRef: j['listing_portal_ref']?.toString(),
      listingTitle: j['listing_title']?.toString(),
      contactId: i(j['contact_id']),
      contactExists: j['contact_exists'] == true,
      existingAgent: j['existing_agent']?.toString(),
      receivedAt: p(j['received_at']),
      notifiedAt: p(j['notified_at']),
      isUnread: j['is_unread'] == true,
      message: j['message']?.toString(),
      leadSourceRaw: j['lead_source_raw']?.toString(),
    );
  }

  PortalLead copyWith({bool? isUnread}) => PortalLead(
        id: id,
        portal: portal,
        portalLabel: portalLabel,
        leadType: leadType,
        name: name,
        email: email,
        phone: phone,
        isWhatsapp: isWhatsapp,
        listingId: listingId,
        listingPortalRef: listingPortalRef,
        listingTitle: listingTitle,
        contactId: contactId,
        contactExists: contactExists,
        existingAgent: existingAgent,
        receivedAt: receivedAt,
        notifiedAt: notifiedAt,
        isUnread: isUnread ?? this.isUnread,
        message: message,
        leadSourceRaw: leadSourceRaw,
      );
}

class PortalLeadDate {
  final String date; // YYYY-MM-DD
  final int total;
  final int unread;

  PortalLeadDate({required this.date, required this.total, required this.unread});

  factory PortalLeadDate.fromJson(Map<String, dynamic> j) => PortalLeadDate(
        date: j['date']?.toString() ?? '',
        total: j['total'] is num ? (j['total'] as num).toInt() : 0,
        unread: j['unread'] is num ? (j['unread'] as num).toInt() : 0,
      );
}
