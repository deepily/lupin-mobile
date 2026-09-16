/// Bug 9cddb791, second half — a question that arrives while the user is
/// reading the scrollback must still be a question the user can SEE.
///
/// 🔴 The interlock surfaces are list items now, prepended at index 0. A
/// `ListView` preserves its PIXEL offset when an item is inserted above the
/// viewport, so on a scrolled list the arriving prompt lands off screen while
/// the record button goes inert with "Answer the question above first"
/// pointing at nothing. That is the same defect `quick_ask_bloc.dart:963-966`
/// records as fixed — *"Holding the id alone blocked the record button on a
/// question the user was never shown, and Door C then timed out to its
/// 'no'"* — in a weaker form: the question exists, it is simply not on
/// screen, and Door C still expires to "no".
///
/// Every other case in this suite pumps a FRESH screen, which is always at
/// offset 0, which is why none of them can see this.
library;

import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/queue/domain/job_lifecycle.dart';
import 'package:lupin_mobile/features/quick_ask/data/quick_ask_models.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_bloc.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_event.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_state.dart';
import 'package:lupin_mobile/features/quick_ask/presentation/quick_ask_screen.dart';
import 'package:lupin_mobile/services/tts/tts_orchestrator.dart';

class MockQuickAskBloc extends MockBloc<QuickAskEvent, QuickAskState>
    implements QuickAskBloc {}

class MockTtsOrchestrator extends Mock implements TtsOrchestrator {}

const Size kSmallPhone = Size( 320, 568 );

const QuickAskPrompt doorC = QuickAskPrompt(
  id       : 'n-1',
  question : 'Is that the same as: what is the weather?',
);

const QuickAskInterview turnOne = QuickAskInterview(
  pendingId : 'p-1',
  question  : 'Which city?',
);

/// Enough answered cards that the list is several screens tall and a 600px
/// drag actually moves it.
List<QuickAskEntry> history( int n ) => List<QuickAskEntry>.generate( n, ( i ) =>
    QuickAskEntry(
      questionText : 'Question number $i, long enough to fill a card row',
      state        : JobLifecycleState.completed,
      source       : QuickAskSource.transition,
      jobId        : 'job-$i',
    ) );

/// Where the scrollback is currently parked, in pixels from the top.
///
/// `.first` because a prompt body that is ON SCREEN brings its own
/// `Scrollable` (the text field's) into the subtree — the list's own is the
/// outermost, so it comes first in tree order.
double offset( WidgetTester tester ) => tester.state<ScrollableState>(
  find.descendant(
    of       : find.byKey( const Key( TestKeys.quickAskList ) ),
    matching : find.byType( Scrollable ),
  ).first,
).position.pixels;

void main() {
  late MockQuickAskBloc         bloc;
  late MockTtsOrchestrator      tts;
  late StreamController<QuickAskState> states;

  setUpAll( () {
    registerFallbackValue( const QuickAskRecordPressed() );
    registerFallbackValue( const TtsSender() );
  } );

  setUp( () {
    bloc   = MockQuickAskBloc();
    tts    = MockTtsOrchestrator();
    states = StreamController<QuickAskState>.broadcast();
    when( () => tts.isPaused ).thenReturn( false );
    when( () => tts.pausedStream ).thenAnswer( ( _ ) => const Stream<bool>.empty() );
    when( () => tts.queueDepth ).thenReturn( 0 );
    when( () => tts.queueDepthStream ).thenAnswer( ( _ ) => const Stream<int>.empty() );
    GetIt.instance.registerSingleton<TtsOrchestrator>( tts );
  } );

  tearDown( () async {
    await states.close();
    await GetIt.instance.reset();
  } );

  /// Mounts the screen on [initial], drags the scrollback up by [dragBy], and
  /// returns the offset it came to rest at.
  Future<double> mountAndScroll(
    WidgetTester  tester,
    QuickAskState initial, {
    double        dragBy = 600,
  } ) async {
    tester.view.physicalSize     = kSmallPhone;
    tester.view.devicePixelRatio = 1.0;
    addTearDown( tester.view.reset );

    whenListen( bloc, states.stream, initialState: initial );
    await tester.pumpWidget( MaterialApp(
      home : BlocProvider<QuickAskBloc>.value( value: bloc, child: const QuickAskScreen() ),
    ) );
    await tester.pump();

    await tester.drag( find.byKey( const Key( TestKeys.quickAskList ) ),
        Offset( 0, -dragBy ) );
    await tester.pumpAndSettle();
    return offset( tester );
  }

  /// Pushes [next] through the bloc and lets the post-frame re-anchor run.
  Future<void> emit( WidgetTester tester, QuickAskState next ) async {
    states.add( next );
    await tester.pumpAndSettle();
  }

  group( 'bug 9cddb791 — a prompt arriving on a SCROLLED list', () {

    testWidgets( 'a Door C prompt is scrolled back into view and is answerable',
        ( tester ) async {
      final entries = history( 12 );
      final resting = await mountAndScroll( tester,
          QuickAskState( connected: true, entries: entries ) );
      expect( resting, greaterThan( 0 ),
          reason : 'the probe is meaningless unless the drag actually scrolled' );

      await emit( tester, QuickAskState(
        connected     : true,
        entries       : entries,
        pendingPrompt : doorC,
      ) );

      expect( offset( tester ), 0,
          reason : 'the list must re-anchor so the prepended prompt is on screen' );

      // Built AND inside the viewport — "built" alone was true of the old
      // fixed-Column layout too, and is satisfied by a widget under the fold.
      final yes = find.byKey( const Key( TestKeys.promptYesButton ) );
      expect( yes, findsOneWidget );
      expect( tester.getBottomLeft( yes ).dy,
          lessThanOrEqualTo( kSmallPhone.height ),
          reason : 'the mic is inert on this question, so it has to be answerable' );
    } );

    testWidgets( 'an interview turn arriving on a scrolled list is brought back too',
        ( tester ) async {
      final entries = history( 12 );
      await mountAndScroll( tester, QuickAskState( connected: true, entries: entries ) );

      await emit( tester, QuickAskState(
        connected : true,
        entries   : entries,
        interview : turnOne,
      ) );

      expect( offset( tester ), 0 );
      expect( find.byKey( const Key( TestKeys.quickAskInterview ) ), findsOneWidget );
    } );

    testWidgets( 'a SECOND surface beside a live prompt re-anchors as well',
        ( tester ) async {
      final entries = history( 12 );
      final prompted = QuickAskState(
        connected     : true,
        entries       : entries,
        pendingPrompt : doorC,
      );

      whenListen( bloc, states.stream, initialState: prompted );
      tester.view.physicalSize     = kSmallPhone;
      tester.view.devicePixelRatio = 1.0;
      addTearDown( tester.view.reset );
      await tester.pumpWidget( MaterialApp(
        home : BlocProvider<QuickAskBloc>.value( value: bloc, child: const QuickAskScreen() ),
      ) );
      await tester.pump();

      // The prompt is not modal — reading the scrollback under it is allowed.
      await tester.drag( find.byKey( const Key( TestKeys.quickAskList ) ),
          const Offset( 0, -600 ) );
      await tester.pumpAndSettle();
      expect( offset( tester ), greaterThan( 0 ) );

      await emit( tester, QuickAskState(
        connected     : true,
        entries       : entries,
        pendingPrompt : doorC,
        errorMessage  : 'Could not accept the audio. Nothing was asked.',
      ) );

      expect( offset( tester ), 0 );
    } );

    testWidgets( 'ANSWERING a prompt does not yank the list back to the top',
        ( tester ) async {
      // The re-anchor fires on a surface ARRIVING. A band that empties is the
      // user finishing something, and moving the list under them then would
      // be a new annoyance in place of the old bug.
      final entries  = history( 12 );
      final prompted = QuickAskState(
        connected     : true,
        entries       : entries,
        pendingPrompt : doorC,
      );
      final resting = await mountAndScroll( tester, prompted );
      expect( resting, greaterThan( 0 ) );

      await emit( tester, QuickAskState( connected: true, entries: entries ) );

      expect( offset( tester ), resting,
          reason : 'dismissing a surface must leave the scroll position alone' );
    } );
  } );
}
