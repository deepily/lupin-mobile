import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../transcript/domain/transcript_stream_bloc.dart';
import '../../transcript/presentation/live_console_screen.dart';
import '../data/fleet_models.dart';
import '../domain/fleet_status_bloc.dart';
import 'fleet_status_pane.dart';

/// The Fleet Status destination.
///
/// This route creates the bloc and the bloc dies with it. The app's convention registers
/// blocs at the app root as `ServiceLocator` singletons. A root-level pane bloc outlives
/// its route and keeps polling whichever destination is showing. Five such panes would run
/// five timers at once, and a "polling stops when backgrounded" test passes with all
/// five. Route scope is the zero-request guard. An unvisited pane has no bloc. A pane left
/// behind is disposed, which cancels the timer and the in-flight request. The home screen's
/// nav cards use `BlocProvider.value`; this one does not.
class FleetStatusScreen extends StatelessWidget {
  /// How the route builds its bloc.
  ///
  /// It is required, not optional with a fallback. An optional factory needs a `!` at the
  /// use site, which crashes for the first caller who forgets it. The home screen
  /// supplies the real one and a widget test supplies a fake.
  final FleetStatusBloc Function( BuildContext ) blocFactory;

  /// How the Live Console route builds its bloc for the seat whose watch button was tapped.
  ///
  /// Null means no watch affordance at all, not a dead button. The console's bloc is
  /// route-scoped, so the route needs a factory as this screen does. A caller that supplies
  /// none cannot open a console, the same rule `_watchTapFor` applies to every other
  /// reason a seat is not watchable. The nav site passes the factory in
  /// (`ServiceLocator.buildTranscriptStreamBloc`), so both routes build in a widget test
  /// without a DI container.
  final TranscriptStreamBloc Function( BuildContext, String ccSessionId )?
      consoleBlocFactory;

  /// Creates the screen.
  const FleetStatusScreen( {
    super.key,
    required this.blocFactory,
    this.consoleBlocFactory,
  } );

  @override
  Widget build( BuildContext context ) {
    return BlocProvider<FleetStatusBloc>(
      // `create`, never `.value`; see the class doc.
      create : blocFactory,
      child  : _FleetStatusView( consoleBlocFactory: consoleBlocFactory ),
    );
  }
}

class _FleetStatusView extends StatefulWidget {
  final TranscriptStreamBloc Function( BuildContext, String )? consoleBlocFactory;

  const _FleetStatusView( { this.consoleBlocFactory } );

  @override
  State<_FleetStatusView> createState() => _FleetStatusViewState();
}

class _FleetStatusViewState extends State<_FleetStatusView> {
  // Held as a field because `dispose()` cannot look up an ancestor.
  // `context.read<FleetStatusBloc>()` inside `dispose()` throws "Looking up a deactivated
  // widget's ancestor is unsafe", so `onPaneHidden()` would never run and the 60-second
  // poll timer would outlive the route. The reference is saved in `didChangeDependencies()`
  // and used in `dispose()`.
  late final FleetStatusBloc _bloc;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bloc = context.read<FleetStatusBloc>();
  }

  @override
  void initState() {
    super.initState();
    // Deferred to the first frame: `initState` runs before `didChangeDependencies`, so the
    // bloc is not resolved yet.
    WidgetsBinding.instance.addPostFrameCallback( ( _ ) {
      if ( !mounted ) return;
      _bloc.startPolling();
      // The route says the pane is on screen. The mixin refreshes once now, then holds the
      // interval while the app stays foregrounded.
      _bloc.onPaneVisible();
    } );
  }

  @override
  void dispose() {
    // Uses the saved reference; see the field comment. This stops the timer and cancels
    // the in-flight request, so neither outlives the route.
    _bloc.onPaneHidden();
    super.dispose();
  }

  // Pushes the Live Console for one seat on an ordinary `MaterialPageRoute`. The console's
  // bloc is created inside the route, not at the app root, for the reason in the class doc.
  // An app-root console bloc would keep its watch open after the operator walked away, and
  // a "stops when you leave" test would pass anyway; a test pops the route, emits a frame
  // for that seat and finds no bloc alive. The id is read off the session, because the
  // roster only says whether a seat is watchable. `_watchTapFor` has already found the id
  // in the roster set, so the `!` cannot fire: a row with a null id never gets a button.
  void _openConsole( BuildContext context, FleetSession session ) {
    final factory = widget.consoleBlocFactory;
    if ( factory == null ) return;

    final id = session.sessionId!;
    Navigator.of( context ).push( MaterialPageRoute<void>(
      builder: ( _ ) => LiveConsoleScreen(
        ccSessionId : id,
        whoLabel    : session.whoLabel,
        blocFactory : ( routeContext ) => factory( routeContext, id ),
      ),
    ) );
  }

  @override
  Widget build( BuildContext context ) {
    return Scaffold(
      appBar : AppBar( title: const Text( "Fleet Status" ) ),
      body   : BlocBuilder<FleetStatusBloc, FleetStatusState>(
        builder: ( context, state ) {
          final composite = state.composite;

          // First paint, before any poll has landed.
          if ( composite == null && state.error == null ) {
            return const Center( child: CircularProgressIndicator() );
          }

          // A transport failure is not an unreachable arbiter. This branch means the phone
          // could not reach `:7999`; the envelope inside `composite` means `:7999` is fine
          // and `:8001` is not. Only the second is a reason to restart something, so they
          // get different screens; `FleetStatusPane` shows the other.
          if ( composite == null ) {
            return Center(
              child: Padding(
                padding : const EdgeInsets.all( 24 ),
                child   : Column(
                  mainAxisSize : MainAxisSize.min,
                  children     : [
                    const Icon( Icons.signal_wifi_off, size: 40 ),
                    const SizedBox( height: 12 ),
                    const Text( "Could not reach the server" ),
                    const SizedBox( height: 6 ),
                    Text( state.error!, textAlign: TextAlign.center ),
                    const SizedBox( height: 12 ),
                    FilledButton(
                      onPressed: () => context
                          .read<FleetStatusBloc>()
                          .add( const FleetStatusRefreshRequested() ),
                      child: const Text( "Retry" ),
                    ),
                  ],
                ),
              ),
            );
          }

          return FleetStatusPane(
            composite  : composite,
            cap        : state.cap,
            capMaximum : state.capMaximum,
            onSetCap   : ( cap ) => context.read<FleetStatusBloc>().setCap( cap ),
            onRefresh  : () async => context
                .read<FleetStatusBloc>()
                .add( const FleetStatusRefreshRequested() ),
            watchableSessionIds : state.watchableSessionIds,
            // Null when no console factory was supplied: no factory, no route, no button.
            onWatch             : widget.consoleBlocFactory == null
                ? null
                : ( session ) => _openConsole( context, session ),
          );
        },
      ),
    );
  }
}
