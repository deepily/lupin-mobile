/// "Pause push from server" on the Notifications screen (row 67ee93b0).
/// A fake repository stands in for the server: nothing here touches :7999.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/settings/data/push_pause_repository.dart';
import 'package:lupin_mobile/features/settings/presentation/notification_management_screen.dart';
import 'package:lupin_mobile/features/settings/presentation/push_pause_section.dart';
import 'package:lupin_mobile/services/notification_audio/notification_preferences.dart';

class FakePushPause implements PushPauseRepository {
  PushPauseState      state = const PushPauseState( paused: false );
  PushPauseException? failWith;
  final List<String>  calls = [];

  @override
  Future<PushPauseState> getState() async {
    calls.add( "get" );
    if ( failWith != null ) throw failWith!;
    return state;
  }

  @override
  Future<void> pause( { int? minutes } ) async {
    calls.add( "pause:$minutes" );
    if ( failWith != null ) throw failWith!;
    state = PushPauseState(
      paused    : true,
      resumesAt : minutes == null ? null : DateTime( 2026, 9, 29, 19, 45 ),
    );
  }

  @override
  Future<void> resume() async {
    calls.add( "resume" );
    if ( failWith != null ) throw failWith!;
    state = const PushPauseState( paused: false );
  }
}

void main() {
  late FakePushPause fake;

  setUp( () => fake = FakePushPause() );

  Widget underTest() => MaterialApp(
    home: Scaffold( body: SingleChildScrollView( child: PushPauseSection( repository: fake ) ) ),
  );

  Finder chip( int? minutes ) => find.byKey( Key( TestKeys.pushPauseDuration( minutes ) ) );
  Finder resume()             => find.byKey( const Key( TestKeys.pushPauseResume ) );

  Future<void> open( WidgetTester t ) async {
    await t.pumpWidget( underTest() );
    await t.pumpAndSettle();
  }

  bool chipEnabled( WidgetTester t, int? m ) =>
      t.widget<ActionChip>( chip( m ) ).onPressed != null;

  group( 'states', () {
    testWidgets( 'not paused reads On, Resume is disabled', ( t ) async {
      await open( t );
      expect( find.text( 'On' ), findsOneWidget );
      expect( t.widget<FilledButton>( resume() ).onPressed, isNull );
    } );

    testWidgets( 'paused with a time reads Paused until <time>', ( t ) async {
      fake.state = PushPauseState( paused: true, resumesAt: DateTime( 2026, 9, 29, 19, 45 ) );
      await open( t );
      expect( find.text( 'Paused until 7:45 PM' ), findsOneWidget );
      expect( t.widget<FilledButton>( resume() ).onPressed, isNotNull );
    } );

    testWidgets( 'paused with no end reads Paused until resumed', ( t ) async {
      fake.state = const PushPauseState( paused: true );
      await open( t );
      expect( find.text( 'Paused until resumed' ), findsOneWidget );
    } );

    testWidgets( 'all six durations are offered', ( t ) async {
      await open( t );
      for ( final m in [ 30, 60, 120, 480, 1440, null ] ) {
        expect( chip( m ), findsOneWidget, reason: '$m' );
      }
      expect( find.text( 'Until I resume' ), findsOneWidget );
    } );
  } );

  group( 'actions', () {
    for ( final m in [ 30, 60, 120, 480, 1440 ] ) {
      testWidgets( 'picking $m posts minutes: $m', ( t ) async {
        await open( t );
        await t.tap( chip( m ) );
        await t.pumpAndSettle();
        expect( fake.calls, contains( "pause:$m" ) );
        expect( find.textContaining( 'Paused until' ), findsOneWidget );
      } );
    }

    testWidgets( 'Until I resume posts no minutes', ( t ) async {
      await open( t );
      await t.tap( chip( null ) );
      await t.pumpAndSettle();
      expect( fake.calls, contains( "pause:null" ) );
      expect( find.text( 'Paused until resumed' ), findsOneWidget );
    } );

    testWidgets( 'Resume posts paused:false and shows On', ( t ) async {
      fake.state = const PushPauseState( paused: true );
      await open( t );
      await t.tap( resume() );
      await t.pumpAndSettle();
      expect( fake.calls, contains( "resume" ) );
      expect( find.text( 'On' ), findsOneWidget );
    } );
  } );

  group( 'errors', () {
    testWidgets( '403 shows the admin-only note and disables every control', ( t ) async {
      fake.failWith = const PushPauseException( "no", statusCode: 403 );
      await open( t );
      expect( find.byKey( const Key( TestKeys.pushPauseAdminOnly ) ), findsOneWidget );
      for ( final m in [ 30, 60, 120, 480, 1440, null ] ) {
        expect( chipEnabled( t, m ), isFalse, reason: '$m' );
      }
      expect( t.widget<FilledButton>( resume() ).onPressed, isNull );
    } );

    testWidgets( 'a 403 on a pause attempt also locks the controls', ( t ) async {
      await open( t );
      fake.failWith = const PushPauseException( "no", statusCode: 403 );
      await t.tap( chip( 30 ) );
      await t.pumpAndSettle();
      expect( find.byKey( const Key( TestKeys.pushPauseAdminOnly ) ), findsOneWidget );
      expect( chipEnabled( t, 30 ), isFalse );
    } );

    testWidgets( 'another error shows inline, keeps controls live, does not throw', ( t ) async {
      fake.failWith = const PushPauseException( "server exploded", statusCode: 500 );
      await open( t );
      expect( find.text( 'server exploded' ), findsOneWidget );
      expect( find.byKey( const Key( TestKeys.pushPauseAdminOnly ) ), findsNothing );
      expect( chipEnabled( t, 30 ), isTrue );
      expect( t.takeException(), isNull );
    } );

    testWidgets( 'a non-API error (network) is shown inline too', ( t ) async {
      final f = _ThrowingRepo();
      await t.pumpWidget( MaterialApp( home: Scaffold( body: PushPauseSection( repository: f ) ) ) );
      await t.pumpAndSettle();
      expect( find.byKey( const Key( TestKeys.pushPauseError ) ), findsOneWidget );
      expect( t.takeException(), isNull );
    } );

    testWidgets( 'a later good read clears the error', ( t ) async {
      fake.failWith = const PushPauseException( "boom", statusCode: 500 );
      await open( t );
      fake.failWith = null;
      t.binding.handleAppLifecycleStateChanged( AppLifecycleState.inactive );
      t.binding.handleAppLifecycleStateChanged( AppLifecycleState.resumed );
      await t.pumpAndSettle();
      expect( find.text( 'boom' ), findsNothing );
    } );
  } );

  group( 're-reading', () {
    testWidgets( 'opening the screen reads the server state', ( t ) async {
      await open( t );
      expect( fake.calls, [ "get" ] );
    } );

    testWidgets( 'returning to the foreground reads it again, never a cached value', ( t ) async {
      await open( t );
      expect( find.text( 'On' ), findsOneWidget );

      // The server restarted or someone else paused: the phone must show it.
      fake.state = const PushPauseState( paused: true );
      t.binding.handleAppLifecycleStateChanged( AppLifecycleState.inactive );
      t.binding.handleAppLifecycleStateChanged( AppLifecycleState.hidden );
      t.binding.handleAppLifecycleStateChanged( AppLifecycleState.paused );
      t.binding.handleAppLifecycleStateChanged( AppLifecycleState.hidden );
      t.binding.handleAppLifecycleStateChanged( AppLifecycleState.inactive );
      t.binding.handleAppLifecycleStateChanged( AppLifecycleState.resumed );
      await t.pumpAndSettle();

      expect( fake.calls.where( ( c ) => c == "get" ).length, 2 );
      expect( find.text( 'Paused until resumed' ), findsOneWidget );
    } );
  } );

  group( 'on the Notifications screen', () {
    Future<NotificationPreferences> prefs() async {
      SharedPreferences.setMockInitialValues( {} );
      return NotificationPreferences( await SharedPreferences.getInstance() );
    }

    testWidgets( 'the section is first, above the master switch', ( t ) async {
      final p = await prefs();
      // The screen takes a repository; wrap the fake in a real-typed subclass path.
      await t.pumpWidget( MaterialApp(
        home: NotificationManagementScreen( prefs: p, pushPause: fake ),
      ) );
      await t.pumpAndSettle();
      expect( find.text( 'Pause push from server' ), findsOneWidget );
      final top    = t.getTopLeft( find.text( 'Pause push from server' ) ).dy;
      final master = t.getTopLeft( find.byKey( const Key( TestKeys.notifMgmtMaster ) ) ).dy;
      expect( top, lessThan( master ) );
    } );

    testWidgets( 'no repository, no section', ( t ) async {
      final p = await prefs();
      await t.pumpWidget( MaterialApp( home: NotificationManagementScreen( prefs: p ) ) );
      await t.pumpAndSettle();
      expect( find.text( 'Pause push from server' ), findsNothing );
    } );
  } );
}

class _ThrowingRepo implements PushPauseRepository {
  @override Future<PushPauseState> getState() async => throw StateError( "offline" );
  @override Future<void> pause( { int? minutes } ) async => throw StateError( "offline" );
  @override Future<void> resume() async => throw StateError( "offline" );
}
