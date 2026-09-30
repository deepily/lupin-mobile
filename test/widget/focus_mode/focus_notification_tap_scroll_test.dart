import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_bloc.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_event.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_state.dart';
import 'package:lupin_mobile/features/focus_mode/presentation/focus_chat_pane.dart';
import 'package:lupin_mobile/features/notifications/data/notification_models.dart';
import 'package:lupin_mobile/services/notification_filter/notification_stop_list.dart';

class _MockFocusBloc extends MockBloc<FocusChatEvent, FocusChatState>
    implements FocusChatBloc {}

/// Row d9bc6f6c, the SECOND half — bringing the tapped message into view.
///
/// ⚠️ WHAT THIS HALF IS WORTH, STATED PLAINLY. The pane renders NEWEST AT THE TOP
/// over a window the bloc caps at 7, so the message a user just tapped is usually
/// item 0 and visible for free. Scrolling earns its keep in two cases only:
/// messages arrived after the notification was posted, or the target is buried in
/// a collapsed progress group. Both are covered below. The sender-selection half
/// (see the bloc test) is what fixes Rick's actual complaint.
void main() {
  const who = 'claude.code@lupin.deepily.ai#a1b2c3d4';

  late _MockFocusBloc bloc;
  late NotificationStopList stopList;

  NotificationItem item( String id, String text, { String? group } ) =>
      NotificationItem(
        id: id, message: text, type: 'progress', priority: 'low', senderId: who,
        timestamp: DateTime( 2026, 9, 28, 12 ), played: false, playCount: 0,
        responseRequested: false, suppressDing: false,
        displayQualifierWidget: false, progressGroupId: group );

  setUp( () async {
    SharedPreferences.setMockInitialValues( {} );
    stopList = NotificationStopList( await SharedPreferences.getInstance() );
    bloc     = _MockFocusBloc();
  } );

  void seed( List<FocusMessage> window, { String? reveal } ) {
    final st = const FocusChatState.initial().copyWith(
      senderOrder     : const [ who ],
      focusedSender   : who,
      hydration       : FocusHydration.ready,
      windows         : { who: window },
      revealMessageId : reveal,
    );
    whenListen( bloc, Stream<FocusChatState>.fromIterable( [ st ] ),
        initialState: st );
  }

  Widget host() => MaterialApp( home: Scaffold(
    body: BlocProvider<FocusChatBloc>.value(
      value : bloc,
      child : FocusChatPane( userEmail: 'rick@test.com', stopList: stopList ) ) ) );

  /// A small viewport, so a 7-message window genuinely overflows and "scrolled
  /// into view" is a real question rather than one the layout answers for free.
  Future<void> pumpSmall( WidgetTester tester ) async {
    tester.view.physicalSize     = const Size( 360, 320 );
    tester.view.devicePixelRatio = 1.0;
    addTearDown( tester.view.resetPhysicalSize );
    addTearDown( tester.view.resetDevicePixelRatio );
    await tester.pumpWidget( host() );
    await tester.pump();
    await tester.pump( const Duration( milliseconds: 400 ) );   // the scroll animation
  }

  group( "the reveal is consumed exactly once", () {
    testWidgets( "a reveal target makes the pane report it consumed", ( tester ) async {
      seed( [ FocusMessage( item: item( 'n-1', 'oldest' ) ),
              FocusMessage( item: item( 'n-2', 'newest' ) ) ],
            reveal: 'n-1' );

      await pumpSmall( tester );

      verify( () => bloc.add( const FocusRevealConsumed() ) ).called( 1 );
    } );

    testWidgets( "NO reveal target ⇒ nothing is consumed and nothing scrolls",
        ( tester ) async {
      seed( [ FocusMessage( item: item( 'n-1', 'oldest' ) ),
              FocusMessage( item: item( 'n-2', 'newest' ) ) ] );

      await pumpSmall( tester );

      verifyNever( () => bloc.add( const FocusRevealConsumed() ) );
    } );

    testWidgets( "a target that is NOT in the window is still consumed",
        ( tester ) async {
      // The window is capped at 7 and the stop-list can hide entries, so a tap on
      // an older notification can point at a message that is simply not here.
      // 🔴 IT MUST STILL BE CONSUMED: a reveal left set would re-fire on every
      // later rebuild, and the pane would keep trying to scroll to a message that
      // does not exist for as long as the conversation stays open.
      seed( [ FocusMessage( item: item( 'n-1', 'oldest' ) ) ], reveal: 'n-evicted' );

      await pumpSmall( tester );

      verify( () => bloc.add( const FocusRevealConsumed() ) ).called( 1 );
      expect( tester.takeException(), isNull,
          reason: 'and it does not throw looking for an element that is not there' );
    } );

    testWidgets( "a rebuild with the SAME target does not consume twice",
        ( tester ) async {
      final st = const FocusChatState.initial().copyWith(
        senderOrder: const [ who ], focusedSender: who,
        hydration: FocusHydration.ready,
        windows: { who: [ FocusMessage( item: item( 'n-1', 'a' ) ) ] },
        revealMessageId: 'n-1' );
      // Two identical states: a rebuild that changes nothing relevant.
      whenListen( bloc, Stream<FocusChatState>.fromIterable( [ st, st ] ),
          initialState: st );

      await pumpSmall( tester );
      await tester.pump( const Duration( milliseconds: 400 ) );

      verify( () => bloc.add( const FocusRevealConsumed() ) ).called( 1 );
    } );
  } );

  group( "scrolling to the target", () {
    /// Is [finder]'s widget actually WITHIN the visible viewport?
    ///
    /// 🔴 `findsOneWidget` IS THE WRONG QUESTION HERE, AND GETTING THAT WRONG
    /// WOULD MAKE THIS WHOLE GROUP VACUOUS. The pane builds its entire capped
    /// window (see the pane's `cacheExtent` note) precisely so `ensureVisible`
    /// has an element to reach — which means every bubble is FOUND by `find.text`
    /// whether or not a human could see it. On-screen-ness is a question about
    /// geometry, so it is asked about geometry.
    bool isOnScreen( WidgetTester tester, Finder finder ) {
      final rect   = tester.getRect( finder );
      final screen = tester.view.physicalSize / tester.view.devicePixelRatio;
      return rect.top >= 0 && rect.bottom <= screen.height;
    }

    final fullWindow = [ for ( var i = 1; i <= 7; i++ )
        FocusMessage( item: item( 'n-$i', 'message number $i' ) ) ];

    testWidgets( "the OLDEST message in a full window is brought INTO VIEW",
        ( tester ) async {
      // Newest-at-top, so the oldest sits at the BOTTOM of the list — below a
      // 320 dp viewport. This is the case where the scroll actually earns its
      // keep: messages arrived after the notification was posted.
      seed( fullWindow, reveal: 'n-1' );

      await pumpSmall( tester );

      expect( isOnScreen( tester, find.text( 'message number 1' ) ), isTrue,
          reason: 'the tapped message is what the user opened the app to read' );
    } );

    testWidgets( "NEGATIVE CONTROL: with no reveal the same message stays OFF screen",
        ( tester ) async {
      // Proof the row above measures the scroll and not the layout. Same window,
      // same viewport, no target — and the oldest message is built (so `find`
      // locates it) but sits below the fold.
      seed( fullWindow );

      await pumpSmall( tester );

      expect( find.text( 'message number 1' ), findsOneWidget,
          reason: 'built, because the pane builds its whole bounded window' );
      expect( isOnScreen( tester, find.text( 'message number 1' ) ), isFalse,
          reason: 'but not visible — nothing scrolled, because nothing asked' );
      expect( isOnScreen( tester, find.text( 'message number 7' ) ), isTrue,
          reason: 'the newest is at the top, where the list starts' );
    } );

    testWidgets( "revealing the NEWEST message leaves the list at the top",
        ( tester ) async {
      // The ordinary case, and the reason the scroll half is worth less than the
      // selection half: the message a user just tapped is normally item 0 and is
      // already in view, so the reveal costs a no-op scroll.
      seed( fullWindow, reveal: 'n-7' );

      await pumpSmall( tester );

      expect( isOnScreen( tester, find.text( 'message number 7' ) ), isTrue );
      expect( isOnScreen( tester, find.text( 'message number 1' ) ), isFalse,
          reason: 'and it did not scroll past what it was asked to show' );
    } );
  } );

  group( "a target buried in a collapsed progress group", () {
    testWidgets( "the group holding the target starts EXPANDED", ( tester ) async {
      // 🔴 ensureVisible NEEDS AN ELEMENT. A bubble inside a folded group is not
      // built, so scrolling to it resolves to nothing at all — the reveal would be
      // consumed and the list would not move, silently.
      seed( [
        FocusMessage( item: item( 'g-1', 'Step one',   group: 'pg-1' ) ),
        FocusMessage( item: item( 'g-2', 'Step two',   group: 'pg-1' ) ),
        FocusMessage( item: item( 'g-3', 'Step three', group: 'pg-1' ) ),
      ], reveal: 'g-1' );

      await pumpSmall( tester );

      expect( find.text( 'Step one' ), findsOneWidget,
          reason: 'the buried target is un-buried so it can be revealed' );
      expect( find.text( '×3' ), findsOneWidget,
          reason: 'and the user keeps the toggle — this expands the group, it does '
                  'not dissolve it' );
    } );

    testWidgets( "NEGATIVE CONTROL: with no reveal, the same group stays FOLDED",
        ( tester ) async {
      seed( [
        FocusMessage( item: item( 'g-1', 'Step one',   group: 'pg-1' ) ),
        FocusMessage( item: item( 'g-2', 'Step two',   group: 'pg-1' ) ),
        FocusMessage( item: item( 'g-3', 'Step three', group: 'pg-1' ) ),
      ] );

      await pumpSmall( tester );

      expect( find.text( 'Step one' ), findsNothing,
          reason: 'proof the expansion above is caused by the reveal, and not by '
                  'this group being expanded either way' );
      expect( find.text( 'Step three' ), findsOneWidget, reason: 'the summary' );
    } );

    testWidgets( "a group NOT holding the target is left folded", ( tester ) async {
      seed( [
        FocusMessage( item: item( 'a-1', 'Alpha one',   group: 'pg-a' ) ),
        FocusMessage( item: item( 'a-2', 'Alpha two',   group: 'pg-a' ) ),
        FocusMessage( item: item( 'a-3', 'Alpha three', group: 'pg-a' ) ),
        FocusMessage( item: item( 'b-1', 'Beta one',    group: 'pg-b' ) ),
        FocusMessage( item: item( 'b-2', 'Beta two',    group: 'pg-b' ) ),
        FocusMessage( item: item( 'b-3', 'Beta three',  group: 'pg-b' ) ),
      ], reveal: 'b-1' );

      await pumpSmall( tester );

      expect( find.text( 'Beta one' ), findsOneWidget, reason: 'the target group' );
      expect( find.text( 'Alpha one' ), findsNothing,
          reason: 'one tap must not unfold the whole conversation' );
    } );
  } );
}
