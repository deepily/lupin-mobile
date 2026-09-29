/// The notification management view — Rick 2026-09-28, row 7cac3a17.
///
/// Three things this screen has to get right: it shows the master / surface /
/// priority hierarchy he asked for, every control SURVIVES the screen (the
/// background isolate reads these from storage long after the widget is gone),
/// and the cascade greys out what a higher switch has already decided.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/settings/presentation/notification_management_screen.dart';
import 'package:lupin_mobile/services/notification_audio/notification_preferences.dart';

void main() {
  late NotificationPreferences prefs;

  Future<void> seed( Map<String, Object> values ) async {
    SharedPreferences.setMockInitialValues( values );
    prefs = NotificationPreferences( await SharedPreferences.getInstance() );
  }

  setUp( () async => seed( {} ) );

  Widget underTest() => MaterialApp(
    home: NotificationManagementScreen( prefs: prefs ),
  );

  Finder masterFinder     = find.byKey( const Key( TestKeys.notifMgmtMaster ) );
  Finder backgroundFinder = find.byKey( const Key( TestKeys.notifMgmtBackground ) );
  Finder foregroundFinder = find.byKey( const Key( TestKeys.notifMgmtForeground ) );
  Finder priorityFinder( String surface, String priority ) =>
      find.byKey( Key( TestKeys.notifMgmtPriority( surface, priority ) ) );

  /// Scroll a lazy ListView entry into existence before looking at it — the
  /// 800x600 test viewport does not hold this whole screen.
  Future<void> bring( WidgetTester tester, Finder f ) async {
    await tester.scrollUntilVisible( f, 80 );
    await tester.pump();
  }

  group( 'the hierarchy Rick asked for', () {
    testWidgets( 'master, two surfaces, and four priorities under each', ( tester ) async {
      await tester.pumpWidget( underTest() );
      await tester.pump();

      expect( masterFinder, findsOneWidget );
      expect( backgroundFinder, findsOneWidget );

      for ( final surface in [ 'background', 'foreground' ] ) {
        for ( final priority in NotificationPreferences.priorities ) {
          await bring( tester, priorityFinder( surface, priority ) );
          expect( priorityFinder( surface, priority ), findsOneWidget,
                  reason: '$surface/$priority needs its own checkbox' );
        }
      }
      await bring( tester, foregroundFinder );
      expect( foregroundFinder, findsOneWidget );
    } );

    testWidgets( 'the four priorities are the server\'s four, in the server\'s order',
        ( tester ) async {
      expect( NotificationPreferences.priorities,
              [ 'low', 'medium', 'high', 'urgent' ] );

      await tester.pumpWidget( underTest() );
      await tester.pump();
      for ( final label in [ 'Low', 'Medium', 'High', 'Urgent' ] ) {
        expect( find.text( label ), findsWidgets );
      }
    } );
  } );

  group( 'persistence — a setting the background isolate cannot read is not a setting', () {
    testWidgets( 'the master switch survives the screen', ( tester ) async {
      await tester.pumpWidget( underTest() );
      await tester.pump();
      expect( tester.widget<SwitchListTile>( masterFinder ).value, isTrue );

      await tester.tap( masterFinder );
      await tester.pump();

      expect( tester.widget<SwitchListTile>( masterFinder ).value, isFalse );
      final reread = NotificationPreferences( await SharedPreferences.getInstance() );
      expect( reread.enabled, isFalse );
    } );

    testWidgets( 'each surface switch survives the screen', ( tester ) async {
      await tester.pumpWidget( underTest() );
      await tester.pump();

      await tester.tap( backgroundFinder );
      await tester.pump();
      await bring( tester, foregroundFinder );
      await tester.tap( foregroundFinder );
      await tester.pump();

      final reread = NotificationPreferences( await SharedPreferences.getInstance() );
      expect( reread.backgroundEnabled, isFalse );
      expect( reread.foregroundEnabled, isFalse );
    } );

    testWidgets( 'a priority checkbox survives the screen, on the surface it belongs to',
        ( tester ) async {
      await tester.pumpWidget( underTest() );
      await tester.pump();

      final urgent = priorityFinder( 'background', 'urgent' );
      await bring( tester, urgent );
      expect( tester.widget<CheckboxListTile>( urgent ).value, isTrue );

      await tester.tap( urgent );
      await tester.pump();

      final reread = NotificationPreferences( await SharedPreferences.getInstance() );
      expect( reread.priorityEnabled( 'background', 'urgent' ), isFalse );
      expect( reread.priorityEnabled( 'foreground', 'urgent' ), isTrue,
              reason: 'the other surface must not move with it' );
    } );

    testWidgets( 'the defaults on screen match the defaults in storage, low included',
        ( tester ) async {
      await tester.pumpWidget( underTest() );
      await tester.pump();

      await bring( tester, priorityFinder( 'background', 'low' ) );
      expect( tester.widget<CheckboxListTile>( priorityFinder( 'background', 'low' ) ).value,
              isTrue );

      await bring( tester, priorityFinder( 'foreground', 'low' ) );
      expect( tester.widget<CheckboxListTile>( priorityFinder( 'foreground', 'low' ) ).value,
              isFalse,
              reason: 'foreground low is already silent today; the screen must '
                      'show that rather than imply it is on' );
    } );

    testWidgets( 'the screen opens showing what was SAVED, not the defaults', ( tester ) async {
      await seed( {
        NotificationPreferences.keyEnabled: false,
        NotificationPreferences.priorityKey( 'background', 'high' ): false,
      } );
      await tester.pumpWidget( underTest() );
      await tester.pump();

      expect( tester.widget<SwitchListTile>( masterFinder ).value, isFalse );
      await bring( tester, priorityFinder( 'background', 'high' ) );
      expect( tester.widget<CheckboxListTile>( priorityFinder( 'background', 'high' ) ).value,
              isFalse );
    } );
  } );

  group( 'the cascade', () {
    testWidgets( 'master OFF greys both surface switches', ( tester ) async {
      await seed( { NotificationPreferences.keyEnabled: false } );
      await tester.pumpWidget( underTest() );
      await tester.pump();

      expect( tester.widget<SwitchListTile>( backgroundFinder ).onChanged, isNull );
      await bring( tester, foregroundFinder );
      expect( tester.widget<SwitchListTile>( foregroundFinder ).onChanged, isNull );
    } );

    testWidgets( 'master OFF greys every priority on both surfaces', ( tester ) async {
      await seed( { NotificationPreferences.keyEnabled: false } );
      await tester.pumpWidget( underTest() );
      await tester.pump();

      for ( final surface in [ 'background', 'foreground' ] ) {
        for ( final priority in NotificationPreferences.priorities ) {
          final f = priorityFinder( surface, priority );
          await bring( tester, f );
          expect( tester.widget<CheckboxListTile>( f ).onChanged, isNull,
                  reason: '$surface/$priority must be inert while master is off' );
        }
      }
    } );

    testWidgets( 'a surface OFF greys only ITS priorities', ( tester ) async {
      await seed( { NotificationPreferences.keyBackgroundEnabled: false } );
      await tester.pumpWidget( underTest() );
      await tester.pump();

      for ( final priority in NotificationPreferences.priorities ) {
        final f = priorityFinder( 'background', priority );
        await bring( tester, f );
        expect( tester.widget<CheckboxListTile>( f ).onChanged, isNull );
      }
      for ( final priority in NotificationPreferences.priorities ) {
        final f = priorityFinder( 'foreground', priority );
        await bring( tester, f );
        expect( tester.widget<CheckboxListTile>( f ).onChanged, isNotNull,
                reason: 'the foreground is a separate switch' );
      }
    } );

    testWidgets( 'greyed-out controls are still VISIBLE and still show their value',
        ( tester ) async {
      // Hiding them would make the master switch look destructive — the user
      // needs to see that their per-priority choices are still there.
      await seed( {
        NotificationPreferences.keyEnabled: false,
        NotificationPreferences.priorityKey( 'background', 'urgent' ): false,
      } );
      await tester.pumpWidget( underTest() );
      await tester.pump();

      final f = priorityFinder( 'background', 'urgent' );
      await bring( tester, f );
      expect( f, findsOneWidget );
      expect( tester.widget<CheckboxListTile>( f ).value, isFalse );
    } );

    testWidgets( 'turning master back ON re-enables the surfaces in one tap', ( tester ) async {
      await seed( { NotificationPreferences.keyEnabled: false } );
      await tester.pumpWidget( underTest() );
      await tester.pump();
      expect( tester.widget<SwitchListTile>( backgroundFinder ).onChanged, isNull );

      await tester.tap( masterFinder );
      await tester.pump();

      expect( tester.widget<SwitchListTile>( backgroundFinder ).onChanged, isNotNull );
    } );
  } );

  group( 'the links out', () {
    testWidgets( 'sound and speech is reachable', ( tester ) async {
      await tester.pumpWidget( underTest() );
      await tester.pump();

      final link = find.byKey( const Key( TestKeys.notifMgmtOpenSound ) );
      await bring( tester, link );
      expect( link, findsOneWidget );
    } );

    testWidgets( 'the stop-list link is hidden when no stop-list is wired, rather than crashing',
        ( tester ) async {
      await tester.pumpWidget( underTest() );   // built with stopList: null
      await tester.pump();

      await tester.drag( find.byType( ListView ), const Offset( 0, -2000 ) );
      await tester.pump();
      expect( find.byKey( const Key( TestKeys.notifMgmtOpenStopList ) ), findsNothing );
    } );
  } );
}
