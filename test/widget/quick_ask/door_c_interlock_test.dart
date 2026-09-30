/// AC-S4.6 — the Door C interlock.
///
/// 🔴 Door C is the near-match confirm (`rest/v2/flow.py` `_near_match_replay`
/// / `_user_confirms`): when a question scores close to a cached one, the flow
/// sends a yes/no `response_requested` notification and BLOCKS the ask's own
/// HTTP thread waiting for the answer — 30s minimum, ~210s worst case. So the
/// question arrives WHILE our ask is in flight, and our ask is what it is
/// holding up. The prompt defaults to **"no"**, and a confirmer that raises
/// counts as a no.
///
/// Before this, the phone recorded the notification's id, disabled the record
/// button on it, and never showed the question — so the confirm always ran out
/// to "no" and the user saw an unexplained pause. That is the regression this
/// file exists to catch.
///
/// 🔴 REAL bloc, REAL screen. A `MockBloc` version could not discriminate by
/// construction: the interlock IS the wiring between the arriving frame, the
/// rendered surface, the notification door, and the ask state left alone.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/notifications/data/notification_models.dart';
import 'package:lupin_mobile/features/notifications/data/notification_repository.dart';
import 'package:lupin_mobile/features/queue/data/queue_models.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_bloc.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_event.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_state.dart';
import 'package:lupin_mobile/features/quick_ask/presentation/quick_ask_screen.dart';
import 'package:lupin_mobile/services/tts/tts_orchestrator.dart';

import '../../unit/quick_ask/_quick_ask_harness.dart';

class MockTtsOrchestrator extends Mock implements TtsOrchestrator {}

/// The Door C confirm, in the shape the server actually sends it:
/// `response_requested` + `response_type: yes_no` + `response_default: no`.
NotificationItem doorCConfirm( { String id = 'confirm-1' } ) => notif(
  id                : id,
  message           : 'Is that the same as: what is the weather in Washington?',
  responseRequested : true,
  responseType      : 'yes_no',
  responseDefault   : 'no',
);

void main() {
  setUpAll( () {
    registerFallbackValue( const AskRequest( question: 'x' ) );
    registerFallbackValue( const NotificationResponsePayload(
      notificationId: 'x', responseValue: 'x' ) );
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

  /// Puts an ask genuinely IN FLIGHT: the `ask` call never completes, exactly
  /// as it does not while the server sits inside `_user_confirms`. Returns the
  /// completer so a test can land the answer afterwards if it wants to.
  Completer<AskResponse> armBlockedAsk( Harness h ) {
    final gate = Completer<AskResponse>();
    when( () => h.repo.ask( any() ) ).thenAnswer( ( _ ) => gate.future );
    when( () => h.asr.stopAndTranscribe() )
        .thenAnswer( ( _ ) async => 'what is the weather in DC' );
    h.stubEmptyQueues();
    return gate;
  }

  /// 🔴 NOT the harness's `settle()`. Inside `testWidgets` the clock is FAKE,
  /// so a bare `Future.delayed( Duration.zero )` never fires — the file HANGS
  /// rather than failing, which is worse than a red. Pumping is how time moves
  /// here. (Measured: this hung the whole quick_ask run at +77.)
  Future<void> drain( WidgetTester tester, [ int rounds = 8 ] ) async {
    for ( var i = 0; i < rounds; i++ ) {
      await tester.pump( Duration.zero );
    }
  }

  /// 🔴 `dispose()` must run in the REAL async zone. `Bloc.close()` cancels a
  /// subscription to the harness's `async*` connection stream, and under
  /// `testWidgets`' FAKE clock that await never completes — the test HANGS
  /// rather than failing. Measured: a bare `Harness()` + `dispose()` hangs on
  /// its own, with no Door C code involved at all.
  Future<void> teardown( WidgetTester tester, Harness h ) =>
      tester.runAsync( () => h.dispose() );

  /// 🔴 REQUIRED before `dispose()`. `Bloc.close()` AWAITS every in-progress
  /// event handler, and `_onRecordReleased` is parked on the ask that Door C
  /// is blocking — so a test that just disposes HANGS instead of failing.
  Future<void> release( WidgetTester tester, Completer<AskResponse> gate ) async {
    if ( !gate.isCompleted ) gate.complete( waitingAsk() );
    await drain( tester );
  }

  Future<void> startBlockedAsk( WidgetTester tester, Harness h ) async {
    h.bloc.add( const QuickAskRecordPressed() );
    await tester.pump();
    h.bloc.add( const QuickAskRecordReleased() );
    await tester.pump();
    h.bloc.add( const QuickAskDraftSent() );
    await tester.pump();
  }

  group( 'AC-S4.6 — a confirm arriving mid-ask is ANSWERABLE', () {

    testWidgets( 'the question is RENDERED while the ask is still in flight', ( tester ) async {
      final h = Harness();
      final gate = armBlockedAsk( h );
      await tester.pumpWidget( host( h.bloc ) );
      await startBlockedAsk( tester, h );

      // The ask is genuinely blocked — this is the window Door C lands in.
      expect( h.bloc.state.phase, QuickAskPhase.submitting );

      h.bloc.add( QuickAskNotificationReceived( doorCConfirm() ) );
      await tester.pump();

      // 🔴 The question itself, not just a disabled button. Recording the id
      // and showing nothing is the defect: the user is blocked BY a question
      // they were never shown.
      expect( find.byKey( const Key( TestKeys.quickAskPrompt ) ), findsOneWidget );
      expect(
        tester.widget<Text>( find.byKey( const Key( TestKeys.quickAskPromptQuestion ) ) ).data,
        contains( 'Is that the same as' ),
      );
      // And it is answerable: the shared yes/no body is live.
      expect( find.byKey( const Key( TestKeys.promptYesButton ) ), findsOneWidget );

      await release( tester, gate );
      await teardown( tester, h );
    } );

    testWidgets( 'YES reaches the notification door — the confirm does NOT default to no',
        ( tester ) async {
      final h = Harness();
      final gate = armBlockedAsk( h );
      await tester.pumpWidget( host( h.bloc ) );
      await startBlockedAsk( tester, h );

      h.bloc.add( QuickAskNotificationReceived( doorCConfirm() ) );
      await tester.pump();

      await tester.tap( find.byKey( const Key( TestKeys.promptYesButton ) ) );
      await drain( tester );

      final captured = verify( () => h.notifications.respond( captureAny() ) )
          .captured.single as NotificationResponsePayload;
      expect( captured.notificationId, 'confirm-1' );
      // 🔴 The whole point. "no" here means the user's yes never left the
      // phone and the near-match replay is discarded.
      expect( captured.responseValue, 'yes' );

      // Answered ⇒ the surface retires, so it cannot block the next question.
      await tester.pump();
      expect( find.byKey( const Key( TestKeys.quickAskPrompt ) ), findsNothing );
      expect( h.bloc.state.pendingPrompt, isNull );

      await release( tester, gate );
      await teardown( tester, h );
    } );

    testWidgets( 'the ask is left UNDISTURBED — no phase, entry or job-id change',
        ( tester ) async {
      final h = Harness();
      final gate = armBlockedAsk( h );
      await tester.pumpWidget( host( h.bloc ) );
      await startBlockedAsk( tester, h );

      final before = h.bloc.state;
      expect( before.phase,        QuickAskPhase.submitting );
      expect( before.liveQuestion, 'what is the weather in DC' );

      h.bloc.add( QuickAskNotificationReceived( doorCConfirm() ) );
      await tester.pump();
      await tester.tap( find.byKey( const Key( TestKeys.promptYesButton ) ) );
      await drain( tester );

      // 🔴 The interlock: answering the OTHER door moved nothing that belongs
      // to the ask. A handler that emitted `phase: idle` "to unblock the UI"
      // would strand the in-flight call and lose the answer when it lands.
      final after = h.bloc.state;
      expect( after.phase,        QuickAskPhase.submitting );
      expect( after.liveQuestion, before.liveQuestion );
      expect( after.liveJobId,    before.liveJobId );
      expect( after.entries,      before.entries );
      expect( after.errorMessage, isNull );
      expect( after.lost,         isFalse );

      // And the released ask still lands normally afterwards.
      await release( tester, gate );
      expect( h.bloc.state.liveJobId, ourJob );
      expect( h.bloc.state.phase,     QuickAskPhase.waiting );

      await teardown( tester, h );
    } );
  } );

  group( 'AC-S4.6 — the default is "no", and it is STATED rather than timed out', () {

    testWidgets( 'dismissing POSTS the server\'s own response_default', ( tester ) async {
      final h = Harness();
      final gate = armBlockedAsk( h );
      await tester.pumpWidget( host( h.bloc ) );
      await startBlockedAsk( tester, h );

      h.bloc.add( QuickAskNotificationReceived( doorCConfirm() ) );
      await tester.pump();

      await tester.tap( find.byKey( const Key( TestKeys.quickAskPromptDismiss ) ) );
      await drain( tester );

      // A LOCAL hide would send nothing and leave the server burning its
      // ~210s retry ladder before defaulting anyway.
      final captured = verify( () => h.notifications.respond( captureAny() ) )
          .captured.single as NotificationResponsePayload;
      expect( captured.responseValue, 'no' );
      expect( h.bloc.state.pendingPrompt, isNull );
      expect( h.bloc.state.phase, QuickAskPhase.submitting );

      await release( tester, gate );
      await teardown( tester, h );
    } );

    test( 'a yes/no confirm with NO response_default still defaults to "no"', () {
      const p = QuickAskPrompt( id: 'c', question: 'same?', responseType: 'yes_no' );
      // Not a preference — `_user_confirms` treats a timeout AND a raise as a
      // no, because a wrong replay is worse than a re-run.
      expect( p.defaultAnswer, 'no' );
    } );
  } );

  group( 'AC-S4.6 — a door that answers badly must not strand the surface', () {

    testWidgets( 'an "already responded" 400 RETIRES the prompt (AC-S4.9 vocabulary)',
        ( tester ) async {
      final h = Harness();
      final gate = armBlockedAsk( h );
      when( () => h.notifications.respond( any() ) ).thenThrow(
        const NotificationApiException( 'Notification already responded', statusCode: 400 ) );
      await tester.pumpWidget( host( h.bloc ) );
      await startBlockedAsk( tester, h );

      h.bloc.add( QuickAskNotificationReceived( doorCConfirm() ) );
      await tester.pump();
      await tester.tap( find.byKey( const Key( TestKeys.promptYesButton ) ) );
      await drain( tester );

      // Another device answered. Holding the prompt open would block the
      // record button forever on a question that is already finished.
      expect( h.bloc.state.pendingPrompt, isNull );
      expect( h.bloc.state.errorMessage,  isNull );
      await release( tester, gate );
      await teardown( tester, h );
    } );

    testWidgets( 'a GENUINE failure keeps the prompt so it can be retried', ( tester ) async {
      final h = Harness();
      final gate = armBlockedAsk( h );
      when( () => h.notifications.respond( any() ) ).thenThrow(
        const NotificationApiException( 'Connection refused', statusCode: 500 ) );
      await tester.pumpWidget( host( h.bloc ) );
      await startBlockedAsk( tester, h );

      h.bloc.add( QuickAskNotificationReceived( doorCConfirm() ) );
      await tester.pump();
      await tester.tap( find.byKey( const Key( TestKeys.promptYesButton ) ) );
      await drain( tester );

      expect( h.bloc.state.pendingPrompt, isNotNull );
      expect( h.bloc.state.errorMessage,  contains( 'Connection refused' ) );
      // Still undisturbed.
      expect( h.bloc.state.phase, QuickAskPhase.submitting );
      await release( tester, gate );
      await teardown( tester, h );
    } );
  } );
}

