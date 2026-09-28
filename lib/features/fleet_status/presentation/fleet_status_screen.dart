import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../transcript/domain/transcript_stream_bloc.dart';
import '../../transcript/presentation/live_console_screen.dart';
import '../data/fleet_models.dart';
import '../domain/fleet_status_bloc.dart';
import 'fleet_status_pane.dart';

/// The Fleet Status destination.
///
/// 🔴 THE BLOC IS CREATED BY THIS ROUTE AND DIES WITH IT. That is the mechanism
/// behind §6.3's rule, not a style preference, and it is a deliberate departure
/// from this app's convention: `app.dart:248-278` registers its blocs at the
/// APP ROOT as `ServiceLocator` singletons, so a pane bloc built that way
/// outlives its route and keeps polling whichever destination is showing. Five
/// panes following that pattern means five timers running at once — and the
/// obvious test, *"polling stops when backgrounded"*, passes with all five
/// running.
///
/// ⇒ Route-scoping IS the zero-request guard. A pane the operator has not
/// navigated to has no bloc, so it cannot issue a request; a pane they left is
/// disposed, which cancels the timer AND the in-flight request. Every sibling
/// `_NavCard` on the home screen uses `BlocProvider.value( context.read<…>() )`
/// and this one deliberately does not — Rick should see that as a decision
/// rather than discover it as an inconsistency.
class FleetStatusScreen extends StatelessWidget {
  /// How the route builds its bloc.
  ///
  /// REQUIRED rather than optional-with-a-fallback: an optional factory needs a
  /// `!` at the use site, which is a crash waiting for the first caller who
  /// forgets it. The home screen supplies the real one; a widget test supplies
  /// a fake, and neither can forget.
  final FleetStatusBloc Function( BuildContext ) blocFactory;

  /// How the LIVE CONSOLE route builds its bloc, for the seat whose watch button was tapped.
  ///
  /// 🔴 NULL MEANS NO WATCH AFFORDANCE AT ALL, which is the honest default rather than a
  /// dead button. The console's bloc is route-scoped (C1), so the route needs a factory the
  /// way this screen does; a caller that has not supplied one cannot open a console, so the
  /// button is not drawn. That is the same rule `_watchTapFor` already applies to every
  /// other reason a seat is not watchable, and the widget test
  /// "no onWatch wired ⇒ no button anywhere" is what holds it.
  ///
  /// ⚠️ IT IS THREADED FROM THE NAV SITE, NOT READ OFF THE LOCATOR HERE. `home_screen.dart`
  /// passes `ServiceLocator.buildTranscriptStreamBloc`, the same shape it already uses for
  /// this screen's own bloc — which is what keeps both routes buildable in a widget test
  /// without a DI container.
  final TranscriptStreamBloc Function( BuildContext, String ccSessionId )?
      consoleBlocFactory;

  const FleetStatusScreen( {
    super.key,
    required this.blocFactory,
    this.consoleBlocFactory,
  } );

  @override
  Widget build( BuildContext context ) {
    return BlocProvider<FleetStatusBloc>(
      // `create`, never `.value` — see the class docstring.
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
  /// 🔴 HELD AS A FIELD BECAUSE `dispose()` CANNOT LOOK UP AN ANCESTOR, AND THE
  /// FIRST CUT OF THIS CLASS DID EXACTLY THAT. `context.read<FleetStatusBloc>()`
  /// inside `dispose()` throws *"Looking up a deactivated widget's ancestor is
  /// unsafe"* — the element is already deactivated by then. The throw meant
  /// `onPaneHidden()` NEVER RAN, so **the 60-second poll timer survived the
  /// route**: every time the operator left this pane, the app kept one more
  /// timer polling a screen nobody was looking at. Exactly the battery defect
  /// §6.3 exists to prevent, reintroduced by the teardown that was supposed to
  /// prevent it.
  ///
  /// The framework names the remedy in the error text: save the reference in
  /// `didChangeDependencies()` and use the saved one in `dispose()`.
  late final FleetStatusBloc _bloc;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bloc = context.read<FleetStatusBloc>();
  }

  @override
  void initState() {
    super.initState();
    // Deferred to the first frame: `initState` runs before
    // `didChangeDependencies`, so the bloc is not resolved yet.
    WidgetsBinding.instance.addPostFrameCallback( ( _ ) {
      if ( !mounted ) return;
      _bloc.startPolling();
      // The route says the pane is on screen. The mixin refreshes once now and
      // then holds the interval while the app stays foregrounded.
      _bloc.onPaneVisible();
    } );
  }

  @override
  void dispose() {
    // The SAVED reference — see the field's docstring. This stops the timer and
    // cancels the in-flight request rather than letting either outlive the route.
    _bloc.onPaneHidden();
    super.dispose();
  }

  /// Push the Live Console for one seat.
  ///
  /// ⚠️ AN ORDINARY `MaterialPageRoute`, LIKE EVERY OTHER PUSH IN THIS APP, and the
  /// console's bloc will be created INSIDE it in slice 3 — not at the app root. That is
  /// the same route-scoping decision this screen's own docstring explains, and C5.11 is
  /// the test that makes it mean something: pop the route, emit a frame for that seat, and
  /// no bloc is alive to receive it. An app-root console bloc would keep its watch open
  /// after the operator walked away, and the obvious test would pass anyway.
  ///
  /// The id is read off the session rather than passed down from the roster, because the
  /// roster's only job was to say WHETHER this seat is watchable — the fleet row is where
  /// the id lives. `_watchTapFor` has already proven it is non-null by finding it in the
  /// roster set, so the `!` here cannot fire: a row with a null id never gets a button.
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

          // 🔴 A TRANSPORT FAILURE IS NOT AN UNREACHABLE ARBITER. This branch
          // means THIS PHONE could not reach :7999. The envelope inside
          // `composite` means :7999 is fine and :8001 is not. Both end in an
          // empty table and only one is a reason to restart something, so they
          // get different screens — see FleetStatusPane for the other.
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
            // Null when no console factory was threaded in: no factory, no route, no button.
            onWatch             : widget.consoleBlocFactory == null
                ? null
                : ( session ) => _openConsole( context, session ),
          );
        },
      ),
    );
  }
}
