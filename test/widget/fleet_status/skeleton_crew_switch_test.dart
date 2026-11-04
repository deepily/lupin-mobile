/// The skeleton crew switch beside the fleet cap dial.
///
/// One test per row of the behaviour table in the lupin hand-off note. Bodies are the
/// real captures from the route handlers.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/fleet_status/data/fleet_models.dart';
import 'package:lupin_mobile/features/fleet_status/data/fleet_repository.dart';
import 'package:lupin_mobile/features/fleet_status/domain/fleet_status_bloc.dart';
import 'package:lupin_mobile/features/fleet_status/presentation/fleet_status_pane.dart';
import 'package:lupin_mobile/features/fleet_status/presentation/fleet_status_screen.dart';

import '../../unit/_helpers/stub_dio.dart';

const _refused = "Only an administrator may change the skeleton crew switch.";
const _capRefused = "Only an administrator may set the fleet size cap.";

void main() {
  late Map<String, Map<String, Object?>> wire;
  late Map<String, Object?>              liveJson;

  setUpAll( () {
    final raw = jsonDecode( File(
      "test/fixtures/fleet_status/skeleton_crew_wire_2026.10.10.json" ).readAsStringSync() ) as Map;
    wire     = raw.map( ( k, v ) => MapEntry( k as String, Map<String, Object?>.from( v as Map ) ) );
    liveJson = jsonDecode( File(
      "test/fixtures/fleet_status/fleet_state_live_2026.09.19.json" ).readAsStringSync() )
        as Map<String, Object?>;
  } );

  SkeletonCrew? crew( String name ) => SkeletonCrew.fromCapBody( wire[ name ]![ "body" ] );

  final switchF  = find.byKey( const Key( TestKeys.fleetStatusSkeletonCrewSwitch ) );
  final labelF   = find.byKey( const Key( TestKeys.fleetStatusSkeletonCrewLabel ) );
  final warnF    = find.byKey( const Key( TestKeys.fleetStatusSkeletonCrewWarning ) );
  final errorF   = find.byKey( const Key( TestKeys.fleetStatusSkeletonCrewError ) );
  final dialF    = find.byKey( const Key( TestKeys.fleetStatusCapDial ) );

  String label( WidgetTester t ) => t.widget<Text>( labelF ).data!;
  bool   isOn( WidgetTester t )  => t.widget<Switch>( switchF ).value;
  bool   enabled( WidgetTester t ) => t.widget<Switch>( switchF ).onChanged != null;

  // Pane harness: the parent owns the state, as the screen does.
  Future<void> pumpPane( WidgetTester tester, {
    required SkeletonCrew? skeletonCrew,
    Future<void> Function( bool )? onSet,
    int? cap = 8,
    int? capMaximum = 18,
  } ) async {
    tester.view.physicalSize     = const Size( 360, 800 );
    tester.view.devicePixelRatio = 1.0;
    addTearDown( tester.view.resetPhysicalSize );
    addTearDown( tester.view.resetDevicePixelRatio );
    await tester.pumpWidget( MaterialApp( home: Scaffold( body: FleetStatusPane(
      composite           : FleetComposite.fromJson( liveJson ),
      cap                 : cap,
      capMaximum          : capMaximum,
      onSetCap            : ( _ ) async {},
      skeletonCrew        : skeletonCrew,
      onSetSkeletonCrew   : onSet ?? ( _ ) async {},
    ) ) ) );
    await tester.pumpAndSettle();
  }

  group( "behaviour table — the pane", () {
    testWidgets( "no skeleton_crew in the payload: switch hidden, dial unaffected", ( t ) async {
      await pumpPane( t, skeletonCrew: null );
      expect( switchF, findsNothing );
      expect( labelF, findsNothing );
      expect( dialF, findsOneWidget );
    } );

    testWidgets( "on is false: unchecked, text 'Skeleton crew: OFF'", ( t ) async {
      await pumpPane( t, skeletonCrew: crew( "get_never_flipped" ) );
      expect( isOn( t ), isFalse );
      expect( label( t ), "Skeleton crew: OFF" );
      expect( enabled( t ), isTrue );
    } );

    testWidgets( "on is true: checked, text 'Skeleton crew: ON'", ( t ) async {
      await pumpPane( t, skeletonCrew: crew( "put_on" ) );
      expect( isOn( t ), isTrue );
      expect( label( t ), "Skeleton crew: ON" );
    } );

    testWidgets( "the words carry the state: a switch node named by that text", ( t ) async {
      final handle = t.ensureSemantics();
      await pumpPane( t, skeletonCrew: crew( "put_on" ) );
      final node = t.getSemantics( switchF );
      expect( node.label, contains( "Skeleton crew: ON" ) );
      expect( node.hasFlag( SemanticsFlag.hasToggledState ), isTrue );
      expect( node.hasFlag( SemanticsFlag.isToggled ), isTrue );
      handle.dispose();
    } );

    testWidgets( "flipping shows the requested state, disables, says turning ON…", ( t ) async {
      final gate  = Completer<void>();
      final sent  = <bool>[];
      await pumpPane( t, skeletonCrew: crew( "get_never_flipped" ),
                      onSet: ( v ) { sent.add( v ); return gate.future; } );

      await t.tap( switchF );
      await t.pump();

      expect( sent, [ true ], reason: "one write per flip" );
      expect( isOn( t ), isTrue, reason: "shows the requested state" );
      expect( enabled( t ), isFalse, reason: "disabled until the server answers" );
      expect( label( t ), "Skeleton crew: turning ON…" );

      gate.complete();
      await t.pumpAndSettle();
    } );

    testWidgets( "turning OFF reads 'turning OFF…'", ( t ) async {
      final gate = Completer<void>();
      await pumpPane( t, skeletonCrew: crew( "put_on" ), onSet: ( _ ) => gate.future );
      await t.tap( switchF );
      await t.pump();
      expect( label( t ), "Skeleton crew: turning OFF…" );
      gate.complete();
      await t.pumpAndSettle();
    } );

    testWidgets( "a refusal reports the server's sentence and snaps back to the parent's state",
        ( t ) async {
      await pumpPane( t, skeletonCrew: crew( "get_never_flipped" ),
          onSet: ( _ ) async => throw const FleetApiException( _refused, statusCode: 403 ) );

      await t.tap( switchF );
      await t.pumpAndSettle();

      expect( t.widget<Text>( errorF ).data, _refused, reason: "verbatim, no wrapper text" );
      expect( isOn( t ), isFalse, reason: "the parent still holds OFF" );
      expect( label( t ), "Skeleton crew: OFF" );
      expect( enabled( t ), isTrue );
    } );

    testWidgets( "a network failure also snaps back and says something", ( t ) async {
      await pumpPane( t, skeletonCrew: crew( "put_on" ),
          onSet: ( _ ) async => throw const FleetApiException( "Skeleton crew not saved: offline" ) );
      await t.tap( switchF );
      await t.pumpAndSettle();
      expect( t.widget<Text>( errorF ).data, "Skeleton crew not saved: offline" );
      expect( isOn( t ), isTrue );
    } );

    testWidgets( "warning line: mute flag true and off", ( t ) async {
      await pumpPane( t, skeletonCrew: crew( "put_off_while_settings_mute_is_set" ) );
      expect( t.widget<Text>( warnF ).data,
        "Warning: the stop poke is still muted by ~/.claude/settings.json "
        "while skeleton crew is off." );
    } );

    testWidgets( "no warning when the flag is false (off)", ( t ) async {
      await pumpPane( t, skeletonCrew: crew( "get_never_flipped" ) );
      expect( warnF, findsNothing );
    } );

    testWidgets( "no warning when the flag is null (settings file unreadable)", ( t ) async {
      await pumpPane( t, skeletonCrew: crew( "get_settings_file_unreadable" ) );
      expect( switchF, findsOneWidget );
      expect( warnF, findsNothing );
    } );

    testWidgets( "no warning when on, even with the flag true", ( t ) async {
      const on = SkeletonCrew( on: true, since: null, setBy: null, settingsMuteWhileOff: true );
      await pumpPane( t, skeletonCrew: on );
      expect( warnF, findsNothing );
    } );

    testWidgets( "cap present but no ceiling: the switch is hidden too", ( t ) async {
      await pumpPane( t, skeletonCrew: crew( "put_on" ), cap: 8, capMaximum: null );
      expect( switchF, findsNothing );
    } );

    testWidgets( "ceiling present but no cap: the switch is hidden too", ( t ) async {
      await pumpPane( t, skeletonCrew: crew( "put_on" ), cap: null, capMaximum: 18 );
      expect( switchF, findsNothing );
    } );

    testWidgets( "cap payload unusable (no cap): the whole cluster, switch included, is hidden",
        ( t ) async {
      await pumpPane( t, skeletonCrew: crew( "put_on" ), cap: null, capMaximum: null );
      expect( switchF, findsNothing );
    } );
  } );

  // ---- Assembled: real screen, real bloc, real repository, only the adapter stubbed -----
  group( "behaviour table — assembled over the wire", () {
    late StubAdapter adapter;
    late String      capGet;      // which captured body the GET answers next

    Future<void> open( WidgetTester tester, {
      required String Function() getName,
      required ResponseBody Function( RequestOptions ) onSkeletonPut,
      ResponseBody Function( RequestOptions )? onCapPut,
    } ) async {
      adapter = StubAdapter( {
        "GET ${ FleetRepository.fleetStateEndpoint }"   : ( _ ) => jsonBody( liveJson ),
        "GET ${ FleetRepository.fleetSizeCapEndpoint }" : ( _ ) =>
            jsonBody( wire[ getName() ]![ "body" ] ),
        "PUT ${ FleetRepository.skeletonCrewEndpoint }" : onSkeletonPut,
        if ( onCapPut != null )
          "PUT ${ FleetRepository.fleetSizeCapEndpoint }" : onCapPut,
      } );
      tester.view.physicalSize     = const Size( 360, 800 );
      tester.view.devicePixelRatio = 1.0;
      addTearDown( tester.view.resetPhysicalSize );
      addTearDown( tester.view.resetDevicePixelRatio );
      addTearDown( () async {
        final screen = find.byType( FleetStatusScreen );
        if ( screen.evaluate().isNotEmpty ) {
          Navigator.of( tester.element( screen ) ).pop();
          await tester.pump( const Duration( milliseconds: 50 ) );
        }
      } );
      final repo = FleetRepository( makeDio( adapter ) );
      await tester.pumpWidget( MaterialApp( home: Builder( builder: ( c ) => Scaffold(
        body: ElevatedButton( child: const Text( "open" ), onPressed: () =>
          Navigator.of( c ).push( MaterialPageRoute( builder: ( _ ) => FleetStatusScreen(
            blocFactory: ( _ ) => FleetStatusBloc( repo ) ) ) ) ),
      ) ) ) );
      await tester.tap( find.text( "open" ) );
      await tester.pump();
      await tester.pump( const Duration( milliseconds: 400 ) );
      await tester.pump();
      await tester.pump( const Duration( milliseconds: 50 ) );
    }

    testWidgets( "flip ON: one PUT {on: true}; the switch is painted from the 200 answer",
        ( t ) async {
      capGet = "get_never_flipped";
      await open( t, getName: () => capGet,
        onSkeletonPut: ( _ ) {
          capGet = "put_on";
          return jsonBody( wire[ "put_on" ]![ "body" ] );
        } );
      expect( label( t ), "Skeleton crew: OFF" );

      await t.tap( switchF );
      await t.pump();
      await t.pump( const Duration( milliseconds: 50 ) );

      final puts = adapter.captured.where(
        ( r ) => r.method == "PUT" && r.path == FleetRepository.skeletonCrewEndpoint ).toList();
      expect( puts.length, 1 );
      expect( puts.single.data, { "on": true } );
      expect( label( t ), "Skeleton crew: ON" );
      expect( isOn( t ), isTrue );
    } );

    testWidgets( "the answer wins over the request: asked ON, server holds OFF with the mute",
        ( t ) async {
      capGet = "get_never_flipped";
      await open( t, getName: () => capGet,
        onSkeletonPut: ( _ ) {
          capGet = "put_off_while_settings_mute_is_set";
          return jsonBody( wire[ "put_off_while_settings_mute_is_set" ]![ "body" ] );
        } );
      await t.tap( switchF );
      await t.pump();
      await t.pump( const Duration( milliseconds: 50 ) );

      expect( label( t ), "Skeleton crew: OFF", reason: "painted from the answer, not the tap" );
      expect( warnF, findsOneWidget );
    } );

    testWidgets( "403 with an API key: sentence shown, GET re-read, switch snaps back",
        ( t ) async {
      await open( t, getName: () => "get_never_flipped",
        onSkeletonPut: ( _ ) => jsonBody(
          wire[ "put_refused_for_an_api_key" ]![ "body" ],
          status: wire[ "put_refused_for_an_api_key" ]![ "status" ] as int ) );
      final readsBefore = adapter.captured.where(
        ( r ) => r.method == "GET" && r.path == FleetRepository.fleetSizeCapEndpoint ).length;

      await t.tap( switchF );
      await t.pump();
      await t.pump( const Duration( milliseconds: 50 ) );

      expect( t.widget<Text>( errorF ).data, _refused );
      expect( isOn( t ), isFalse );
      expect( label( t ), "Skeleton crew: OFF" );
      final readsAfter = adapter.captured.where(
        ( r ) => r.method == "GET" && r.path == FleetRepository.fleetSizeCapEndpoint ).length;
      expect( readsAfter, greaterThan( readsBefore ), reason: "re-read after a refusal" );
    } );

    testWidgets( "an older server (no skeleton_crew) shows no switch", ( t ) async {
      await open( t, getName: () => "get_never_flipped",
                  onSkeletonPut: ( _ ) => jsonBody( {}, status: 500 ) );
      // Replace the GET answer with a body lacking the key, then refresh.
      wire[ "old_server" ] = {
        "status": 200,
        "body"  : { "cap": 8, "ceiling": 18,
                    "live": { "total": 0, "managers": 0, "workers": 0 } },
      };
      adapter.handlers[ "GET ${ FleetRepository.fleetSizeCapEndpoint }" ] =
          ( _ ) => jsonBody( wire[ "old_server" ]![ "body" ] );
      t.element( find.byType( FleetStatusPane ) )
          .read<FleetStatusBloc>()
          .add( const FleetStatusRefreshRequested() );
      await t.pump();
      await t.pump( const Duration( milliseconds: 50 ) );
      expect( switchF, findsNothing );
      expect( dialF, findsOneWidget );
    } );

    testWidgets( "cap dial: a 403 on the cap PUT snaps back and reports the server's sentence",
        ( t ) async {
      await open( t, getName: () => "get_never_flipped",
        onSkeletonPut: ( _ ) => jsonBody( {}, status: 500 ),
        onCapPut: ( _ ) => jsonBody( { "detail": _capRefused }, status: 403 ) );

      await t.drag( find.byType( Slider ), const Offset( 120, 0 ) );
      await t.pump();
      await t.tap( find.byKey( const Key( TestKeys.fleetStatusCapApply ) ) );
      await t.pump();
      await t.pump( const Duration( milliseconds: 50 ) );

      expect( t.widget<Text>( find.byKey( const Key( TestKeys.fleetStatusCapValue ) ) ).data, "8",
              reason: "back to the server's cap from the real `cap` key" );
      expect( find.text( _capRefused ), findsOneWidget,
              reason: "the sentence alone, not 'FleetApiException(403): …'" );
    } );
  } );
}
