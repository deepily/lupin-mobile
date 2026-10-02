/// The "Stop poke" switch on the Notifications screen (row ee68d5e7).
/// A fake repository stands in for the server: nothing here touches :7999.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/settings/data/heartbeat_poke_repository.dart';
import 'package:lupin_mobile/features/settings/presentation/heartbeat_poke_section.dart';
import 'package:lupin_mobile/features/settings/presentation/notification_management_screen.dart';
import 'package:lupin_mobile/services/notification_audio/notification_preferences.dart';

class FakeHeartbeatPoke implements HeartbeatPokeRepository {
  HeartbeatPokeState      state = const HeartbeatPokeState( muted: false );
  HeartbeatPokeException? failRead;
  HeartbeatPokeException? failWrite;
  final List<String>      calls = [];

  @override
  Future<HeartbeatPokeState> getState() async {
    calls.add( "get" );
    if ( failRead != null ) throw failRead!;
    return state;
  }

  @override
  Future<HeartbeatPokeState> setMuted( bool muted ) async {
    calls.add( "set:$muted" );
    if ( failWrite != null ) throw failWrite!;
    return state = HeartbeatPokeState( muted: muted, setBy: "rick" );
  }
}

class _ThrowingRepo implements HeartbeatPokeRepository {
  @override Future<HeartbeatPokeState> getState() async => throw StateError( "offline" );
  @override Future<HeartbeatPokeState> setMuted( bool muted ) async => throw StateError( "offline" );
}

void main() {
  late FakeHeartbeatPoke fake;

  setUp( () => fake = FakeHeartbeatPoke() );

  Finder sw()        => find.byKey( const Key( TestKeys.heartbeatPokeSwitch ) );
  Finder adminOnly() => find.byKey( const Key( TestKeys.heartbeatPokeAdminOnly ) );
  Finder error()     => find.byKey( const Key( TestKeys.heartbeatPokeError ) );

  Future<void> open( WidgetTester t, [ HeartbeatPokeRepository? repo ] ) async {
    await t.pumpWidget( MaterialApp(
      home: Scaffold( body: SingleChildScrollView(
          child: HeartbeatPokeSection( repository: repo ?? fake ) ) ),
    ) );
    await t.pumpAndSettle();
  }

  SwitchListTile tile( WidgetTester t ) => t.widget<SwitchListTile>( sw() );

  String status( WidgetTester t ) =>
      t.widget<Text>( find.byKey( const Key( TestKeys.heartbeatPokeStatus ) ) ).data!;

  group( 'states', () {
    testWidgets( 'not muted: switch on, reads On', ( t ) async {
      await open( t );
      expect( tile( t ).value, isTrue );
      expect( status( t ), "On" );
      expect( tile( t ).onChanged, isNotNull );
    } );

    testWidgets( 'muted: switch off, says who and when', ( t ) async {
      fake.state = HeartbeatPokeState(
          muted: true, setBy: "rick", setAt: DateTime( 2026, 10, 2, 11, 5 ) );
      await open( t );
      expect( tile( t ).value, isFalse );
      expect( status( t ), "Muted by rick at 11:05 AM" );
    } );

    testWidgets( 'muted with no author or time reads plain Muted', ( t ) async {
      fake.state = const HeartbeatPokeState( muted: true );
      await open( t );
      expect( status( t ), "Muted" );
    } );

    testWidgets( 'there is no timer or duration control', ( t ) async {
      await open( t );
      expect( find.byType( ActionChip ), findsNothing );
      expect( find.byType( FilledButton ), findsNothing );
    } );
  } );

  group( 'flipping', () {
    testWidgets( 'turning the switch off sends muted: true and shows Muted', ( t ) async {
      await open( t );
      await t.tap( sw() );
      await t.pumpAndSettle();
      expect( fake.calls, [ "get", "set:true" ] );
      expect( tile( t ).value, isFalse );
      expect( status( t ), "Muted by rick" );
    } );

    testWidgets( 'turning it back on sends muted: false and shows On', ( t ) async {
      fake.state = const HeartbeatPokeState( muted: true );
      await open( t );
      await t.tap( sw() );
      await t.pumpAndSettle();
      expect( fake.calls, [ "get", "set:false" ] );
      expect( tile( t ).value, isTrue );
      expect( status( t ), "On" );
    } );
  } );

  group( 'refusals and failures', () {
    testWidgets( 'a 403 on the write shows admin-only, disables the switch, keeps the state', ( t ) async {
      await open( t );
      fake.failWrite = const HeartbeatPokeException( "no", statusCode: 403 );
      await t.tap( sw() );
      await t.pumpAndSettle();
      expect( adminOnly(), findsOneWidget );
      expect( error(), findsNothing );
      expect( tile( t ).onChanged, isNull );
      expect( tile( t ).value, isTrue, reason: "the refused write must not look like it landed" );
      expect( status( t ), "On" );
    } );

    testWidgets( 'after a 403, a later good read keeps the switch disabled', ( t ) async {
      await open( t );
      fake.failWrite = const HeartbeatPokeException( "no", statusCode: 403 );
      await t.tap( sw() );
      await t.pumpAndSettle();
      t.binding.handleAppLifecycleStateChanged( AppLifecycleState.resumed );
      await t.pumpAndSettle();
      expect( fake.calls, [ "get", "set:true", "get" ] );
      expect( adminOnly(), findsOneWidget );
      expect( tile( t ).onChanged, isNull,
          reason: "a read succeeds for any user, so it must not re-enable a refused switch" );
    } );

    testWidgets( 'after a 403, a failed read does not re-enable the switch either', ( t ) async {
      await open( t );
      fake.failWrite = const HeartbeatPokeException( "no", statusCode: 403 );
      await t.tap( sw() );
      await t.pumpAndSettle();
      fake.failRead = const HeartbeatPokeException( "boom", statusCode: 500 );
      t.binding.handleAppLifecycleStateChanged( AppLifecycleState.resumed );
      await t.pumpAndSettle();
      expect( adminOnly(), findsOneWidget );
      expect( tile( t ).onChanged, isNull );
    } );

    testWidgets( 'a 500 on the write shows the message and leaves the switch usable', ( t ) async {
      await open( t );
      fake.failWrite = const HeartbeatPokeException( "server exploded", statusCode: 500 );
      await t.tap( sw() );
      await t.pumpAndSettle();
      expect( find.text( "server exploded" ), findsOneWidget );
      expect( adminOnly(), findsNothing );
      expect( tile( t ).onChanged, isNotNull );
      expect( tile( t ).value, isTrue );
    } );

    testWidgets( 'a failed first read: Unknown, switch disabled and off', ( t ) async {
      fake.failRead = const HeartbeatPokeException( "unreachable" );
      await open( t );
      expect( status( t ), "Unknown" );
      expect( tile( t ).onChanged, isNull );
      expect( find.text( "unreachable" ), findsOneWidget );
    } );

    testWidgets( 'a repository that throws something else does not crash the screen', ( t ) async {
      await open( t, _ThrowingRepo() );
      expect( error(), findsOneWidget );
      expect( t.takeException(), isNull );
    } );

    testWidgets( 'an error clears on the next good read', ( t ) async {
      fake.failRead = const HeartbeatPokeException( "boom", statusCode: 500 );
      await open( t );
      expect( error(), findsOneWidget );
      fake.failRead = null;
      t.binding.handleAppLifecycleStateChanged( AppLifecycleState.resumed );
      await t.pumpAndSettle();
      expect( error(), findsNothing );
      expect( status( t ), "On" );
    } );
  } );

  group( 'freshness', () {
    testWidgets( 'coming back to the foreground re-reads, so another client\'s flip shows', ( t ) async {
      await open( t );
      fake.state = const HeartbeatPokeState( muted: true, setBy: "web" );
      t.binding.handleAppLifecycleStateChanged( AppLifecycleState.resumed );
      await t.pumpAndSettle();
      expect( fake.calls, [ "get", "get" ] );
      expect( status( t ), "Muted by web" );
    } );
  } );

  group( 'on the Notifications screen', () {
    Future<NotificationPreferences> prefs() async {
      SharedPreferences.setMockInitialValues( {} );
      return NotificationPreferences( await SharedPreferences.getInstance() );
    }

    testWidgets( 'the switch sits above the master switch', ( t ) async {
      final p = await prefs();
      await t.pumpWidget( MaterialApp(
        home: NotificationManagementScreen( prefs: p, heartbeatPoke: fake ),
      ) );
      await t.pumpAndSettle();
      final top    = t.getTopLeft( sw() ).dy;
      final master = t.getTopLeft( find.byKey( const Key( TestKeys.notifMgmtMaster ) ) ).dy;
      expect( top, lessThan( master ) );
    } );

    testWidgets( 'no repository, no switch', ( t ) async {
      final p = await prefs();
      await t.pumpWidget( MaterialApp( home: NotificationManagementScreen( prefs: p ) ) );
      await t.pumpAndSettle();
      expect( sw(), findsNothing );
    } );
  } );
}
