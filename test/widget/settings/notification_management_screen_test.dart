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
import 'package:lupin_mobile/features/notifications/data/notification_models.dart';
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

  // ── Row f1e80e67, plan §7.5: muted senders and quiet hours ────────────────
  group( 'muted senders', () {
    const maya  = MutableSender( key: 'persona:maya',  label: '🌻 Maya' );
    const maria = MutableSender( key: 'persona:maria', label: '🗼 María' );

    Widget withRoster( List<MutableSender> roster ) => MaterialApp(
      home: NotificationManagementScreen( prefs: prefs, loadSenders: () async => roster ),
    );

    Finder addFinder = find.byKey( const Key( TestKeys.notifMgmtMuteAdd ) );
    Finder pick( String key )   => find.byKey( Key( '${TestKeys.notifMgmtMutePickPrefix}$key' ) );
    Finder row( String key )    => find.byKey( Key( '${TestKeys.notifMgmtMuteRowPrefix}$key' ) );
    Finder remove( String key ) => find.byKey( Key( '${TestKeys.notifMgmtMuteRemovePrefix}$key' ) );

    testWidgets( 'Add offers the roster, and picking one mutes it and lists it', ( tester ) async {
      await tester.pumpWidget( withRoster( [ maya, maria ] ) );
      await bring( tester, addFinder );
      await tester.tap( addFinder );
      await tester.pumpAndSettle();

      expect( pick( maya.key ), findsOneWidget );
      await tester.tap( pick( maya.key ) );
      await tester.pumpAndSettle();

      expect( prefs.isSenderMuted( maya.key ), isTrue );
      expect( prefs.mutedSenders[ maya.key ], '🌻 Maya', reason: 'the label is what a person reads' );
      await bring( tester, row( maya.key ) );
      expect( find.text( '🌻 Maya' ), findsOneWidget );
    } );

    testWidgets( 'a sender already muted is not offered again', ( tester ) async {
      await prefs.muteSender( maya.key, maya.label );
      await tester.pumpWidget( withRoster( [ maya, maria ] ) );
      await bring( tester, addFinder );
      await tester.tap( addFinder );
      await tester.pumpAndSettle();

      expect( pick( maya.key ), findsNothing );
      expect( pick( maria.key ), findsOneWidget );
    } );

    testWidgets( '✕ unmutes', ( tester ) async {
      await prefs.muteSender( maya.key, maya.label );
      await tester.pumpWidget( withRoster( const [] ) );
      await bring( tester, remove( maya.key ) );
      await tester.tap( remove( maya.key ) );
      await tester.pumpAndSettle();

      expect( prefs.isSenderMuted( maya.key ), isFalse );
      expect( row( maya.key ), findsNothing );
    } );

    testWidgets( 'no roster loader: no Add button, but muted senders can still be removed', ( tester ) async {
      await prefs.muteSender( maya.key, maya.label );
      await tester.pumpWidget( underTest() );
      await bring( tester, remove( maya.key ) );
      expect( addFinder, findsNothing );
      expect( remove( maya.key ), findsOneWidget );
    } );

    testWidgets( 'the urgent bypass is on by default and persists when unticked', ( tester ) async {
      final bypass = find.byKey( const Key( TestKeys.notifMgmtMuteUrgentBypass ) );
      await tester.pumpWidget( underTest() );
      await bring( tester, bypass );
      expect( tester.widget<CheckboxListTile>( bypass ).value, isTrue );
      await tester.tap( bypass );
      await tester.pumpAndSettle();
      expect( prefs.muteUrgentBypass, isFalse );
    } );
  } );

  group( 'MutableSender.fromRoster', () {
    test( 'two seats of one persona are ONE thing to mute; order is kept', () {
      const mayaJson = { 'name': 'Maya', 'icon': '🌻' };
      final roster = [
        SenderSummary.fromJson( { 'sender_id': 'claude.code@lupin.deepily.ai#aaaa', 'count': 1,
                                  'voice_persona': mayaJson } ),
        SenderSummary.fromJson( { 'sender_id': 'claude.code@lookml.deepily.ai#cccc', 'count': 1 } ),
        SenderSummary.fromJson( { 'sender_id': 'claude.code@lupin.deepily.ai#bbbb', 'count': 1,
                                  'voice_persona': mayaJson } ),
      ];
      final out = MutableSender.fromRoster( roster );
      expect( out.map( ( s ) => s.key ), [ 'persona:maya', 'project:lookml' ] );
      expect( out.first.label, '🌻 Maya' );
      expect( out.last.label, 'lookml' );
    } );
  } );

  group( 'quiet hours', () {
    Finder quietFinder = find.byKey( const Key( TestKeys.notifMgmtQuiet ) );
    Finder startFinder = find.byKey( const Key( TestKeys.notifMgmtQuietStart ) );

    testWidgets( 'off by default, showing 22:00 → 07:00 greyed out', ( tester ) async {
      await tester.pumpWidget( underTest() );
      await bring( tester, startFinder );
      expect( tester.widget<SwitchListTile>( quietFinder ).value, isFalse );
      expect( find.text( '22:00' ), findsOneWidget );
      expect( find.text( '07:00' ), findsOneWidget );
      expect( tester.widget<TextButton>( startFinder ).onPressed, isNull,
              reason: 'the times cannot be edited while quiet hours are off' );
    } );

    testWidgets( 'turning it on persists and enables the times', ( tester ) async {
      await tester.pumpWidget( underTest() );
      await bring( tester, quietFinder );
      await tester.tap( quietFinder );
      await tester.pumpAndSettle();
      expect( prefs.quietEnabled, isTrue );
      await bring( tester, startFinder );
      expect( tester.widget<TextButton>( startFinder ).onPressed, isNotNull );
    } );

    testWidgets( 'the master switch greys quiet hours too', ( tester ) async {
      await seed( { NotificationPreferences.keyEnabled: false } );
      await tester.pumpWidget( underTest() );
      await bring( tester, quietFinder );
      expect( tester.widget<SwitchListTile>( quietFinder ).onChanged, isNull );
    } );

    test( 'formatMinutes is 24-hour and zero-padded', () {
      expect( formatMinutes( 22 * 60 ), '22:00' );
      expect( formatMinutes( 7 * 60 + 5 ), '07:05' );
      expect( formatMinutes( 0 ), '00:00' );
    } );
  } );
}
