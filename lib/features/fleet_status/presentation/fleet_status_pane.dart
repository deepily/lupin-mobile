import 'package:flutter/material.dart';

import '../../../core/testing/test_keys.dart';
import '../data/fleet_models.dart';
import 'fleet_cap_dial.dart';
import 'fleet_row_card.dart';

/// Fleet Status — the eight facts per seat, the offline toggle, and the
/// fleet-size cap dial.
///
/// This widget is deliberately state-in / callbacks-out: it takes a parsed
/// [FleetComposite] and renders it. Fetching, polling and the write live in the
/// repository and whatever drives it, so every branch below is reachable from a
/// widget test without a socket or a server.
class FleetStatusPane extends StatefulWidget {
  final FleetComposite            composite;
  final int?                      cap;
  final int?                      capMaximum;
  final Future<void> Function( int cap )? onSetCap;
  final Future<void> Function()?  onRefresh;

  const FleetStatusPane( {
    super.key,
    required this.composite,
    this.cap,
    this.capMaximum,
    this.onSetCap,
    this.onRefresh,
  } );

  @override
  State<FleetStatusPane> createState() => _FleetStatusPaneState();
}

class _FleetStatusPaneState extends State<FleetStatusPane> {
  /// Offline seats hidden by default — the toggle is the difference between a
  /// readable list and a wall of dead seats.
  bool _showOffline = false;

  @override
  Widget build( BuildContext context ) {
    final composite = widget.composite;

    // 🔴 THE UNREACHABLE CHECK COMES FIRST, AND IT IS NOT THE EMPTY CHECK.
    // `/api/arbiter/fleet-state` answers `status: "unreachable"` with an HTTP
    // 200 when the :8001 arbiter is down (arbiter.py:168-176). Both that and a
    // genuinely idle fleet produce zero rows, but only one of them is a reason
    // to go and restart something. Ordering this branch after the empty check
    // would silently collapse the two.
    if ( composite.isUnreachable ) {
      return _notice(
        key     : TestKeys.fleetStatusUnreachable,
        icon    : Icons.cloud_off,
        title   : "Cannot see the fleet",
        detail  : "The arbiter service is not answering. This is not an empty "
                  "fleet — seats may be running and unseen.",
      );
    }

    final visible = composite.sessions
        .where( ( s ) => _showOffline || !s.isOffline )
        .toList( growable: false );

    return Column(
      children: [
        _toolbar( context, composite ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => widget.onRefresh?.call(),
            child    : _body( visible, composite ),
          ),
        ),
      ],
    );
  }

  Widget _body( List<FleetSession> visible, FleetComposite composite ) {
    if ( composite.sessions.isEmpty ) {
      return _scrollable( _notice(
        key    : TestKeys.fleetStatusEmpty,
        icon   : Icons.people_outline,
        title  : "No seats running",
        detail : "The arbiter is reachable and reports an empty fleet.",
      ) );
    }

    if ( visible.isEmpty ) {
      // Every seat is offline and the toggle is hiding them. Say so, rather
      // than showing the same blank pane an empty fleet shows.
      return _scrollable( _notice(
        key    : TestKeys.fleetStatusEmpty,
        icon   : Icons.visibility_off_outlined,
        title  : "All ${ composite.sessions.length } seats are offline",
        detail : "Turn on \"Show offline\" to see them.",
      ) );
    }

    return ListView.builder(
      key         : const Key( TestKeys.fleetStatusList ),
      itemCount   : visible.length,
      itemBuilder : ( context, i ) {
        final session = visible[ i ];
        return FleetRowCard(
          session       : session,
          context       : composite.contextFor( session ),
          onLivenessTap : () => _showLiveness( context, session ),
        );
      },
    );
  }

  Widget _toolbar( BuildContext context, FleetComposite composite ) {
    final offlineCount = composite.sessions.where( ( s ) => s.isOffline ).length;

    return Padding(
      padding : const EdgeInsets.fromLTRB( 16, 8, 16, 0 ),
      child   : Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  "${ composite.sessions.length } seat"
                  "${ composite.sessions.length == 1 ? "" : "s" }"
                  "${ offlineCount > 0 ? " · $offlineCount offline" : "" }",
                  style: Theme.of( context ).textTheme.bodySmall,
                ),
              ),
              // The label is spoken as well as drawn, so the switch is not an
              // unnamed control to a screen reader.
              Semantics(
                label : "Show offline seats",
                child : Switch(
                  key       : const Key( TestKeys.fleetStatusOfflineToggle ),
                  value     : _showOffline,
                  onChanged : ( v ) => setState( () => _showOffline = v ),
                ),
              ),
              Text( "Offline", style: Theme.of( context ).textTheme.labelSmall ),
            ],
          ),
          if ( widget.onSetCap != null )
            FleetCapDial(
              cap        : widget.cap,
              capMaximum : widget.capMaximum,
              onSetCap   : widget.onSetCap!,
            ),
        ],
      ),
    );
  }

  /// The raw four ages, in a sheet.
  ///
  /// A sheet rather than an in-place expansion: opening a route moves focus, so
  /// a screen-reader user is carried to the detail and hears it announced.
  void _showLiveness( BuildContext context, FleetSession session ) {
    showModalBottomSheet<void>(
      context : context,
      builder : ( sheetContext ) => Padding(
        key     : const Key( TestKeys.fleetStatusLivenessSheet ),
        padding : const EdgeInsets.all( 24 ),
        child   : Column(
          mainAxisSize       : MainAxisSize.min,
          crossAxisAlignment : CrossAxisAlignment.start,
          children           : [
            Text(
              "${ session.whoLabel } — ${ session.liveness.verdictLabel }",
              style: Theme.of( sheetContext ).textTheme.titleMedium,
            ),
            const SizedBox( height: 12 ),
            // Ported verbatim from the web's hover tooltip; only the gesture
            // that reaches it has changed.
            Text( session.livenessDetail ),
          ],
        ),
      ),
    );
  }

  /// A full-pane notice. Scrollable so pull-to-refresh still works over it.
  ///
  /// ⚠️ THE HEIGHT IS A MINIMUM, NOT A FIXED BOX, and the first cut got that
  /// wrong. A `SizedBox( height: 120 )` overflowed at 360 dp as soon as a title
  /// wrapped to two lines — caught by the widget tests once they were moved off
  /// the 800x600 default onto a real phone surface. A notice that overflows is
  /// the pane telling the operator nothing at the moment it most needs to speak.
  Widget _scrollable( Widget child ) => LayoutBuilder(
    builder: ( context, constraints ) => ListView(
      physics  : const AlwaysScrollableScrollPhysics(),
      children : [
        ConstrainedBox(
          constraints : BoxConstraints( minHeight: constraints.maxHeight ),
          child       : child,
        ),
      ],
    ),
  );

  Widget _notice( {
    required String   key,
    required IconData icon,
    required String   title,
    required String   detail,
  } ) {
    return Center(
      key   : Key( key ),
      child : Padding(
        padding : const EdgeInsets.all( 24 ),
        child   : Column(
          mainAxisSize : MainAxisSize.min,
          children     : [
            Icon( icon, size: 40 ),
            const SizedBox( height: 12 ),
            Text( title, textAlign: TextAlign.center ),
            const SizedBox( height: 6 ),
            Text( detail, textAlign: TextAlign.center ),
          ],
        ),
      ),
    );
  }
}
