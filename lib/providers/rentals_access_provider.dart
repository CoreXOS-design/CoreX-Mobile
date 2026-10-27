import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../models/visibility.dart';
import 'client_session_provider.dart';
import 'visibility_provider.dart';

/// The one answer to "may this person see Rentals?" (AT-508). Every rental
/// entry point — tiles, the hub, sections on other screens, deep links and
/// pushes — asks this; no screen decides on its own.
///
///  * Client: `rentals.{tenant, owner}` from `/client/me`, for the current
///    agency.
///  * Staff: `rentals_enabled` + the per-screen flags from
///    `/mobile/visibility`.
///
/// Derived from [ClientSessionProvider] and [VisibilityProvider], which keep
/// the flags in memory for the session only. A flag that is false means the
/// entry point does not exist — hide it, never grey it out.
@immutable
class RentalsAccess {
  /// Client sides. Both false for staff and signed-out users.
  final bool tenant;
  final bool owner;

  /// Staff screens; [RentalScreens.none] for clients and when the agency or
  /// role has Rentals off.
  final RentalScreens staffScreens;

  /// Staff `rentals_enabled`. Also gates the property Inspections tab.
  final bool staffRentalsEnabled;

  const RentalsAccess({
    this.tenant = false,
    this.owner = false,
    this.staffScreens = RentalScreens.none,
    this.staffRentalsEnabled = false,
  });

  factory RentalsAccess.from(
      ClientSessionProvider client, VisibilityProvider staff) {
    if (client.isLoggedIn) {
      return RentalsAccess(
          tenant: client.rentals.tenant, owner: client.rentals.owner);
    }
    if (!staff.loaded) return const RentalsAccess();
    return RentalsAccess(
      staffScreens: staff.rentals,
      staffRentalsEnabled: staff.descriptor.rentalsEnabled,
    );
  }

  /// Staff may open the Rentals hub (at least one screen is viewable).
  bool get staff => staffScreens.any;

  /// Like `context.read<RentalsAccess>()`, but first waits (bounded) for the
  /// flags to arrive. For a deep link or push tapped on cold start, which can
  /// beat `/client/me` or `/mobile/visibility`; on timeout it answers with
  /// whatever is known, and unknown means hidden.
  static Future<RentalsAccess> settled(BuildContext context,
      {Duration timeout = const Duration(seconds: 10)}) async {
    final client = context.read<ClientSessionProvider>();
    final staff = context.read<VisibilityProvider>();
    bool ready() =>
        client.isLoggedIn ? client.rentalsLoaded : staff.loaded;
    if (!ready()) {
      final done = Completer<void>();
      void check() {
        if (ready() && !done.isCompleted) done.complete();
      }

      client.addListener(check);
      staff.addListener(check);
      try {
        await done.future.timeout(timeout, onTimeout: () {});
      } finally {
        client.removeListener(check);
        staff.removeListener(check);
      }
    }
    return RentalsAccess.from(client, staff);
  }

  @override
  bool operator ==(Object other) =>
      other is RentalsAccess &&
      other.tenant == tenant &&
      other.owner == owner &&
      other.staffScreens == staffScreens &&
      other.staffRentalsEnabled == staffRentalsEnabled;

  @override
  int get hashCode =>
      Object.hash(tenant, owner, staffScreens, staffRentalsEnabled);
}
