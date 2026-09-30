/// The progress status line on a live Quick Ask card (bug 1829eb26).
///
/// Rick's ruling: a long-running job's milestone is SHOWN, so a 15-minute job
/// visibly breathes — but as a status line, never in the answer's slot and
/// never styled like one. These are rendering assertions with a mocked bloc;
/// whether progress actually stops ending the card is driven against a REAL
/// bloc in `test/unit/quick_ask/progress_not_answer_test.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:get_it/get_it.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/queue/data/queue_models.dart';
import 'package:lupin_mobile/features/queue/domain/job_lifecycle.dart';
import 'package:lupin_mobile/features/quick_ask/data/quick_ask_models.dart';
import 'package:lupin_mobile/services/tts/tts_orchestrator.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_bloc.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_event.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_state.dart';
import 'package:lupin_mobile/features/quick_ask/presentation/quick_ask_screen.dart';

class MockQuickAskBloc extends MockBloc<QuickAskEvent, QuickAskState>
    implements QuickAskBloc {}

class MockTtsOrchestrator extends Mock implements TtsOrchestrator {}

void main() {
  late MockTtsOrchestrator tts;

  setUpAll( () {
    registerFallbackValue( const QuickAskRecordPressed() );
    registerFallbackValue( const TtsSender() );
  } );

  setUp( () {
    tts = MockTtsOrchestrator();
    when( () => tts.isPaused ).thenReturn( false );
    when( () => tts.pausedStream ).thenAnswer( ( _ ) => const Stream<bool>.empty() );
    when( () => tts.queueDepth ).thenReturn( 0 );
    when( () => tts.queueDepthStream ).thenAnswer( ( _ ) => const Stream<int>.empty() );
    GetIt.instance.registerSingleton<TtsOrchestrator>( tts );
  } );

  tearDown( () async { await GetIt.instance.reset(); } );

  Future<void> pump( WidgetTester tester, QuickAskState state ) async {
    final b = MockQuickAskBloc();
    whenListen( b, Stream<QuickAskState>.fromIterable( const [] ), initialState: state );
    await tester.pumpWidget( MaterialApp(
      home: BlocProvider<QuickAskBloc>.value( value: b, child: const QuickAskScreen() ),
    ) );
    await tester.pump();
  }

  const jobId = 'job-ours';

  QuickAskState withEntry( QuickAskEntry e ) =>
      QuickAskState( connected: true, entries: [ e ] );

  QuickAskEntry running( { String? progressText, String? answer } ) => QuickAskEntry(
    questionText : 'what is the weather',
    state        : answer == null ? JobLifecycleState.running : JobLifecycleState.completed,
    source       : QuickAskSource.transition,
    jobId        : jobId,
    progressText : progressText,
    details      : answer == null ? null : JobSummary(
      jobId        : jobId,
      questionText : 'what is the weather',
      status       : 'completed',
      responseText : answer,
    ),
  );

  Finder progress() => find.byKey( const Key( '${TestKeys.quickAskProgressPrefix}$jobId' ) );
  Finder answer()   => find.byKey( const Key( '${TestKeys.quickAskAnswerPrefix}$jobId' ) );

  group( 'the status line', () {

    testWidgets( 'renders the milestone text on a running card', ( tester ) async {
      await pump( tester, withEntry( running( progressText: 'Fetching sources…' ) ) );

      expect( progress(), findsOneWidget );
      expect( find.text( 'Fetching sources…' ), findsOneWidget );
    } );

    testWidgets( 'shows a spinner beside it, so the job reads as ALIVE', ( tester ) async {
      await pump( tester, withEntry( running( progressText: 'Fetching sources…' ) ) );

      expect( find.byType( CircularProgressIndicator ), findsOneWidget );
    } );

    testWidgets( 'is absent when no milestone has arrived', ( tester ) async {
      await pump( tester, withEntry( running() ) );

      expect( progress(), findsNothing );
    } );

    testWidgets( 'is NOT rendered in the answer slot', ( tester ) async {
      await pump( tester, withEntry( running( progressText: 'Fetching sources…' ) ) );

      // 🔴 The rendering half of the bug: the milestone must never occupy the
      // place a user reads as their answer.
      expect( answer(), findsNothing );
    } );

    testWidgets( '🔴 the real answer OUTRANKS a stale milestone', ( tester ) async {
      await pump( tester, withEntry(
        running( progressText: 'Summarising…', answer: '72 and sunny' ) ) );

      expect( answer(),   findsOneWidget );
      expect( find.text( '72 and sunny' ), findsOneWidget );
      // The status line must yield the moment there is a real result — the
      // two must never be on screen together competing to be read.
      expect( progress(), findsNothing );
      expect( find.text( 'Summarising…' ), findsNothing );
    } );
  } );
}
