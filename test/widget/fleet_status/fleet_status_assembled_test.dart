/// THE ASSEMBLED PANE, DRIVEN AT THE OPERATOR'S ALTITUDE — row a1962a5b,
/// requested by Tiffany 2026-09-19 21:06 EDT.
///
/// Every other fleet_status test hands in the layer below the one it exercises:
/// `fleet_status_pane_test` drives the real dial against a callback IT supplies,
/// `fleet_status_bloc_test` calls `setCap` directly against a fake repository,
/// and `fleet_status_screen_test` swaps the repository out. Each proves one
/// half while supplying the other, so ALL THREE STAY GREEN if the screen's
/// `onSetCap` closure is wired to the wrong bloc method — the dial still
/// renders, the callback is still non-null, and nothing follows the operator's
/// finger to the network. That is the shape of bug 9adff476.
///
/// So this file substitutes NOTHING above the socket. Real screen, real bloc,
/// real `FleetRepository`, real `Dio` — only the HTTP adapter is swapped, for
/// `StubAdapter`, which records every `RequestOptions` it is asked to send.
/// The assertions are therefore about A REQUEST THAT APPEARED: its method, its
/// path and its body.
///
/// ⚠️ NO pumpAndSettle IN THIS FILE — the screen runs a 60-second
/// `Timer.periodic`, so it never settles. Every wait is an explicit `pump`, and
/// every test pops the route.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/fleet_status/data/fleet_repository.dart';
import 'package:lupin_mobile/features/fleet_status/domain/fleet_status_bloc.dart';
import 'package:lupin_mobile/features/fleet_status/presentation/fleet_status_screen.dart';

import '../../unit/_helpers/stub_dio.dart';

void main() {
  late Map<String, Object?> liveJson;

  setUpAll( () {
    final f = File( "test/fixtures/fleet_status/fleet_state_live_2026.09.19.json" );
    liveJson = jsonDecode( f.readAsStringSync() ) as Map<String, Object?>;
  } );

  /// The live capture with ONE row's verdict rewritten to "offline".
  ///
  /// Said plainly because it matters: the live fleet contained no offline seat
  /// (it reported LIVE, "quiet 3m" and "stale 21m"), so this one cell is
  /// synthetic. Every other field on every row is the real producer's, and the
  /// point of the exercise — that a free-form verdict string of exactly
  /// "offline" is what the filter keys on, while "stale 21m" is a seat to chase
  /// rather than hide — needs a row in that state to have anything to assert.
  Map<String, Object?> withOneOfflineRow() {
    final copy     = jsonDecode( jsonEncode( liveJson ) ) as Map<String, Object?>;
    final arbiter  = copy[ "fleet_arbiter" ] as Map<String, Object?>;
    final sessions = ( arbiter[ "sessions" ] as List ).cast<Map<String, Object?>>();
    final target   = sessions.firstWhere( ( r ) => r[ "persona" ] == "maria" );
    ( target[ "liveness" ] as Map<String, Object?> )[ "verdict" ] = "offline";
    return copy;
  }

  ( StubAdapter, Future<void> Function( WidgetTester ) ) harness(
    Map<String, Object?> state, {
    int cap        = 9,
    int capMaximum = 20,
  } ) {
    final adapter = StubAdapter( {
      "GET ${ FleetRepository.fleetStateEndpoint }"   : ( _ ) => jsonBody( state ),
      "GET ${ FleetRepository.fleetSizeCapEndpoint }" : ( _ ) =>
          jsonBody( { "cap": cap, "maximum": capMaximum } ),
      // 🔴 THE SERVER ANSWERS cap+1, NEVER AN ECHO. An echoing stub cannot fail
      // the assertion that the screen displays the server's RE-READ, so it
      // would be asserting nothing — and the cap really is re-read fresh from
      // disk on the spawn path, so the two can differ in production.
      "PUT ${ FleetRepository.fleetSizeCapEndpoint }" : ( req ) {
        final posted = ( req.data as Map )[ "cap" ] as int;
        return jsonBody( { "cap": posted + 1, "maximum": capMaximum } );
      },
    } );

    Future<void> pump( WidgetTester tester ) async {
      tester.view.physicalSize     = const Size( 360, 800 );
      tester.view.devicePixelRatio = 1.0;
      addTearDown( tester.view.resetPhysicalSize );
      addTearDown( tester.view.resetDevicePixelRatio );

      addTearDown( () async {
        final open = find.byType( FleetStatusScreen );
        if ( open.evaluate().isNotEmpty ) {
          Navigator.of( tester.element( open ) ).pop();
          await tester.pump( const Duration( milliseconds: 50 ) );
        }
      } );

      // Nothing between the screen and the socket is a test double.
      final repo = FleetRepository( makeDio( adapter ) );

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

      await tester.tap( find.text( "open" ) );
      await tester.pump();                                     // start the transition
      await tester.pump( const Duration( milliseconds: 400 ) ); // run it out
      await tester.pump();                                     // first build
      await tester.pump( const Duration( milliseconds: 50 ) );  // the poll lands
    }

    return ( adapter, pump );
  }

  group( "🔴 the dial — a request APPEARED on the wire", () {
    testWidgets( "apply issues PUT /api/arbiter/fleet-size-cap with the dragged cap", ( tester ) async {
      final ( adapter, pump ) = harness( liveJson );
      await pump( tester );

      // Nothing has been written yet — the two reads are the poll.
      expect(
        adapter.captured.where( ( r ) => r.method == "PUT" ), isEmpty,
        reason: "opening the pane must not write anything",
      );

      await tester.drag( find.byType( Slider ), const Offset( 200, 0 ) );
      await tester.pump();

      final dragged = int.parse(
        tester.widget<Text>( find.byKey( const Key( TestKeys.fleetStatusCapValue ) ) ).data!,
      );
      expect( dragged, isNot( 9 ), reason: "the drag must have moved the handle" );

      await tester.tap( find.byKey( const Key( TestKeys.fleetStatusCapApply ) ) );
      await tester.pump();
      await tester.pump( const Duration( milliseconds: 50 ) );

      final writes = adapter.captured.where( ( r ) => r.method == "PUT" ).toList();
      expect( writes.length, 1, reason: "one apply, one write" );
      expect( writes.single.path, FleetRepository.fleetSizeCapEndpoint );
      expect(
        writes.single.data, { "cap": dragged },
        reason: "the body carries exactly the operator's dragged value. The "
                "endpoint's contract is {cap: int >= 1} and nothing else.",
      );
    } );

    testWidgets( "and the handle then shows the SERVER'S re-read", ( tester ) async {
      final ( adapter, pump ) = harness( liveJson );
      await pump( tester );

      await tester.drag( find.byType( Slider ), const Offset( 200, 0 ) );
      await tester.pump();
      await tester.tap( find.byKey( const Key( TestKeys.fleetStatusCapApply ) ) );
      await tester.pump();
      await tester.pump( const Duration( milliseconds: 50 ) );

      final posted = ( adapter.captured
          .lastWhere( ( r ) => r.method == "PUT" ).data as Map )[ "cap" ] as int;

      expect(
        tester.widget<Text>( find.byKey( const Key( TestKeys.fleetStatusCapValue ) ) ).data,
        "${ posted + 1 }",
        reason: "displaying the POSTED value would show the operator a number "
                "the fleet is not enforcing",
      );
    } );
  } );

  group( "🔴 the offline toggle — the real filter, in the assembled pane", () {
    testWidgets( "hides an offline seat and brings it back, with no request either way", ( tester ) async {
      final ( adapter, pump ) = harness( withOneOfflineRow() );
      await pump( tester );

      // The row key is the WHO cell — the persona when there is one
      // (`fleet_row_card.dart:42` over `whoLabel`), not the session id.
      const offlineRow = Key( "${ TestKeys.fleetStatusRowPrefix }maria" );
      const liveRow    = Key( "${ TestKeys.fleetStatusRowPrefix }mr radio" );

      // Prove the instrument can find a row at all before trusting an absence:
      // a test that asserts "hidden" against a pane rendering nothing passes
      // for the wrong reason.
      expect(
        find.byKey( liveRow ), findsOneWidget,
        reason: "the table is rendering rows",
      );
      expect( find.byKey( offlineRow ), findsNothing, reason: "offline is hidden by default" );

      final readsBefore = adapter.captured.length;

      await tester.tap( find.byKey( const Key( TestKeys.fleetStatusOfflineToggle ) ) );
      await tester.pump();
      // ⚠️ `ListView.builder` only builds what is on screen, and at 360x800 the
      // revealed row can sit below the fold — genuinely absent from the tree,
      // not merely invisible. Scroll to it before reading its presence.
      await tester.scrollUntilVisible(
        find.byKey( offlineRow ), 120,
        scrollable: find.descendant(
          of       : find.byKey( const Key( TestKeys.fleetStatusList ) ),
          matching : find.byType( Scrollable ),
        ).first,
      );
      expect( find.byKey( offlineRow ), findsOneWidget, reason: "the toggle reveals it" );

      await tester.tap( find.byKey( const Key( TestKeys.fleetStatusOfflineToggle ) ) );
      await tester.pump();
      expect( find.byKey( offlineRow ), findsNothing, reason: "and hides it again" );

      expect(
        adapter.captured.length, readsBefore,
        reason: "filtering is client-side over rows already held. A toggle that "
                "re-queried would cost a round trip per flick and could show a "
                "different fleet on the way back.",
      );
    } );

    testWidgets( "🔴 a STALE seat is not an offline seat — it stays visible", ( tester ) async {
      // The verdict is a FREE-FORM STRING, not an enum: the live fleet reported
      // "LIVE", "quiet 3m" and "stale 21m". The filter keys on exactly
      // "offline", and a row with no verdict at all stays LIVE
      // (fleetModel.ts:155). A first cut that treated stale-or-missing as
      // offline would have hidden every seat the arbiter had not yet judged —
      // and a stale seat is one to CHASE, not to hide.
      final ( _, pump ) = harness( withOneOfflineRow() );
      await pump( tester );

      const staleRow = Key( "${ TestKeys.fleetStatusRowPrefix }Krishna" );
      await tester.scrollUntilVisible(
        find.byKey( staleRow ), 120,
        scrollable: find.descendant(
          of       : find.byKey( const Key( TestKeys.fleetStatusList ) ),
          matching : find.byType( Scrollable ),
        ).first,
      );

      expect( find.byKey( staleRow ), findsOneWidget,
              reason: '"stale 21m" stays visible with the offline filter ON' );
    } );
  } );
}
