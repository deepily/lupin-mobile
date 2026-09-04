/// Bug 1829eb26 — a progress notification is NOT the answer.
///
/// The belt channel exists for the case where the completion FRAME goes
/// missing and a notification's `message` genuinely IS the answer. It guarded
/// only on `jobId`, never on `type`, so that premise silently extended to
/// every notification the live job emitted. On a long-running job the FIRST
/// milestone marked the card completed, rendered the milestone text where the
/// answer belongs, cleared `liveJobId` and cancelled the watchdog — and the
/// real answer, arriving minutes later, was then dropped by the very
/// `jobId != live` test one line above. Silent, and it produced a WRONG
/// answer rather than an error.
///
/// THE FALSIFIER for this whole file is the last test: progress, THEN the
/// real answer, and the answer must win. A bloc that still completes on
/// progress passes several assertions here and fails that one.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/features/queue/data/queue_models.dart';
import 'package:lupin_mobile/features/queue/domain/job_lifecycle.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_event.dart';

import '_quick_ask_harness.dart';

void main() {
  setUpAll( () { registerFallbackValue( const AskRequest( question: 'x' ) ); } );

  /// A question submitted and in flight — `liveJobId` set, card not terminal.
  Future<Harness> liveCard() async {
    final h = Harness();
    h.stubEmptyQueues();
    when( () => h.asr.stopAndTranscribe() ).thenAnswer( ( _ ) async => 'what is the weather' );
    when( () => h.repo.ask( any() ) ).thenAnswer( ( _ ) async => waitingAsk() );
    when( () => h.repo.cancelJob( any() ) ).thenAnswer( ( _ ) async {} );
    await settle();

    h.bloc.add( const QuickAskRecordPressed() );
    await settle();
    h.bloc.add( const QuickAskRecordReleased() );
    await settle();
    h.bloc.add( const QuickAskDraftSent() );
    await settle();
    return h;
  }

  group( 'a progress notification does not end the card', () {

    test( 'the card stays live and is NOT marked completed', () async {
      final h = await liveCard();
      expect( h.bloc.state.liveJobId, ourJob, reason: 'setup failed — nothing in flight' );

      h.bloc.add( QuickAskNotificationReceived(
        notif( id: 'p-1', type: 'progress', message: 'Fetching sources…', jobId: ourJob ) ) );
      await settle();

      final entry = h.bloc.state.liveEntry;
      expect( entry, isNotNull, reason: 'the card was removed by a progress frame' );
      expect( entry!.state, isNot( JobLifecycleState.completed ) );
      expect( entry.isTerminal, isFalse );
      // The card must still be OWNED by the live job — this is what used to be
      // cleared, and clearing it is what made the real answer undeliverable.
      expect( h.bloc.state.liveJobId, ourJob );
    } );

    test( 'the milestone is stored as progress, never as the answer', () async {
      final h = await liveCard();

      h.bloc.add( QuickAskNotificationReceived(
        notif( id: 'p-1', type: 'progress', message: 'Fetching sources…', jobId: ourJob ) ) );
      await settle();

      final entry = h.bloc.state.liveEntry!;
      expect( entry.progressText, 'Fetching sources…' );
      // 🔴 The heart of the bug: this text must never reach the answer slot.
      expect( entry.hasAnswer, isFalse );
      expect( entry.answer,    isNot( 'Fetching sources…' ) );
    } );

    test( 'a later milestone replaces the earlier one', () async {
      final h = await liveCard();

      h.bloc.add( QuickAskNotificationReceived(
        notif( id: 'p-1', type: 'progress', message: 'Fetching sources…', jobId: ourJob ) ) );
      await settle();
      h.bloc.add( QuickAskNotificationReceived(
        notif( id: 'p-2', type: 'progress', message: 'Summarising…', jobId: ourJob ) ) );
      await settle();

      expect( h.bloc.state.liveEntry!.progressText, 'Summarising…' );
      expect( h.bloc.state.liveEntry!.hasAnswer,    isFalse );
    } );

    test( 'progress for a DIFFERENT job is ignored', () async {
      final h = await liveCard();

      h.bloc.add( QuickAskNotificationReceived(
        notif( id: 'p-x', type: 'progress', message: 'not ours', jobId: 'some-other-job' ) ) );
      await settle();

      expect( h.bloc.state.liveEntry!.progressText, isNull );
    } );
  } );

  group( 'the belt channel still works for a real answer', () {

    test( 'a task-type notification completes the card as before', () async {
      final h = await liveCard();

      h.bloc.add( QuickAskNotificationReceived(
        notif( id: 'a-1', message: '72 and sunny', jobId: ourJob ) ) );
      await settle();

      final entry = h.bloc.state.entries.first;
      expect( entry.state,     JobLifecycleState.completed );
      expect( entry.answer,    '72 and sunny' );
      expect( entry.hasAnswer, isTrue );
    } );

    test( '🔴 THE FALSIFIER — progress first, then the real answer 15 minutes later',
        () async {
      final h = await liveCard();

      // Three milestones, exactly the shape that used to end the card on the
      // first one and make everything after it undeliverable.
      for ( final m in [ 'Fetching sources…', 'Reading…', 'Summarising…' ] ) {
        h.bloc.add( QuickAskNotificationReceived(
          notif( id: 'p-$m', type: 'progress', message: m, jobId: ourJob ) ) );
        await settle();
      }
      expect( h.bloc.state.liveJobId, ourJob,
              reason: 'the job was released before its answer arrived' );

      // The answer the user actually asked for.
      h.bloc.add( QuickAskNotificationReceived(
        notif( id: 'a-1', message: '72 and sunny', jobId: ourJob ) ) );
      await settle();

      final entry = h.bloc.state.entries.first;
      expect( entry.answer,    '72 and sunny',
              reason: 'the real answer was dropped — the exact user-visible defect' );
      expect( entry.state,     JobLifecycleState.completed );
      expect( entry.hasAnswer, isTrue );
    } );
  } );
}
