import 'package:flutter/material.dart';

import '../../../core/testing/test_keys.dart';
import '../data/fleet_models.dart';
import 'fleet_cap_dial.dart';
import 'fleet_row_card.dart';

/// Fleet Status: eight facts per seat, the offline toggle and the fleet-size cap dial.
///
/// State comes in and callbacks go out. The widget takes a parsed [FleetComposite] and
/// renders it. Fetching, polling and the write live elsewhere. Every branch is therefore
/// reachable from a widget test without a socket or a server.
class FleetStatusPane extends StatefulWidget {
  /// The parsed fleet to render.
  final FleetComposite            composite;

  /// The fleet-size cap, or null when unknown.
  final int?                      cap;

  /// The server's ceiling for the cap, or null.
  final int?                      capMaximum;

  /// Applies a new cap; null hides the dial.
  final Future<void> Function( int cap )? onSetCap;

  /// Called on pull-to-refresh.
  final Future<void> Function()?  onRefresh;

  /// The full session ids this caller may open a console on, from the roster projection.
  ///
  /// The join to fleet rows by `session_id` is exact string equality. The stream is keyed
  /// on the full `stable_session_id` and three id widths circulate. A width mismatch hides
  /// the button instead of offering a watch on a prefix the stream would not recognise.
  /// The client cannot tell "not watchable" from "the ids disagree". That is safe for the
  /// operator but useless for diagnosis, so the server must check the surfaces agree.
  final Set<String> watchableSessionIds;

  /// Opens the Live Console for one seat; null hides the affordance everywhere.
  final void Function( FleetSession session )? onWatch;

  /// Creates the pane.
  const FleetStatusPane( {
    super.key,
    required this.composite,
    this.cap,
    this.capMaximum,
    this.onSetCap,
    this.onRefresh,
    this.watchableSessionIds = const <String>{},
    this.onWatch,
  } );

  @override
  State<FleetStatusPane> createState() => _FleetStatusPaneState();
}

class _FleetStatusPaneState extends State<FleetStatusPane> {
  // Offline seats are hidden by default; the toggle is the difference between a readable
  // list and a wall of dead seats.
  bool _showOffline = false;

  @override
  Widget build( BuildContext context ) {
    final composite = widget.composite;

    // The unreachable check comes before the empty check. The endpoint answers
    // `status: "unreachable"` with an HTTP 200 when the `:8001` arbiter is down. That and
    // a genuinely idle fleet both produce zero rows, but only the first is a reason to
    // restart something. Checking empty first would collapse the two.
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
      // Every seat is offline and the toggle hides them. Say so, instead of showing the
      // blank pane an empty fleet shows.
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
          onWatchTap    : _watchTapFor( session ),
        );
      },
    );
  }

  // The row's watch callback, or null when this seat is not watchable. Every "no"
  // collapses to null here, in one place: no handler from the caller, a row with no
  // session id, or a session id absent from the roster. An unreachable arbiter produces no
  // roster rows, a 403 produces an empty set, and an older server produces the same empty
  // set. No error, no dead button.
  VoidCallback? _watchTapFor( FleetSession session ) {
    final onWatch = widget.onWatch;
    if ( onWatch == null ) return null;

    final id = session.sessionId;
    if ( id == null || !widget.watchableSessionIds.contains( id ) ) return null;

    return () => onWatch( session );
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
              // The label is spoken as well as drawn, so a screen reader hears a named
              // control.
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

  // The raw liveness ages, in a sheet rather than an in-place expansion: opening a route
  // moves focus, so a screen-reader user is carried to the detail and hears it.
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
            // The same text as the web's hover tooltip; only the gesture differs.
            Text( session.livenessDetail ),
          ],
        ),
      ),
    );
  }

  // A full-pane notice, scrollable so pull-to-refresh still works over it. Its height is
  // a minimum, not a fixed box: a fixed `SizedBox( height: 120 )` overflowed at 360 dp when
  // a title wrapped to two lines, and an overflowing notice says nothing when the operator
  // most needs it.
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
