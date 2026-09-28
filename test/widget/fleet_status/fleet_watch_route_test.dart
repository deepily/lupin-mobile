import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/fleet_status/data/fleet_models.dart';
import 'package:lupin_mobile/features/fleet_status/data/fleet_repository.dart';
import 'package:lupin_mobile/features/fleet_status/data/fleet_watchable_models.dart';
import 'package:lupin_mobile/features/fleet_status/domain/fleet_status_bloc.dart';
import 'package:lupin_mobile/features/fleet_status/presentation/fleet_status_screen.dart';
import 'package:lupin_mobile/features/transcript/data/transcript_models.dart';
import 'package:lupin_mobile/features/transcript/data/transcript_repository.dart';
import 'package:lupin_mobile/features/transcript/domain/transcript_frame_router.dart';
import 'package:lupin_mobile/features/transcript/domain/transcript_stream_bloc.dart';
import 'package:lupin_mobile/features/transcript/presentation/live_console_screen.dart';

/// C5.9's tap arm, driven from the SCREEN rather than the pane — the seam where the roster
/// read, the join, the button and the route all have to agree.
///
/// 🔴 THE PANE-LEVEL TEST CANNOT SEE THIS, AND THAT IS THE WHOLE REASON THIS FILE EXISTS.
/// `fleet_watch_button_test.dart` hands `FleetStatusPane` a `watchableSessionIds` set
/// directly, so it proves the join and the button given a roster. It says nothing about
/// whether anything ever FETCHES that roster, puts it in the state, or pushes a route. A
/// build where `fetchWatchable` is never called, or where `onWatch` is wired to nothing,
/// passes every assertion in that file. This one drives the real `FleetStatusBloc` over a
/// fake repository, taps the button that results, and lands on the real console route.
///
/// ⚠️ `pumpAndSettle` NEVER SETTLES HERE. The screen starts a 60-second `Timer.periodic`,
/// so there is no quiescent frame to wait for and the framework fails the test on "a Timer
/// is still pending" rather than on anything it asserts. Every wait below is an explicit
/// `pump( duration )` — the same shape `fleet_status_screen_test.dart` uses, and for the
/// same reason.
void main() {
  const fullId = "6bf7cfa9-964e-4cef-a5d9-a804a4d75874";
  const who    = "maya";

  FleetComposite composite() => const FleetComposite(
    status   : "ok",
    sessions : [
      FleetSession(
        sessionId : fullId,
        persona   : who,
        state     : "working",
        role      : "implementer",
        liveness  : FleetLiveness( verdict: "live", freshestAgeS: 3 ),
      ),
    ],
    personas : {},
  );

  Future<void> pumpApp( WidgetTester tester, _RosterRepo repo ) async {
    tester.view.physicalSize     = const Size( 360, 800 );
    tester.view.devicePixelRatio = 1.0;
    addTearDown( tester.view.resetPhysicalSize );
    addTearDown( tester.view.resetDevicePixelRatio );

    // 🔴 EVERY TEST MUST LEAVE THE ROUTE, or the screen's 60-second timer is still pending
    // at teardown. Popping is not harness hygiene: it is the path the app takes when the
    // operator presses back, and it is what disposes the BlocProvider, closes the bloc and
    // cancels the timer and the in-flight request.
    addTearDown( () async {
      for ( var i = 0; i < 2; i++ ) {
        final open = find.byType( FleetStatusScreen );
        if ( open.evaluate().isEmpty ) break;
        final nav = Navigator.of( tester.element( open ) );
        if ( !nav.canPop() ) break;
        nav.pop();
        await tester.pump( const Duration( milliseconds: 50 ) );
      }
    } );

    await tester.pumpWidget( MaterialApp(
      home: Builder(
        builder: ( context ) => Scaffold(
          body: Center(
            child: ElevatedButton(
              child     : const Text( "open" ),
              onPressed : () => Navigator.of( context ).push( MaterialPageRoute<void>(
                builder: ( _ ) => FleetStatusScreen(
                  blocFactory: ( _ ) => FleetStatusBloc( repo ),
                  // Slice 3 threaded the console's bloc factory through this screen, so a
                  // test that taps the watch button must supply one — a real bloc over a
                  // fake repository, since what is under test is the ROUTE, not the stream.
                  consoleBlocFactory: ( _, id ) => TranscriptStreamBloc(
                    ccSessionId : id,
                    repository  : TranscriptRepository( Dio() ),
                    router      : TranscriptFrameRouter(),
                    send        : ( _ ) async {},
                  ),
                ),
              ) ),
            ),
          ),
        ),
      ),
    ) );
  }

  /// Run a `MaterialPageRoute` transition out without `pumpAndSettle`.
  Future<void> runRoute( WidgetTester tester ) async {
    await tester.pump();                                        // start the transition
    await tester.pump( const Duration( milliseconds: 400 ) );    // run it out
    await tester.pump();                                        // let the first build land
  }

  Future<void> openFleet( WidgetTester tester ) async {
    await tester.tap( find.text( "open" ) );
    await runRoute( tester );
    // The first poll is awaited by the bloc; give the Loaded event a frame to land.
    await tester.pump( const Duration( milliseconds: 50 ) );
    await tester.pump();
  }

  Finder watchButton() =>
      find.byKey( Key( "${ TestKeys.fleetStatusWatchPrefix }$who" ) );

  testWidgets( "the screen reads the roster and the button opens the console",
      ( tester ) async {
    final repo = _RosterRepo(
      composite(),
      roster: FleetWatchableRoster.fromJson( {
        "status"   : "ok",
        "sessions" : [ { "session_id": fullId, "transcript_watchable": true } ],
      } ),
    );

    await pumpApp( tester, repo );
    await openFleet( tester );

    expect( repo.watchableCalls, greaterThanOrEqualTo( 1 ),
        reason: "the roster must actually be fetched. A build that never calls "
                "fetchWatchable passes every pane-level test" );
    expect( watchButton(), findsOneWidget );

    await tester.tap( watchButton() );
    await runRoute( tester );

    expect( find.byType( LiveConsoleScreen ), findsOneWidget,
        reason: "the button must push the console route, not merely be tappable" );
    expect( find.byKey( const Key( TestKeys.liveConsoleScreen ) ), findsOneWidget );

    // 🔴 THE CONSOLE OPENED FOR THE RIGHT SEAT, AT THE RIGHT WIDTH. §3 pins `cc_session_id`
    // to the seat's full `stable_session_id`; an 8-hex id here would be a watch the server
    // cannot resolve. The title carries the persona and the bloc carries the id, so both are
    // asserted rather than just the one that is easy to see.
    expect( find.text( "Console — $who" ), findsOneWidget );

    final consoleBloc = BlocProvider.of<TranscriptStreamBloc>(
      tester.element( find.byKey( const Key( TestKeys.liveConsoleScreen ) ) ),
    );
    expect( consoleBloc.ccSessionId, fullId );

    // Back out of the console so the tear-down finds the fleet screen on top.
    Navigator.of( tester.element( find.byType( LiveConsoleScreen ) ) ).pop();
    await tester.pump( const Duration( milliseconds: 400 ) );
  } );

  testWidgets( "a roster the server refuses leaves no button on the screen",
      ( tester ) async {
    // 403 is the ordinary case for a non-admin operator, and `fetchWatchable` turns it
    // into `none` rather than an exception. The table must still render.
    final repo = _RosterRepo( composite(), roster: FleetWatchableRoster.none );

    await pumpApp( tester, repo );
    await openFleet( tester );

    expect( find.byKey( const Key( TestKeys.fleetStatusList ) ), findsOneWidget,
        reason: "a refused roster must not break the pane it rides along with" );
    expect( watchButton(), findsNothing );
  } );

  // 🔴 THE BUG THIS ROW EXISTS FOR, AND I WROTE IT BEFORE I CAUGHT IT. `setCap` re-emits
  // `FleetStatusLoaded` to carry the server's re-read of the dial. With a non-nullable
  // `watchable` field defaulting to `none`, that emit wiped every watch button off the pane
  // on any cap change — a control vanishing because an unrelated number moved. Nothing in
  // §5's acceptance rows exercises "move the cap, then look at the buttons".
  testWidgets( "moving the fleet-size cap does NOT remove the watch buttons",
      ( tester ) async {
    final repo = _RosterRepo(
      composite(),
      roster: FleetWatchableRoster.fromJson( {
        "sessions": [ { "session_id": fullId, "transcript_watchable": true } ],
      } ),
    );

    await pumpApp( tester, repo );
    await openFleet( tester );
    expect( watchButton(), findsOneWidget );

    // Drive the write directly rather than through the dial's gesture: the dial is another
    // widget's test, and what is under test here is what `setCap`'s Loaded event does to
    // the watchable set.
    final bloc = BlocProvider.of<FleetStatusBloc>(
      tester.element( find.byKey( const Key( TestKeys.fleetStatusList ) ) ),
    );
    await bloc.setCap( 12 );
    await tester.pump();
    await tester.pump();

    expect( bloc.state.cap, 13, reason: "the fake answers cap+1, never an echo" );
    expect( watchButton(), findsOneWidget,
        reason: "the cap moved; watchability did not. A Loaded event that carries no "
                "roster must leave the set alone rather than emptying it" );
  } );
}

/// A repository whose roster the test dictates, and which counts the roster read.
class _RosterRepo implements FleetRepository {
  final FleetComposite       composite;
  final FleetWatchableRoster roster;

  int watchableCalls = 0;
  int serverCap      = 9;

  _RosterRepo( this.composite, { required this.roster } );

  @override
  Future<FleetComposite> fetchState( { CancelToken? cancelToken } ) async => composite;

  @override
  Future<FleetWatchableRoster> fetchWatchable( { CancelToken? cancelToken } ) async {
    watchableCalls++;
    return roster;
  }

  @override
  Future<Map<String, Object?>> fetchSizeCap( { CancelToken? cancelToken } ) async =>
      { "cap": serverCap, "maximum": 20 };

  /// The server RE-READS and answers with what it found; it does not echo. A fake that
  /// echoed could not fail the assertion that the dial shows the server's number.
  @override
  Future<Map<String, Object?>> setSizeCap( int cap ) async {
    serverCap = cap + 1;
    return { "cap": serverCap, "maximum": 20 };
  }
}
