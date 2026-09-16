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
import 'package:lupin_mobile/features/queue/data/queue_models.dart';
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

/// Enough cards that the list is several screens tall and a 600px drag
/// actually moves it.
///
/// 🔴 THE SHAPE OF THESE CARDS IS PART OF THE TEST. When items are prepended
/// to a scrolled list, `RenderSliverList` issues a `scrollOffsetCorrection`
/// on the next layout, sized by the CHILD EXTENT it just measured — so how far
/// the re-anchor is pushed back depends on how tall a card is, and on nothing
/// else. A suite that only ever builds one card shape proves the anchor works
/// for that shape. Measured at 320×568 with a single jump and no re-check:
/// long question with no answer settled at 0 and passed, while short question
/// plus answer settled at 96 and short question alone at 172 — identically for
/// 6, 12 and 20 cards, because it is never about list length.
///
/// This is the same criticism the suite next door makes of its own viewport
/// case: a test tuned to one content shape passes for a reason it does not
/// state. Vary the shape, or the next content change silently re-opens this.
List<QuickAskEntry> cards( int n, { required String q, String? answer } ) =>
    List<QuickAskEntry>.generate( n, ( i ) => QuickAskEntry(
      questionText : '$q $i',
      state        : JobLifecycleState.completed,
      source       : QuickAskSource.transition,
      jobId        : 'job-$i',
      details      : answer == null ? null : JobSummary(
        jobId        : 'job-$i',
        status       : 'completed',
        responseText : answer,
      ),
    ) );

/// The three card shapes, by the height they give a card. The tall one is what
/// the suite used to test exclusively, and the only one a single jump survived.
final Map<String, List<QuickAskEntry>> kShapes = {
  'tall cards — long question, no answer' :
      cards( 12, q: 'Question number, long enough to fill a card row' ),
  'medium cards — question plus a short answer' :
      cards( 12, q: 'What is the weather today', answer: 'It will be sunny and mild.' ),
  'short cards — two-word question, no answer' :
      cards( 12, q: 'Hi' ),
};

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

/// 🔴 ASSERT ON THE BAND, NOT ON THE NUMBER. An offset of 0 is evidence that
/// the anchor ran, not that the user can read anything: the question is what
/// has to be visible. `ListView` clips hard at its viewport, so a band pushed
/// even 96px above it renders its Yes and No buttons — fully visible, fully
/// tappable — under a question whose text is hidden behind the record header.
/// On Door C, where dismissing POSTS the default, that is a user answering a
/// question they cannot read.
void expectQuestionReadable( WidgetTester tester, { required String shape } ) {
  final viewportTop = tester.getTopLeft( find.byKey( const Key( TestKeys.quickAskList ) ) ).dy;
  final question    = find.byKey( const Key( TestKeys.quickAskPromptQuestion ) );
  final yes         = find.byKey( const Key( TestKeys.promptYesButton ) );

  expect( question, findsOneWidget, reason: shape );
  expect( yes,      findsOneWidget, reason: shape );

  expect( tester.getTopLeft( question ).dy, greaterThanOrEqualTo( viewportTop ),
      reason : '$shape: the question is clipped above the list viewport, so the '
               'user would be answering text they cannot see' );
  expect( tester.getBottomLeft( yes ).dy, lessThanOrEqualTo( kSmallPhone.height ),
      reason : '$shape: the answer row must be on screen too' );
}

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

    // One case per card shape. See `kShapes` for why the shape is the variable
    // that matters here and list length is not.
    for ( final shape in kShapes.entries ) {
      testWidgets( 'a Door C prompt is scrolled back into view and is READABLE — ${shape.key}',
          ( tester ) async {
        final entries = shape.value;
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
        expectQuestionReadable( tester, shape: shape.key );
      } );
    }

    testWidgets( 'an interview turn arriving on a scrolled list is brought back too',
        ( tester ) async {
      final entries = cards( 12, q: 'Hi' );
      await mountAndScroll( tester, QuickAskState( connected: true, entries: entries ) );

      await emit( tester, QuickAskState(
        connected : true,
        entries   : entries,
        interview : turnOne,
      ) );

      expect( offset( tester ), 0 );
      expect( find.byKey( const Key( TestKeys.quickAskInterview ) ), findsOneWidget );
      expect(
        tester.getTopLeft( find.byKey( const Key( TestKeys.quickAskInterviewQ ) ) ).dy,
        greaterThanOrEqualTo(
            tester.getTopLeft( find.byKey( const Key( TestKeys.quickAskList ) ) ).dy ),
        reason : 'the interview question must not be clipped under the header either',
      );
    } );

    testWidgets( 'a SECOND surface beside a live prompt re-anchors as well',
        ( tester ) async {
      final entries = cards( 12, q: 'Hi' );
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
      expectQuestionReadable( tester, shape: 'prompt plus a late error' );
    } );

    testWidgets( 'a DIFFERENT error replacing the first one re-anchors',
        ( tester ) async {
      // The error tag carries the message's identity, like the prompt's id and
      // the interview's turn. Without that, error B replacing error A in a
      // band that is already live and off screen is new text the user is never
      // shown — the same harm, reached through the one surface whose slot was
      // already occupied.
      final entries = cards( 12, q: 'Hi' );
      final firstError = QuickAskState(
        connected    : true,
        entries      : entries,
        errorMessage : 'Could not accept the audio. Nothing was asked.',
      );
      final resting = await mountAndScroll( tester, firstError );
      expect( resting, greaterThan( 0 ) );

      await emit( tester, QuickAskState(
        connected    : true,
        entries      : entries,
        errorMessage : 'The server refused that question. Try rephrasing it.',
      ) );

      expect( offset( tester ), 0,
          reason : 'a replacement error is text the user has not seen yet' );
      expect( find.text( 'The server refused that question. Try rephrasing it.' ),
          findsOneWidget );
    } );

    testWidgets( 'the SAME error re-delivered does not move the list',
        ( tester ) async {
      // The other half of the identity claim: an unchanged band is not new,
      // so a rebuild carrying the same error must not yank the list.
      final entries = cards( 12, q: 'Hi' );
      const same    = 'Could not accept the audio. Nothing was asked.';
      final resting = await mountAndScroll( tester, QuickAskState(
        connected    : true,
        entries      : entries,
        errorMessage : same,
      ) );
      expect( resting, greaterThan( 0 ) );

      await emit( tester, QuickAskState(
        connected    : true,
        entries      : entries,
        errorMessage : same,
      ) );

      expect( offset( tester ), resting );
    } );

    testWidgets( 'ANSWERING a prompt does not yank the list back to the top',
        ( tester ) async {
      // The re-anchor fires on a surface ARRIVING. A band that empties is the
      // user finishing something, and moving the list under them then would
      // be a new annoyance in place of the old bug.
      final entries  = cards( 12, q: 'Hi' );
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
