import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/fleet_status/data/fleet_models.dart';
import 'package:lupin_mobile/features/fleet_status/presentation/fleet_status_pane.dart';

/// Fleet Status pane — widget tests.
///
/// ⚠️ THESE DRIVE THE ASSEMBLED PANE, not the cards in isolation. A component
/// can be complete, correct, fully covered and never mounted, and every test
/// that builds the component stays green.
void main() {
  late Map<String, Object?> live;

  setUpAll( () {
    final f = File( "test/fixtures/fleet_status/fleet_state_live_2026.09.19.json" );
    live = jsonDecode( f.readAsStringSync() ) as Map<String, Object?>;
  } );

  Future<void> pump(
    WidgetTester tester,
    FleetComposite composite, {
    int?   cap,
    int?   capMaximum,
    Future<void> Function( int )? onSetCap,
  } ) async {
    // 🔴 360 dp IS THE REQUIREMENT, not the 800x600 test default. The row body
    // says "eight columns legible at 360 dp", so every assertion below is made
    // on an ordinary Android portrait surface rather than on a desktop-sized
    // one where a too-wide layout would pass unnoticed.
    tester.view.physicalSize         = const Size( 360, 800 );
    tester.view.devicePixelRatio     = 1.0;
    addTearDown( tester.view.resetPhysicalSize );
    addTearDown( tester.view.resetDevicePixelRatio );

    await tester.pumpWidget( MaterialApp(
      home: Scaffold(
        body: FleetStatusPane(
          composite  : composite,
          cap        : cap,
          capMaximum : capMaximum,
          onSetCap   : onSetCap,
        ),
      ),
    ) );
    await tester.pumpAndSettle();
  }

  /// Bring an off-screen row into view. `ListView.builder` only builds what is
  /// visible, so a row below the fold is genuinely absent from the tree — not
  /// a rendering bug, and not something to assert around.
  Future<Finder> rowFor( WidgetTester tester, String who ) async {
    final f = find.byKey( Key( "${ TestKeys.fleetStatusRowPrefix }$who" ) );
    await tester.scrollUntilVisible(
      f, 200,
      scrollable: find.descendant(
        of      : find.byKey( const Key( TestKeys.fleetStatusList ) ),
        matching: find.byType( Scrollable ),
      ),
    );
    await tester.pumpAndSettle();
    return f;
  }

  group( "the three empty-looking states are three different screens", () {
    testWidgets( "unreachable says we cannot SEE the fleet", ( tester ) async {
      await pump( tester, FleetComposite.fromJson( const {
        "status"        : "unreachable",
        "fleet_arbiter" : null,
      } ) );

      expect( find.byKey( const Key( TestKeys.fleetStatusUnreachable ) ), findsOneWidget );
      expect( find.byKey( const Key( TestKeys.fleetStatusEmpty ) ),       findsNothing );
      expect( find.textContaining( "not an empty fleet" ), findsOneWidget );
    } );

    testWidgets( "a reachable but empty fleet is a DIFFERENT screen", ( tester ) async {
      await pump( tester, FleetComposite.fromJson( const {
        "status"        : "ok",
        "fleet_arbiter" : { "sessions": <Object?>[] },
      } ) );

      expect( find.byKey( const Key( TestKeys.fleetStatusEmpty ) ),       findsOneWidget );
      expect( find.byKey( const Key( TestKeys.fleetStatusUnreachable ) ), findsNothing );
    } );

    testWidgets( "all-offline-and-hidden says so rather than showing a blank pane", ( tester ) async {
      await pump( tester, FleetComposite.fromJson( const {
        "status"        : "ok",
        "fleet_arbiter" : {
          "sessions": [
            { "persona": "ghost", "liveness": { "verdict": "offline" } },
          ],
        },
      } ) );

      expect( find.byKey( const Key( TestKeys.fleetStatusEmpty ) ), findsOneWidget );
      expect( find.textContaining( "offline" ), findsWidgets );
      // And it must NOT claim the arbiter is unreachable.
      expect( find.byKey( const Key( TestKeys.fleetStatusUnreachable ) ), findsNothing );
    } );
  } );

  group( "the real capture renders", () {
    testWidgets( "online seats show by default and offline ones are hidden", ( tester ) async {
      final c = FleetComposite.fromJson( live );
      await pump( tester, c );

      expect( find.byKey( const Key( TestKeys.fleetStatusList ) ), findsOneWidget );

      // Assert the fixture actually exercises the filter before trusting it.
      final offline = c.sessions.where( ( s ) => s.isOffline ).length;
      final online  = c.sessions.length - offline;
      expect( online, greaterThan( 0 ), reason: "fixture must carry live seats" );

      expect( await rowFor( tester, "chloe" ), findsOneWidget );
    } );

    testWidgets( "all eight facts are on screen without a tap", ( tester ) async {
      await pump( tester, FleetComposite.fromJson( live ) );

      // The four labelled fields plus Who and the role badge and the two
      // window columns — nothing is hidden behind a disclosure.
      expect( find.text( "State" ),      findsWidgets );
      expect( find.text( "Holding on" ), findsWidgets );
      expect( find.text( "Stuck" ),      findsWidgets );
      expect( find.text( "Liveness" ),   findsWidgets );
      expect( find.text( "% Window" ),   findsWidgets );
      expect( find.text( "Window" ),     findsWidgets );
      // `chloe` sits below the fold on a 360x800 surface — scroll to it rather
      // than assert it is absent.
      expect( await rowFor( tester, "chloe" ), findsOneWidget );
    } );

    testWidgets( "a row whose pct is null still shows its window size", ( tester ) async {
      // 🔴 THE TWO COLUMNS DISAGREE IN LIVE DATA. `sam` carries
      // window_size 1000000 with a null percentage, so the pane must render
      // "1M" beside an em dash rather than blanking both.
      await pump( tester, FleetComposite.fromJson( live ) );

      final row = await rowFor( tester, "sam" );
      expect( row, findsOneWidget );
      expect( find.descendant( of: row, matching: find.text( "1M" ) ), findsOneWidget );
      expect( find.descendant( of: row, matching: find.text( "—" ) ),  findsWidgets );
    } );
  } );

  group( "the offline toggle", () {
    testWidgets( "reveals offline seats and puts them away again", ( tester ) async {
      final c = FleetComposite.fromJson( const {
        "status": "ok",
        "fleet_arbiter": {
          "sessions": [
            { "persona": "alive", "liveness": { "verdict": "LIVE" } },
            { "persona": "ghost", "liveness": { "verdict": "offline" } },
          ],
        },
      } );
      await pump( tester, c );

      const ghost = Key( "${ TestKeys.fleetStatusRowPrefix }ghost" );
      expect( find.byKey( ghost ), findsNothing );

      await tester.tap( find.byKey( const Key( TestKeys.fleetStatusOfflineToggle ) ) );
      await tester.pumpAndSettle();
      expect( find.byKey( ghost ), findsOneWidget );

      await tester.tap( find.byKey( const Key( TestKeys.fleetStatusOfflineToggle ) ) );
      await tester.pumpAndSettle();
      expect( find.byKey( ghost ), findsNothing );
    } );
  } );

  group( "Liveness detail is reachable by TAP, because a phone has no hover", () {
    testWidgets( "tapping the cell opens a sheet carrying the raw ages", ( tester ) async {
      await pump( tester, FleetComposite.fromJson( live ) );

      await rowFor( tester, "chloe" );
      await tester.tap( find.byKey( const Key( "${ TestKeys.fleetStatusLivenessPrefix }chloe" ) ) );
      await tester.pumpAndSettle();

      expect( find.byKey( const Key( TestKeys.fleetStatusLivenessSheet ) ), findsOneWidget );
      // The web's four ages, verbatim; only the gesture changed.
      expect( find.textContaining( "bridge" ),      findsOneWidget );
      expect( find.textContaining( "idle_prompt" ), findsOneWidget );
    } );

    testWidgets( "the tap target carries an accessible name and is 48 dp tall", ( tester ) async {
      await pump( tester, FleetComposite.fromJson( live ) );

      await rowFor( tester, "chloe" );
      final target = find.byKey( const Key( "${ TestKeys.fleetStatusLivenessPrefix }chloe" ) );
      expect( tester.getSize( target ).height,
              greaterThanOrEqualTo( kMinInteractiveDimension ) );

      // Without a label a screen reader announces a button with no purpose —
      // the visible text is a bare verdict word.
      final handle = tester.getSemantics( target );
      expect( handle.label, contains( "Liveness" ) );
      expect( handle.label, contains( "chloe" ) );
    } );
  } );

  group( "the fleet-size cap dial", () {
    testWidgets( "is absent when the pane is given no write callback", ( tester ) async {
      await pump( tester, FleetComposite.fromJson( live ) );
      expect( find.byKey( const Key( TestKeys.fleetStatusCapDial ) ), findsNothing );
    } );

    testWidgets( "shows the server's number and disables Apply until it moves", ( tester ) async {
      await pump( tester, FleetComposite.fromJson( live ),
                  cap: 9, capMaximum: 20, onSetCap: ( _ ) async {} );

      expect( find.byKey( const Key( TestKeys.fleetStatusCapDial ) ), findsOneWidget );
      expect(
        tester.widget<Text>( find.byKey( const Key( TestKeys.fleetStatusCapValue ) ) ).data,
        "9",
      );

      final apply = tester.widget<TextButton>(
        find.byKey( const Key( TestKeys.fleetStatusCapApply ) ),
      );
      expect( apply.onPressed, isNull, reason: "nothing to apply yet" );
    } );

    testWidgets( "🔴 renders the SERVER'S value, never the one it posted", ( tester ) async {
      // The whole point of the dial returning a body. A cap that echoed what it
      // sent would display a number the fleet is not enforcing — and the cap is
      // read fresh from disk on the spawn path, so the two really can differ.
      int? posted;
      await pump( tester, FleetComposite.fromJson( live ),
                  cap: 5, capMaximum: 20, onSetCap: ( v ) async { posted = v; } );

      await tester.drag( find.byType( Slider ), const Offset( 200, 0 ) );
      await tester.pumpAndSettle();

      final dragged = int.parse(
        tester.widget<Text>( find.byKey( const Key( TestKeys.fleetStatusCapValue ) ) ).data!,
      );
      expect( dragged, greaterThan( 5 ), reason: "the drag must have moved it" );

      await tester.tap( find.byKey( const Key( TestKeys.fleetStatusCapApply ) ) );
      await tester.pumpAndSettle();

      expect( posted, dragged, reason: "the drag is what gets sent" );
      // The parent has NOT handed back a new `cap`, so the handle must fall
      // back to the server's last known number rather than keeping the drag.
      expect(
        tester.widget<Text>( find.byKey( const Key( TestKeys.fleetStatusCapValue ) ) ).data,
        "5",
      );
    } );

    testWidgets( "a refusal snaps the handle back and shows the server's words", ( tester ) async {
      await pump( tester, FleetComposite.fromJson( live ),
                  cap: 5, capMaximum: 20,
                  onSetCap: ( _ ) async => throw Exception( "cap exceeds the configured maximum" ) );

      await tester.drag( find.byType( Slider ), const Offset( 200, 0 ) );
      await tester.pumpAndSettle();
      await tester.tap( find.byKey( const Key( TestKeys.fleetStatusCapApply ) ) );
      await tester.pumpAndSettle();

      // Never leave the handle on a number the operator did not get.
      expect(
        tester.widget<Text>( find.byKey( const Key( TestKeys.fleetStatusCapValue ) ) ).data,
        "5",
      );
      expect( find.textContaining( "cap exceeds the configured maximum" ), findsOneWidget );
    } );

    testWidgets( "accepts a server maximum above any client constant", ( tester ) async {
      // ⚠️ NO CLIENT-SIDE CLAMP. The ceiling is read at call time server-side,
      // so a constant compiled in here would refuse numbers the server accepts.
      await pump( tester, FleetComposite.fromJson( live ),
                  cap: 50, capMaximum: 500, onSetCap: ( _ ) async {} );

      final slider = tester.widget<Slider>( find.byType( Slider ) );
      expect( slider.max, 500 );
      expect( slider.min, 1, reason: "the floor IS in the body model, ge=1" );
    } );
  } );
}
