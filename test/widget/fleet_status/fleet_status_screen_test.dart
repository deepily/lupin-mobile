import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/fleet_status/data/fleet_models.dart';
import 'package:lupin_mobile/features/fleet_status/data/fleet_repository.dart';
import 'package:lupin_mobile/features/fleet_status/domain/fleet_status_bloc.dart';
import 'package:lupin_mobile/features/fleet_status/presentation/fleet_status_screen.dart';

/// Counts what the screen actually asks the network for.
class _CountingRepo implements FleetRepository {
  int stateCalls = 0;
  Object? stateThrows;
  final FleetComposite composite;

  _CountingRepo( this.composite );

  @override
  Future<FleetComposite> fetchState( { CancelToken? cancelToken } ) async {
    stateCalls++;
    if ( stateThrows != null ) throw stateThrows!;
    return composite;
  }

  @override
  Future<Map<String, Object?>> fetchSizeCap( { CancelToken? cancelToken } ) async =>
      { "cap": 9, "maximum": 20 };

  /// What the DIAL actually posted, and what the screen got back. The answer
  /// is cap+1 and never an echo: an echoing fake cannot fail the assertion that
  /// the screen shows the SERVER'S re-read, so it would be testing nothing.
  int? postedCap;

  @override
  Future<Map<String, Object?>> setSizeCap( int cap ) async {
    postedCap = cap;
    return { "cap": cap + 1, "maximum": 20 };
  }
}

// ⚠️ NO pumpAndSettle IN THIS FILE, AND THAT IS NOT A STYLE CHOICE. The screen
// starts a 60-second `Timer.periodic` the moment the route opens, so
// `pumpAndSettle` never settles — it waits for a quiescent frame that a live
// poller will not produce and fails with "a Timer is still pending". Every
// wait here is an explicit `pump( duration )`.
void main() {
  late FleetComposite live;

  setUpAll( () {
    final f = File( "test/fixtures/fleet_status/fleet_state_live_2026.09.19.json" );
    live = FleetComposite.fromJson( jsonDecode( f.readAsStringSync() ) );
  } );

  Future<void> pumpApp( WidgetTester tester, _CountingRepo repo ) async {
    tester.view.physicalSize     = const Size( 360, 800 );
    tester.view.devicePixelRatio = 1.0;
    addTearDown( tester.view.resetPhysicalSize );
    addTearDown( tester.view.resetDevicePixelRatio );

    // 🔴 EVERY TEST MUST LEAVE THE ROUTE, or the 60-second Timer.periodic the
    // screen starts is still pending at teardown and the framework fails the
    // test on that rather than on anything it asserts. Popping is not test
    // hygiene invented for the harness: it is the path the app takes when the
    // operator presses back, and it is what disposes the BlocProvider, closes
    // the bloc, cancels the timer and cancels the in-flight request.
    addTearDown( () async {
      final open = find.byType( FleetStatusScreen );
      if ( open.evaluate().isNotEmpty ) {
        Navigator.of( tester.element( open ) ).pop();
        await tester.pump( const Duration( milliseconds: 50 ) );
      }
    } );

    await tester.pumpWidget( MaterialApp(
      home: Builder(
        builder: ( context ) => Scaffold(
          body: Center(
            child: ElevatedButton(
              child: const Text( "open" ),
              onPressed: () => Navigator.of( context ).push( MaterialPageRoute(
                builder: ( _ ) => FleetStatusScreen(
                  blocFactory: ( _ ) => FleetStatusBloc( repo ),
                ),
              ) ),
            ),
          ),
        ),
      ),
    ) );
  }

  /// Run a MaterialPageRoute transition to completion WITHOUT pumpAndSettle,
  /// which never settles against the screen's live 60-second poller.
  Future<void> openRoute( WidgetTester tester ) async {
    await tester.pump();                                    // start the transition
    await tester.pump( const Duration( milliseconds: 400 ) ); // run it out
    await tester.pump();                                    // let the first build land
  }

  group( "🔴 route-scoping IS the zero-request guard", () {
    testWidgets( "a destination never opened issues zero requests", ( tester ) async {
      final repo = _CountingRepo( live );
      await pumpApp( tester, repo );
      await tester.pump( const Duration( milliseconds: 100 ) );

      // The bloc does not exist yet, so it cannot poll. This is the property an
      // app-root BlocProvider would NOT have, and the reason this route departs
      // from the app's convention.
      expect( repo.stateCalls, 0 );
    } );

    testWidgets( "opening it polls once; leaving it stops", ( tester ) async {
      final repo = _CountingRepo( live );
      await pumpApp( tester, repo );

      await tester.tap( find.text( "open" ) );
      await openRoute( tester );
      expect( repo.stateCalls, 1, reason: "visible → refresh once, immediately" );

      // Pop the route. Disposal must cancel the timer, so no further request
      // can arrive however long we wait.
      final before = repo.stateCalls;
      Navigator.of( tester.element( find.byType( FleetStatusScreen ) ) ).pop();
      await tester.pump( const Duration( milliseconds: 300 ) );
      await tester.pump( const Duration( seconds: 2 ) );

      expect( repo.stateCalls, before, reason: "a popped route must not poll" );
    } );
  } );

  group( "the screen's own states", () {
    testWidgets( "a transport failure is NOT the unreachable-arbiter screen", ( tester ) async {
      // Two different facts: this branch means the PHONE could not reach :7999.
      // The envelope means :7999 is fine and :8001 is not.
      final repo = _CountingRepo( live )
        ..stateThrows = const FleetApiException( "Connection refused" );
      await pumpApp( tester, repo );

      await tester.tap( find.text( "open" ) );
      await openRoute( tester );

      expect( find.text( "Could not reach the server" ), findsOneWidget );
      expect( find.textContaining( "Connection refused" ), findsOneWidget );
      expect( find.byKey( const Key( TestKeys.fleetStatusUnreachable ) ), findsNothing );
      expect( find.text( "Retry" ), findsOneWidget );
    } );

    testWidgets( "Retry re-issues the request", ( tester ) async {
      final repo = _CountingRepo( live )
        ..stateThrows = const FleetApiException( "Connection refused" );
      await pumpApp( tester, repo );

      await tester.tap( find.text( "open" ) );
      await openRoute( tester );
      final afterOpen = repo.stateCalls;

      await tester.tap( find.text( "Retry" ) );
      await tester.pump( const Duration( milliseconds: 300 ) );

      expect( repo.stateCalls, greaterThan( afterOpen ) );
    } );

    testWidgets( "a successful open renders the pane and its rows", ( tester ) async {
      final repo = _CountingRepo( live );
      await pumpApp( tester, repo );

      await tester.tap( find.text( "open" ) );
      await openRoute( tester );

      expect( find.text( "Fleet Status" ), findsOneWidget );
      expect( find.byKey( const Key( TestKeys.fleetStatusList ) ), findsOneWidget );
      // The dial is present because the screen supplies onSetCap.
      expect( find.byKey( const Key( TestKeys.fleetStatusCapDial ) ), findsOneWidget );
    } );

    testWidgets( "the unreachable ENVELOPE gets the pane's screen, not the transport one", ( tester ) async {
      final repo = _CountingRepo( FleetComposite.fromJson( const {
        "status": "unreachable", "fleet_arbiter": null,
      } ) );
      await pumpApp( tester, repo );

      await tester.tap( find.text( "open" ) );
      await openRoute( tester );

      expect( find.byKey( const Key( TestKeys.fleetStatusUnreachable ) ), findsOneWidget );
      expect( find.text( "Could not reach the server" ), findsNothing );
    } );
  } );

  group( "🔴 the dial's SEAM — the handle all the way through to the repository", () {
    // WHY THIS EXISTS, since three other files look like they cover it.
    // `fleet_status_pane_test` drives the real dial against a callback IT
    // supplies; `fleet_status_bloc_test` calls `setCap` directly and watches
    // the repository. Each proves one half while handing in the other, so
    // BOTH stay green if the screen's `onSetCap` closure is wired to the wrong
    // thing — the dial still renders, the callback is still non-null, and no
    // assertion anywhere follows the operator's drag to the network. That is
    // the shape of bug 9adff476, and Tiffany named it before it bit.
    testWidgets( "dragging and applying reaches setSizeCap with the dragged value", ( tester ) async {
      final repo = _CountingRepo( live );
      await pumpApp( tester, repo );

      await tester.tap( find.text( "open" ) );
      await openRoute( tester );

      // The dial only exists once a cap has landed, so let the first poll
      // resolve before reaching for it.
      await tester.pump( const Duration( milliseconds: 50 ) );

      await tester.drag( find.byType( Slider ), const Offset( 200, 0 ) );
      await tester.pump();

      final dragged = int.parse(
        tester.widget<Text>( find.byKey( const Key( TestKeys.fleetStatusCapValue ) ) ).data!,
      );
      expect( dragged, isNot( 9 ), reason: "the drag must have moved the handle" );

      await tester.tap( find.byKey( const Key( TestKeys.fleetStatusCapApply ) ) );
      await tester.pump();
      await tester.pump( const Duration( milliseconds: 50 ) );

      expect(
        repo.postedCap, dragged,
        reason: "the operator's drag must arrive at the repository unchanged. "
                "Point the screen's onSetCap at any other bloc method and this "
                "stays null while every other fleet_status test stays green.",
      );
    } );

    testWidgets( "and the handle then shows the SERVER'S re-read, not the posted value", ( tester ) async {
      final repo = _CountingRepo( live );
      await pumpApp( tester, repo );

      await tester.tap( find.text( "open" ) );
      await openRoute( tester );
      await tester.pump( const Duration( milliseconds: 50 ) );

      await tester.drag( find.byType( Slider ), const Offset( 200, 0 ) );
      await tester.pump();
      await tester.tap( find.byKey( const Key( TestKeys.fleetStatusCapApply ) ) );
      await tester.pump();
      await tester.pump( const Duration( milliseconds: 50 ) );

      // The fake answers cap+1. The cap is re-read fresh from disk on the spawn
      // path, so the number enforced really can differ from the number posted —
      // showing the posted one would show a number the fleet is not enforcing.
      expect(
        tester.widget<Text>( find.byKey( const Key( TestKeys.fleetStatusCapValue ) ) ).data,
        "${ repo.postedCap! + 1 }",
      );
    } );
  } );
}
