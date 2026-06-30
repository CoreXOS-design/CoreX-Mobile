import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/env.dart';
import '../screens/contacts/contact_show_screen.dart';
import '../screens/properties/property_edit_screen.dart';

/// Navigates to the first non-null pillar destination, following the
/// cockpit fallback order: property → deal → contact.
///
/// Returns `true` if navigation happened. If every id is null the caller
/// should render plain (non-tappable) text rather than a dead link.
bool navigateToPillar(
  BuildContext context, {
  int? propertyId,
  int? dealId,
  int? contactId,
}) {
  if (propertyId != null) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PropertyEditScreen(propertyId: propertyId)),
    );
    return true;
  }
  if (dealId != null) {
    // No native deal screen yet — open the real web deal page rather than a
    // placeholder. Host is derived from the configured API base (strip /api).
    final webBase = Env.apiBaseUrl.replaceFirst(RegExp(r'/api/?$'), '');
    final uri = Uri.tryParse('$webBase/deals/$dealId');
    if (uri != null) {
      // Fire-and-forget; the pillar tap shouldn't block on the launch.
      launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return true;
  }
  if (contactId != null) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ContactShowScreen(contactId: contactId)),
    );
    return true;
  }
  return false;
}

/// True when at least one pillar FK is populated — use to decide whether to
/// render a row's title / address as a tappable link versus plain text.
bool hasPillarLink({int? propertyId, int? dealId, int? contactId}) =>
    propertyId != null || dealId != null || contactId != null;
