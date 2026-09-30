import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_bloc.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_event.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_state.dart';
import 'package:lupin_mobile/features/focus_mode/presentation/focus_chat_pane.dart';
import 'package:lupin_mobile/features/notifications/data/notification_models.dart';
import 'package:lupin_mobile/features/notifications/presentation/message_stamp.dart';
import 'package:lupin_mobile/services/notification_audio/notification_preferences.dart';
import 'package:lupin_mobile/services/notification_filter/notification_stop_list.dart';

class _MockFocusBloc extends MockBloc<FocusChatEvent, FocusChatState> implements FocusChatBloc {}

NotificationItem _item( String id, String text, { String? group, bool ask = false } ) => NotificationItem(
  id: id, message: text, type: 'progress', priority: 'low', senderId: 'S',
  timestamp: DateTime( 2026, 8, 21, 12 ), played: false, playCount: 0,
  responseRequested: ask, responseType: ask ? 'yes_no' : null,
  suppressDing: false, displayQualifierWidget: false, progressGroupId: group,
);

NotificationItem _reply( String id, String text ) => NotificationItem(
  id: id, message: text, type: 'user_initiated_message', priority: 'low', senderId: 'S',
  timestamp: DateTime( 2026, 8, 21, 12 ), played: true, playCount: 0,
  responseRequested: false, suppressDing: true, displayQualifierWidget: false,
);

void main() {
  group( 'FocusChatPane — progress-group collapse (plan §4)', () {
    late _MockFocusBloc bloc;
    late NotificationStopList sl;

    final window = [
      FocusMessage( item: _item( '1', 'Step a', group: 'pg-1' ) ),
      FocusMessage( item: _item( '2', 'Step b', group: 'pg-1' ) ),
      FocusMessage( item: _item( '3', 'Step c', group: 'pg-1' ) ),
      FocusMessage( item: _item( '4', 'A real message' ) ),
      FocusMessage( item: _item( '5', 'Proceed?', group: 'pg-1', ask: true ) ),
    ];

    setUp( () async {
      SharedPreferences.setMockInitialValues( {} );
      sl   = NotificationStopList( await SharedPreferences.getInstance() );
      bloc = _MockFocusBloc();
      final st = const FocusChatState.initial().copyWith(
        senderOrder: const [ 'S' ], focusedSender: 'S', hydration: FocusHydration.ready,
        windows: { 'S': window } );
      whenListen( bloc, Stream<FocusChatState>.fromIterable( [ st ] ), initialState: st );
    } );

    Widget host() => MaterialApp( home: Scaffold( body: BlocProvider<FocusChatBloc>.value(
      value: bloc, child: FocusChatPane( userEmail: 'rick@test.com', stopList: sl ) ) ) );

    testWidgets( 'three same-group bubbles render as ONE row with ×3 showing the latest; tap expands to all; the ask is never buried', ( tester ) async {
      await tester.pumpWidget( host() );
      await tester.pump();
      expect( find.text( 'Step c' ), findsOneWidget );
      expect( find.text( 'Step a' ), findsNothing );
      expect( find.text( '×3' ), findsOneWidget );
      expect( find.text( 'A real message' ), findsOneWidget );
      expect( find.text( 'Proceed?' ), findsOneWidget, reason: 'responseRequested ⇒ own row even with a group id' );

      await tester.tap( find.text( '×3' ) );
      await tester.pump();
      expect( find.text( 'Step a' ), findsOneWidget );
      expect( find.text( 'Step b' ), findsOneWidget );
      expect( find.text( 'Step c' ), findsOneWidget );

      await tester.tap( find.text( '×3' ) );
      await tester.pump();
      expect( find.text( 'Step a' ), findsNothing );
    } );

    testWidgets( 'collapse OFF ⇒ every bubble renders; flipping the pref live re-renders', ( tester ) async {
      await sl.setCollapseGroups( false );
      await tester.pumpWidget( host() );
      await tester.pump();
      expect( find.text( 'Step a' ), findsOneWidget );
      expect( find.text( '×3' ), findsNothing );

      await sl.setCollapseGroups( true );
      await tester.pump();
      expect( find.text( '×3' ), findsOneWidget );
      expect( find.text( 'Step a' ), findsNothing );
    } );

    testWidgets( 'render lens: a bubble ALREADY in the window hides the moment its pattern is checked, and reappears when unchecked (hide-not-delete)', ( tester ) async {
      // Start with the pattern OFF so the bubble is visible, then flip it.
      final i = sl.patterns.indexWhere( ( p ) => p.pattern == 'Done: Bash' );
      await sl.setEnabled( i, false );
      final st = const FocusChatState.initial().copyWith(
        senderOrder: const [ 'S' ], focusedSender: 'S', hydration: FocusHydration.ready,
        windows: { 'S': [
          FocusMessage( item: _item( '1', 'Done: Bash: flutter test' ) ),
          FocusMessage( item: _item( '2', 'Suite green' ) ),
          FocusMessage( item: _reply( '3', 'Done: Bash — yes I ran it' ) ),
        ] },
      );
      whenListen( bloc, Stream<FocusChatState>.fromIterable( [ st ] ), initialState: st );
      await tester.pumpWidget( host() );
      await tester.pump();
      expect( find.text( 'Done: Bash: flutter test' ), findsOneWidget );
      expect( find.byKey( const Key( TestKeys.focusHiddenCaption ) ), findsNothing );

      await sl.setEnabled( i, true );          // user checks "Done: Bash" in settings
      await tester.pump();
      expect( find.text( 'Done: Bash: flutter test' ), findsNothing );
      expect( find.text( 'Suite green' ), findsOneWidget );
      expect( find.text( 'Done: Bash — yes I ran it' ), findsOneWidget, reason: 'user replies are never hidden' );
      expect( find.text( '1 hidden by your stop-list' ), findsOneWidget );

      await sl.setEnabled( i, false );         // unchecks ⇒ reveal, nothing was deleted
      await tester.pump();
      expect( find.text( 'Done: Bash: flutter test' ), findsOneWidget );
      expect( find.byKey( const Key( TestKeys.focusHiddenCaption ) ), findsNothing );
    } );

    testWidgets( 'render lens: when every stored bubble is hidden the pane says so (not "no messages yet")', ( tester ) async {
      final st = const FocusChatState.initial().copyWith(
        senderOrder: const [ 'S' ], focusedSender: 'S', hydration: FocusHydration.ready,
        windows: { 'S': [ FocusMessage( item: _item( '1', 'Done: mcp__x' ) ) ] },
      );
      whenListen( bloc, Stream<FocusChatState>.fromIterable( [ st ] ), initialState: st );
      await tester.pumpWidget( host() );
      await tester.pump();
      expect( find.text( 'Everything here is hidden by your stop-list.' ), findsOneWidget );
    } );

    testWidgets( 'NEWEST AT THE TOP: bubbles render newest-first; every bubble carries a lower-left timestamp', ( tester ) async {
      for ( var i = sl.patterns.length - 1; i >= 0; i-- ) { await sl.removeAt( i ); }
      NotificationItem at( String id, String text, int minute ) => NotificationItem(
        id: id, message: text, type: 'progress', priority: 'low', senderId: 'S',
        timestamp: DateTime( 2026, 8, 21, 12, minute, 7 ), played: false, playCount: 0,
        responseRequested: false, suppressDing: false, displayQualifierWidget: false,
      );
      final st = const FocusChatState.initial().copyWith(
        senderOrder: const [ 'S' ], focusedSender: 'S', hydration: FocusHydration.ready,
        windows: { 'S': [
          FocusMessage( item: at( 'old', 'oldest', 1 ) ),
          FocusMessage( item: at( 'mid', 'middle', 2 ) ),
          FocusMessage( item: at( 'new', 'newest', 3 ) ),
        ] },
      );
      whenListen( bloc, Stream<FocusChatState>.fromIterable( [ st ] ), initialState: st );
      await tester.pumpWidget( host() );
      await tester.pump();
      final dyNew = tester.getTopLeft( find.text( 'newest' ) ).dy;
      final dyMid = tester.getTopLeft( find.text( 'middle' ) ).dy;
      final dyOld = tester.getTopLeft( find.text( 'oldest' ) ).dy;
      expect( dyNew < dyMid && dyMid < dyOld, isTrue, reason: 'newest on top, oldest at the bottom' );
      for ( final id in [ 'old', 'mid', 'new' ] ) {
        expect( find.byKey( Key( '${TestKeys.messageStampPrefix}$id' ) ), findsOneWidget );
      }
      expect( find.text( MessageStamp.format( DateTime( 2026, 8, 21, 12, 3, 7 ) ) ), findsOneWidget );
      // stamp sits BELOW its message text (lower-left)
      final stampNew = tester.getTopLeft( find.byKey( const Key( '${TestKeys.messageStampPrefix}new' ) ) );
      expect( stampNew.dy > dyNew, isTrue );
    } );

    testWidgets( 'TTS fraction slider is pinned at the top of the pane (even with NO focused sender), 10% steps, persists', ( tester ) async {
      SharedPreferences.setMockInitialValues( {} );
      final prefs = NotificationPreferences( await SharedPreferences.getInstance() );
      final st = const FocusChatState.initial().copyWith( hydration: FocusHydration.ready );   // nothing focused
      whenListen( bloc, Stream<FocusChatState>.fromIterable( [ st ] ), initialState: st );
      await tester.pumpWidget( MaterialApp( home: Scaffold( body: BlocProvider<FocusChatBloc>.value(
        value: bloc, child: FocusChatPane( userEmail: 'rick@test.com', stopList: sl, prefs: prefs ) ) ) ) );
      await tester.pump();

      final bar = find.byKey( const Key( TestKeys.focusTtsFractionBar ) );
      expect( bar, findsOneWidget );
      expect( find.text( 'Tap a session badge to focus its conversation.' ), findsOneWidget );
      expect( tester.getTopLeft( bar ).dy < tester.getTopLeft( find.text( 'Tap a session badge to focus its conversation.' ) ).dy, isTrue );
      expect( find.text( '20%' ), findsOneWidget );   // default

      final slider = tester.widget<Slider>( find.byKey( const Key( TestKeys.focusTtsFractionSlider ) ) );
      expect( slider.divisions, 10 );
      slider.onChanged!( 0.74 );
      await tester.pump();
      expect( find.text( '70%' ), findsOneWidget );
      expect( prefs.ttsFraction, 0.7 );
      final again = NotificationPreferences( await SharedPreferences.getInstance() );
      expect( again.ttsFraction, 0.7 );
    } );
  } );
}
