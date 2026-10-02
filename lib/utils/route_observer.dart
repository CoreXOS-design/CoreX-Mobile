import 'package:flutter/widgets.dart';

/// App-wide route observer, registered on the root [MaterialApp]. Widgets that
/// must refresh when a route pushed on top of them pops (e.g. the Home hero
/// card after Ellie schedules an appointment) subscribe via [RouteAware].
final RouteObserver<ModalRoute<void>> corexRouteObserver =
    RouteObserver<ModalRoute<void>>();
