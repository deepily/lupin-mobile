/// AC-S2.2b / AC-S2.3 / AC-S2.4 / AC-S2.5b — the SCREEN, under `MockBloc`.
///
/// 🔴 Scope, stated so this file is not mistaken for more than it is: these
/// are RENDERING assertions only. Mocking the bloc replaces the computation,
/// so nothing here can speak to whether `canRecord` is CORRECT — that is
/// AC-S2.2a, driven against a real bloc in
/// `test/unit/quick_ask/quick_ask_predicate_test.dart`. The split exists
/// because the old combined AC could not discriminate by construction.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:get_it/get_it.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/services/tts/tts_orchestrator.dart';
import 'package:lupin_mobile/shared/widgets/tts_pause_control.dart';
import 'package:lupin_mobile/features/queue/data/queue_models.dart';
import 'package:lupin_mobile/features/queue/domain/job_lifecycle.dart';
import 'package:lupin_mobile/features/quick_ask/data/quick_ask_models.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_bloc.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_event.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_state.dart';
import 'package:lupin_mobile/features/quick_ask/presentation/quick_ask_screen.dart';

class MockQuickAskBloc extends MockBloc<QuickAskEvent, QuickAskState>
    implements QuickAskBloc {}

class MockTtsOrchestrator extends Mock implements TtsOrchestrator {}

QuickAskEntry entry( {
  String jobId = 'j-1',
  required JobLifecycleState state,
  String question = 'what is the weather',
  String? answer,
  String? error,
} ) => QuickAskEntry(
  questionText : question,
  state        : state,
  source       : QuickAskSource.transition,
  jobId        : jobId,
  details      : JobSummary(
    jobId        : jobId,
    questionText : question,
    status       : state.name,
    responseText : answer,
    error        : error,
  ),
);

void main() {
  late MockQuickAskBloc bloc;

  setUpAll( () {
    registerFallbackValue( const QuickAskRecordPressed() );
    registerFallbackValue( const TtsSender() );
  } );

  late MockTtsOrchestrator tts;

  setUp( () {
    bloc = MockQuickAskBloc();
    tts  = MockTtsOrchestrator();
    when( () => tts.isPaused ).thenReturn( false );
    when( () => tts.pausedStream ).thenAnswer( ( _ ) => const Stream<bool>.empty() );
    when( () => tts.queueDepth ).thenReturn( 0 );
    when( () => tts.queueDepthStream ).thenAnswer( ( _ ) => const Stream<int>.empty() );
    GetIt.instance.registerSingleton<TtsOrchestrator>( tts );
  } );

  tearDown( () async { await GetIt.instance.reset(); } );

  Widget host( QuickAskState state, { MockQuickAskBloc? using } ) {
    final b = using ?? bloc;
    whenListen( b, Stream<QuickAskState>.fromIterable( const [] ), initialState: state );
    return MaterialApp(
      home: BlocProvider<QuickAskBloc>.value( value: b, child: const QuickAskScreen() ),
    );
  }

  /// A FRESH mock per case. Re-pumping `host()` with the same bloc reuses the
  /// element tree and the `BlocBuilder` keeps its first state — the loop would
  /// silently assert the first case four times.
  Future<void> pumpFresh( WidgetTester tester, QuickAskState state ) async {
    await tester.pumpWidget( host( state, using: MockQuickAskBloc() ) );
    await tester.pump();
  }

  group( 'AC-S2.2b — the screen RENDERS canRecord correctly', () {

    testWidgets( 'canRecord false disables the button and shows the supplied reason', ( tester ) async {
      // Disconnected ⇒ the predicate is false and names the socket. The screen
      // must show THAT reason, not a generic "unavailable".
      await tester.pumpWidget( host( const QuickAskState( connected: false ) ) );
      await tester.pump();

      final reason = find.byKey( const Key( TestKeys.quickAskBlockedReason ) );
      expect( reason, findsOneWidget );
      expect( ( tester.widget<Text>( reason ) ).data, 'Not connected — reconnecting' );

      // Disabled: the gesture callbacks are detached, so a long-press adds
      // nothing to the bloc.
      await tester.longPress( find.byKey( const Key( TestKeys.quickAskRecordButton ) ) );
      await tester.pump();
      verifyNever( () => bloc.add( any() ) );
    } );

    testWidgets( 'canRecord true enables the button and shows NO reason', ( tester ) async {
      await tester.pumpWidget( host( const QuickAskState( connected: true ) ) );
      await tester.pump();

      expect( find.byKey( const Key( TestKeys.quickAskBlockedReason ) ), findsNothing );

      await tester.longPress( find.byKey( const Key( TestKeys.quickAskRecordButton ) ) );
      await tester.pump();
      verify( () => bloc.add( const QuickAskRecordPressed() ) ).called( 1 );
    } );

    testWidgets( 'each block reason renders its OWN message, not a shared one', ( tester ) async {
      final cases = <QuickAskState, String>{
        const QuickAskState( connected: false ) : 'Not connected — reconnecting',
        const QuickAskState( connected: true, pendingPromptId: 'p' ) : 'Answer the question above first',
        const QuickAskState( connected: true, liveJobId: 'j' ) : 'Waiting on your last question',
        const QuickAskState( connected: true, capturing: true ) : 'Already recording somewhere else',
      };
      for ( final c in cases.entries ) {
        await pumpFresh( tester, c.key );
        expect( find.text( c.value ), findsOneWidget,
            reason: 'a shared message would make three of these pass wrongly' );
      }
    } );
  } );

  group( 'AC-S2.3 — pinned header, newest pair on top', () {

    testWidgets( 'the record button is a FIXED HEADER, not item 0 of the list', ( tester ) async {
      await tester.pumpWidget( host( QuickAskState(
        connected : true,
        entries   : [ entry( jobId: 'a', state: JobLifecycleState.completed, answer: 'A' ) ],
      ) ) );
      await tester.pump();

      final button = find.byKey( const Key( TestKeys.quickAskRecordButton ) );
      final list   = find.byKey( const Key( TestKeys.quickAskList ) );
      expect( button, findsOneWidget );
      expect( list,   findsOneWidget );

      // Structural, not positional: the button is NOT a descendant of the list.
      expect( find.descendant( of: list, matching: button ), findsNothing );
      // And it sits above the list on screen.
      expect( tester.getBottomLeft( button ).dy,
          lessThanOrEqualTo( tester.getTopLeft( list ).dy ) );
    } );

    testWidgets( 'NEWEST pair renders on top', ( tester ) async {
      await tester.pumpWidget( host( QuickAskState(
        connected : true,
        entries   : [
          entry( jobId: 'older',  state: JobLifecycleState.completed, question: 'asked first'  ),
          entry( jobId: 'newer',  state: JobLifecycleState.completed, question: 'asked second' ),
        ],
      ) ) );
      await tester.pump();

      final firstY  = tester.getTopLeft( find.text( 'asked second' ) ).dy;
      final secondY = tester.getTopLeft( find.text( 'asked first'  ) ).dy;
      expect( firstY, lessThan( secondY ), reason: 'newest first (Rick ruling 3)' );
    } );

    testWidgets( '🔴 rendered by .reversed — the ListView is NOT reverse: true', ( tester ) async {
      // `reverse: true` anchors scroll to the BOTTOM, fighting the pinned top
      // header the same AC requires. `grep -rn "reverse: true" lib/` returns
      // zero; the in-tree convention is store oldest→newest then `.reversed`.
      await tester.pumpWidget( host( QuickAskState(
        connected : true,
        entries   : [ entry( jobId: 'a', state: JobLifecycleState.completed ) ],
      ) ) );
      await tester.pump();

      final lv = tester.widget<ListView>( find.byKey( const Key( TestKeys.quickAskList ) ) );
      expect( lv.reverse, isFalse );
    } );

    testWidgets( 'an empty scrollback says so rather than rendering a blank list', ( tester ) async {
      await tester.pumpWidget( host( const QuickAskState( connected: true ) ) );
      await tester.pump();
      expect( find.byKey( const Key( TestKeys.quickAskEmpty ) ), findsOneWidget );
    } );
  } );

  group( 'AC-S2.4 — status chips render from JobLane', () {

    testWidgets( 'todo / run / done each render their own chip', ( tester ) async {
      for ( final c in <JobLifecycleState, String>{
        JobLifecycleState.queued    : 'Queued',
        JobLifecycleState.running   : 'Working',
        JobLifecycleState.completed : 'Answered',
      }.entries ) {
        await pumpFresh( tester, QuickAskState(
          connected : true,
          entries   : [ entry( state: c.key ) ],
        ) );
        expect( find.text( c.value ), findsOneWidget );
        expect( find.byKey( Key( '${TestKeys.quickAskChipPrefix}${c.key.lane.name}' ) ), findsOneWidget );
      }
    } );

    testWidgets( 'STALLED renders in the TODO lane, not as a failure', ( tester ) async {
      // The one a hand-rolled lane map gets wrong: a stalled job is resumable.
      await tester.pumpWidget( host( QuickAskState(
        connected : true,
        entries   : [ entry( state: JobLifecycleState.stalled ) ],
      ) ) );
      await tester.pump();
      expect( find.text( 'Queued' ), findsOneWidget );
      expect( find.text( 'Failed' ), findsNothing );
    } );

    testWidgets( 'a DEAD lane renders an error card carrying the error text', ( tester ) async {
      await tester.pumpWidget( host( QuickAskState(
        connected : true,
        entries   : [ entry( state: JobLifecycleState.failed, error: 'agent exploded' ) ],
      ) ) );
      await tester.pump();

      expect( find.byKey( const Key( '${TestKeys.quickAskErrorCardPrefix}j-1' ) ), findsOneWidget );
      expect( find.text( 'agent exploded' ), findsOneWidget );
      expect( find.text( 'Failed' ),         findsOneWidget );
    } );

    testWidgets( 'a done card renders the answer', ( tester ) async {
      await tester.pumpWidget( host( QuickAskState(
        connected : true,
        entries   : [ entry( state: JobLifecycleState.completed, answer: 'It is sunny.' ) ],
      ) ) );
      await tester.pump();
      expect( find.byKey( const Key( '${TestKeys.quickAskAnswerPrefix}j-1' ) ), findsOneWidget );
      expect( find.text( 'It is sunny.' ), findsOneWidget );
    } );
  } );

  group( 'AC-S2.5b — the error renders inline', () {

    testWidgets( 'an error state renders the inline message and the screen stays idle', ( tester ) async {
      await tester.pumpWidget( host( const QuickAskState(
        connected    : true,
        errorMessage : 'Transcription came back empty',
      ) ) );
      await tester.pump();

      expect( find.byKey( const Key( TestKeys.quickAskError ) ), findsOneWidget );
      expect( find.text( 'Transcription came back empty' ), findsOneWidget );
      expect( find.text( 'Hold to ask' ), findsOneWidget );
    } );

    testWidgets( 'dismissing the error tells the bloc', ( tester ) async {
      await tester.pumpWidget( host( const QuickAskState(
        connected : true, errorMessage : 'Microphone permission denied' ) ) );
      await tester.pump();

      await tester.tap( find.descendant(
        of      : find.byKey( const Key( TestKeys.quickAskError ) ),
        matching: find.byIcon( Icons.close ) ) );
      await tester.pump();

      verify( () => bloc.add( const QuickAskErrorDismissed() ) ).called( 1 );
    } );

    testWidgets( 'no error state renders no error surface', ( tester ) async {
      await tester.pumpWidget( host( const QuickAskState( connected: true ) ) );
      await tester.pump();
      expect( find.byKey( const Key( TestKeys.quickAskError ) ), findsNothing );
    } );
  } );

  group( 'the lost banner — a watchdog verdict the user can read', () {

    testWidgets( 'lost renders a banner that says what happened, not "an error occurred"', ( tester ) async {
      await tester.pumpWidget( host( const QuickAskState( connected: true, lost: true ) ) );
      await tester.pump();
      final banner = find.byKey( const Key( TestKeys.quickAskLostBanner ) );
      expect( banner, findsOneWidget );
      expect( tester.widget<Text>( find.descendant( of: banner, matching: find.byType( Text ) ) ).data,
          contains( 'no longer lists it' ) );
    } );

    testWidgets( 'not lost renders no banner', ( tester ) async {
      await tester.pumpWidget( host( const QuickAskState( connected: true ) ) );
      await tester.pump();
      expect( find.byKey( const Key( TestKeys.quickAskLostBanner ) ), findsNothing );
    } );
  } );

  group( 'AC-S3.5c — the SHARED pause/replay control is MOUNTED, not reimplemented', () {

    testWidgets( 'the pause toggle on screen is seat B\'s shared widget', ( tester ) async {
      await tester.pumpWidget( host( const QuickAskState( connected: true ) ) );
      await tester.pump();

      expect( find.byType( TtsPauseToggle ), findsOneWidget );
      expect( find.byKey( const Key( TestKeys.quickAskPauseToggle ) ), findsOneWidget );
    } );

    testWidgets( '🔴 this screen holds NO StreamBuilder of its own over pausedStream', ( tester ) async {
      // The falsifier AC-S3.5c names: a screen that renders its own inline
      // StreamBuilder passes every behavioural assertion while leaving a THIRD
      // copy in the tree, which IS the defect. Asserted on the source, because
      // a widget test cannot tell whose StreamBuilder it is looking at.
      // COMMENTS STRIPPED FIRST. The naive version of this check matched the
      // comment that explains why the screen does not do this — a source scan
      // that reads prose as code is a scan that fails on its own explanation.
      final raw  = File( 'lib/features/quick_ask/presentation/quick_ask_screen.dart' ).readAsStringSync();
      final code = raw.split( '\n' )
          .where( ( l ) => !l.trimLeft().startsWith( '//' ) )
          .join( '\n' );

      expect( code.contains( 'pausedStream' ), isFalse,
          reason: 'Quick Ask must MOUNT the shared control, never re-derive paused state' );
      expect( code.contains( 'StreamBuilder' ), isFalse,
          reason: 'a third StreamBuilder over the same stream IS the defect AC-S3.5c prevents' );
      // Positive half — the check must not pass merely because the file is empty.
      expect( code, contains( 'TtsPauseToggle' ) );
      expect( code, contains( 'TtsPausedBanner' ) );
    } );

    testWidgets( 'a paused orchestrator renders the shared banner WITH a stated reason', ( tester ) async {
      // The user-visible half: someone who paused in focus mode arrives here
      // to an explanation, not a bare icon.
      when( () => tts.isPaused ).thenReturn( true );
      when( () => tts.queueDepth ).thenReturn( 2 );
      await tester.pumpWidget( host( const QuickAskState( connected: true ) ) );
      await tester.pump();

      expect( find.byType( TtsPausedBanner ), findsOneWidget );
      expect( find.byKey( const Key( TestKeys.quickAskPausedBanner ) ), findsOneWidget );
      expect( find.textContaining( 'Tap replay' ), findsOneWidget );
    } );

    testWidgets( 'an UNPAUSED orchestrator renders no banner', ( tester ) async {
      await tester.pumpWidget( host( const QuickAskState( connected: true ) ) );
      await tester.pump();
      expect( find.byKey( const Key( TestKeys.quickAskPausedBanner ) ), findsNothing );
    } );
  } );

  group( 'the replay button — mounted by S2, behaviour owned by S3', () {

    testWidgets( 'a done card with a non-empty answer offers Replay', ( tester ) async {
      await tester.pumpWidget( host( QuickAskState(
        connected : true,
        entries   : [ entry( state: JobLifecycleState.completed, answer: 'It is sunny.' ) ],
      ) ) );
      await tester.pump();
      expect( find.byKey( const Key( '${TestKeys.quickAskReplayPrefix}j-1' ) ), findsOneWidget );
    } );

    testWidgets( 'a card with NO answer offers no Replay', ( tester ) async {
      await tester.pumpWidget( host( QuickAskState(
        connected : true,
        entries   : [ entry( state: JobLifecycleState.running ) ],
      ) ) );
      await tester.pump();
      expect( find.byKey( const Key( '${TestKeys.quickAskReplayPrefix}j-1' ) ), findsNothing );
    } );

    testWidgets( 'a FAILED card offers no Replay — there is nothing to replay', ( tester ) async {
      await tester.pumpWidget( host( QuickAskState(
        connected : true,
        entries   : [ entry( state: JobLifecycleState.failed, error: 'boom' ) ],
      ) ) );
      await tester.pump();
      expect( find.byKey( const Key( '${TestKeys.quickAskReplayPrefix}j-1' ) ), findsNothing );
    } );

    testWidgets( '🔴 tapping Replay calls replay(), NOT a bare enqueueAlways', ( tester ) async {
      // AC-S3.4b: an urgent enqueue preempts only when NOT paused, so a bare
      // `enqueueAlways(priority:"urgent")` here would enqueue and play nothing
      // while held — and pause-then-rewind is the natural gesture. Routing
      // through `replay()` is what calls `resume()` first.
      when( () => tts.replay(
        message : any( named: 'message' ),
        title   : any( named: 'title' ),
        voiceId : any( named: 'voiceId' ),
        sender  : any( named: 'sender' ),
      ) ).thenReturn( null );

      await tester.pumpWidget( host( QuickAskState(
        connected : true,
        entries   : [ entry( state: JobLifecycleState.completed, answer: 'It is sunny.' ) ],
      ) ) );
      await tester.pump();

      await tester.tap( find.byKey( const Key( '${TestKeys.quickAskReplayPrefix}j-1' ) ) );
      await tester.pump();

      verify( () => tts.replay(
        message : 'It is sunny.',
        title   : any( named: 'title' ),
        voiceId : any( named: 'voiceId' ),
        sender  : any( named: 'sender' ),
      ) ).called( 1 );
      verifyNever( () => tts.enqueueAlways(
        priority : any( named: 'priority' ),
        message  : any( named: 'message' ),
        title    : any( named: 'title' ),
        voiceId  : any( named: 'voiceId' ),
        sender   : any( named: 'sender' ),
        verbatim : any( named: 'verbatim' ),
      ) );
    } );
  } );
}
