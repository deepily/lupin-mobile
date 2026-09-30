/// AC-S4.12 (RENDER half) — the Door-A interview is RE-ENTRANT on screen.
///
/// 🔴 The gap this file closes. `resume_interview_test.dart` already proves the
/// BLOC re-posts the same `pending_id` and shrinks `args_missing`. Nobody had
/// asserted the SCREEN re-renders the second question — and that is the half
/// the defect lives in. `_InterviewPrompt`'s own docstring names it: *"a client
/// that treats the first `resume` as terminal renders the answer card after
/// turn one and never asks the second question… Rick's ruling 5 silently
/// half-implemented."* A bloc-only suite passes with that screen.
///
/// `flow.py` comments the loop verbatim — *"Interview continues — re-ask the
/// next arg on the SAME pending_id"* — so a three-argument question is three
/// round trips on ONE id, and every turn after the first is a RE-render of a
/// surface that was already mounted.
///
/// 🔴 REAL bloc, REAL screen, same reason `door_c_interlock_test.dart` gives:
/// a `MockBloc` version could not discriminate by construction. What is under
/// test IS the wiring between the parked response, the mounted prompt, the
/// resume door, and what the second parked response does to a surface that is
/// already on screen.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/queue/data/queue_models.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_bloc.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_event.dart';
import 'package:lupin_mobile/features/quick_ask/presentation/quick_ask_screen.dart';
import 'package:lupin_mobile/services/tts/tts_orchestrator.dart';

import '../../unit/quick_ask/_quick_ask_harness.dart';

class MockTtsOrchestrator extends Mock implements TtsOrchestrator {}

/// A parked ask — Door A holding a `pending_id` open for one more argument.
AskResponse parked( {
  required String pendingId,
  required String question,
  List<String>    missing = const [],
} ) => AskResponse(
  path        : 'needs_input',
  status      : 'parked',
  routeReason : 'args_missing',
  traceId     : 'tr-p',
  answer      : question,
  pendingId   : pendingId,
  argsMissing : missing,
);

/// The interview's terminal turn — the server has what it needs and answers.
AskResponse doneWith( String answer ) => AskResponse(
  path        : 'agent',
  status      : 'done',
  routeReason : 'router:weather',
  traceId     : 'tr-d',
  answer      : answer,
  jobId       : 'j-final',
);

void main() {
  setUpAll( () {
    registerFallbackValue( const AskRequest( question: 'x' ) );
    registerFallbackValue( const ResumeRequest( pendingId: 'p', answer: 'a' ) );
  } );

  late MockTtsOrchestrator tts;

  setUp( () {
    tts = MockTtsOrchestrator();
    when( () => tts.isPaused ).thenReturn( false );
    when( () => tts.pausedStream ).thenAnswer( ( _ ) => const Stream<bool>.empty() );
    when( () => tts.queueDepth ).thenReturn( 0 );
    when( () => tts.queueDepthStream ).thenAnswer( ( _ ) => const Stream<int>.empty() );
    GetIt.instance.registerSingleton<TtsOrchestrator>( tts );
  } );

  tearDown( () async { await GetIt.instance.reset(); } );

  Widget host( QuickAskBloc bloc ) => MaterialApp(
    home: BlocProvider<QuickAskBloc>.value( value: bloc, child: const QuickAskScreen() ),
  );

  /// 🔴 NOT the harness's `settle()`. Inside `testWidgets` the clock is FAKE,
  /// so a bare `Future.delayed( Duration.zero )` never fires — the file HANGS
  /// rather than failing. Pumping is how time moves here. (Same hazard
  /// `door_c_interlock_test.dart` documents; it hung the whole run at +77.)
  Future<void> drain( WidgetTester tester, [ int rounds = 8 ] ) async {
    for ( var i = 0; i < rounds; i++ ) {
      await tester.pump( Duration.zero );
    }
  }

  /// 🔴 `dispose()` must run in the REAL async zone — `Bloc.close()` cancels a
  /// subscription to the harness's `async*` connection stream, and under the
  /// fake clock that await never completes.
  Future<void> teardown( WidgetTester tester, Harness h ) =>
      tester.runAsync( () => h.dispose() );

  /// Records a question whose ask comes back PARKED, with the screen mounted,
  /// and leaves turn 1's prompt on screen.
  Future<Harness> openInterview(
    WidgetTester tester, {
    String       pendingId = 'pend-1',
    String       question  = 'Which city?',
    List<String> missing   = const [ 'city', 'when' ],
  } ) async {
    final h = Harness();
    h.stubEmptyQueues();
    when( () => h.asr.stopAndTranscribe() )
        .thenAnswer( ( _ ) async => 'what is the weather' );
    when( () => h.repo.ask( any() ) ).thenAnswer(
      ( _ ) async => parked( pendingId: pendingId, question: question, missing: missing ) );

    await tester.pumpWidget( host( h.bloc ) );
    await drain( tester );

    h.bloc.add( const QuickAskRecordPressed() );
    await tester.pump();
    h.bloc.add( const QuickAskRecordReleased() );
    await drain( tester );
    h.bloc.add( const QuickAskDraftSent() );
    await drain( tester );
    await tester.pump();
    return h;
  }

  /// Types into the interview's shared `OpenEndedPromptBody` and submits.
  Future<void> answerWith( WidgetTester tester, String text ) async {
    await tester.enterText(
      find.descendant(
        of        : find.byKey( const Key( TestKeys.quickAskInterview ) ),
        matching  : find.byType( TextField ),
      ),
      text,
    );
    await tester.pump();
    await tester.tap(
      find.descendant(
        of       : find.byKey( const Key( TestKeys.quickAskInterview ) ),
        matching : find.widgetWithText( FilledButton, 'Submit' ),
      ),
    );
    await drain( tester );
    await tester.pump();
  }

  Finder interviewQuestion() => find.byKey( const Key( TestKeys.quickAskInterviewQ ) );

  /// Any rendered answer — the keys are `quickAsk.answer.<jobId>`, so this
  /// matches on the prefix rather than guessing an id.
  Finder answerCards() => find.byWidgetPredicate( ( w ) =>
      w.key is ValueKey<String> &&
      ( w.key as ValueKey<String> ).value.startsWith( TestKeys.quickAskAnswerPrefix ) );

  group( 'AC-S4.12 — turn 1 RENDERS the question, not an answer', () {

    testWidgets( 'a parked ask mounts the interview prompt carrying the question', ( tester ) async {
      final h = await openInterview( tester );

      expect( find.byKey( const Key( TestKeys.quickAskInterview ) ), findsOneWidget );
      expect( tester.widget<Text>( interviewQuestion() ).data, 'Which city?' );
      await teardown( tester, h );
    } );

    testWidgets( 'nothing is answered yet — no answer card is on screen', ( tester ) async {
      final h = await openInterview( tester );

      // The falsifier for the whole file: an answer card here means the client
      // treated a PARKED response as terminal. NOT the empty-scrollback key —
      // `liveQuestion` is already set by the transcription, so `_Scrollback`
      // is past its empty state while still holding zero answers.
      expect( answerCards(), findsNothing );
      expect( find.byKey( const Key( TestKeys.quickAskInterview ) ), findsOneWidget );
      await teardown( tester, h );
    } );
  } );

  group( '🔴 AC-S4.12 — turn 2 RE-RENDERS on the SAME pending_id', () {

    testWidgets( 'answering posts the answer to resume on the SAME id', ( tester ) async {
      final h = await openInterview( tester, pendingId: 'pend-1' );

      when( () => h.repo.resume( any() ) ).thenAnswer( ( _ ) async => parked(
        pendingId: 'pend-1', question: 'Which day?', missing: [ 'when' ] ) );

      await answerWith( tester, 'Washington' );

      final sent = verify( () => h.repo.resume( captureAny() ) ).captured
          .single as ResumeRequest;
      expect( sent.pendingId, 'pend-1', reason: 'the interview never starts a new id' );
      expect( sent.answer,    'Washington' );
      await teardown( tester, h );
    } );

    testWidgets( 'the SECOND question replaces the first ON SCREEN', ( tester ) async {
      // 🔴 THE regression. A client that treats the first `resume` as terminal
      // renders an answer card here and never asks question two — and a
      // bloc-only suite cannot see the difference.
      final h = await openInterview( tester, pendingId: 'pend-1' );

      when( () => h.repo.resume( any() ) ).thenAnswer( ( _ ) async => parked(
        pendingId: 'pend-1', question: 'Which day?', missing: [ 'when' ] ) );

      await answerWith( tester, 'Washington' );

      expect( find.byKey( const Key( TestKeys.quickAskInterview ) ), findsOneWidget,
          reason: 'the prompt stays mounted for turn 2' );
      expect( tester.widget<Text>( interviewQuestion() ).data, 'Which day?' );
      expect( find.text( 'Which city?' ), findsNothing,
          reason: 'turn 1 is replaced, not stacked' );
      await teardown( tester, h );
    } );

    testWidgets( 'the answer field is CLEAR for turn 2 — turn 1\'s text is not resubmitted',
        ( tester ) async {
      final h = await openInterview( tester, pendingId: 'pend-1' );

      when( () => h.repo.resume( any() ) ).thenAnswer( ( _ ) async => parked(
        pendingId: 'pend-1', question: 'Which day?', missing: [ 'when' ] ) );

      await answerWith( tester, 'Washington' );

      final field = tester.widget<TextField>( find.descendant(
        of       : find.byKey( const Key( TestKeys.quickAskInterview ) ),
        matching : find.byType( TextField ),
      ) );
      expect( field.controller?.text ?? '', isEmpty,
          reason: 'a stale controller would re-post "Washington" as the day' );
      await teardown( tester, h );
    } );
  } );

  group( 'AC-S4.12 — the interview ENDS, on screen', () {

    testWidgets( 'a terminal resume swaps the prompt for the answer', ( tester ) async {
      final h = await openInterview( tester, missing: [ 'city' ] );

      when( () => h.repo.resume( any() ) )
          .thenAnswer( ( _ ) async => doneWith( 'Sunny, 72 degrees.' ) );

      await answerWith( tester, 'Washington' );

      expect( find.byKey( const Key( TestKeys.quickAskInterview ) ), findsNothing,
          reason: 'the server stopped asking, so the prompt comes down' );
      expect( find.text( 'Sunny, 72 degrees.' ), findsOneWidget );
      await teardown( tester, h );
    } );

    testWidgets( 'cancelling takes the prompt down and leaves nothing half-asked', ( tester ) async {
      final h = await openInterview( tester );

      await tester.tap( find.byKey( const Key( TestKeys.quickAskInterviewCancel ) ) );
      await drain( tester );
      await tester.pump();

      expect( find.byKey( const Key( TestKeys.quickAskInterview ) ), findsNothing );
      verifyNever( () => h.repo.resume( any() ) );
      await teardown( tester, h );
    } );
  } );
}
