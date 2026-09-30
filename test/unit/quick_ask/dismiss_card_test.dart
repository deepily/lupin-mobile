/// The X on a question card, against a REAL bloc.
///
/// 🔴 The falsifier for this file is `verify( repo.cancelJob )` on a RUNNING
/// card and `verifyNever` on a finished one. A dismiss that only hides the card
/// passes every "the card is gone" assertion while leaving the job running, the
/// record button blocked, and an answer still on its way to the speaker.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/features/queue/data/queue_models.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_event.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_state.dart';

import '_quick_ask_harness.dart';

void main() {
  setUpAll( () { registerFallbackValue( const AskRequest( question: 'x' ) ); } );

  /// Records, sends, and leaves ONE live (non-terminal) card in flight.
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

  group( 'dismissing a card whose job is STILL RUNNING', () {

    test( 'cancels the job server-side, not just locally', () async {
      final h = await liveCard();
      expect( h.bloc.state.liveJobId, ourJob, reason: 'setup failed — nothing in flight' );

      h.bloc.add( const QuickAskEntryDismissed( ourJob ) );
      await settle();

      // THE falsifier. A local-only hide passes everything below this line.
      verify( () => h.repo.cancelJob( ourJob ) ).called( 1 );

      await h.dispose();
    } );

    test( 'removes the card and frees the record button', () async {
      final h = await liveCard();

      h.bloc.add( const QuickAskEntryDismissed( ourJob ) );
      await settle();

      expect( h.bloc.state.entries,   isEmpty );
      expect( h.bloc.state.liveJobId, isNull );
      expect( h.bloc.state.phase,     QuickAskPhase.idle );
      expect( h.bloc.state.canRecord, isTrue,
          reason: 'a dismissed question must not go on blocking the button' );

      await h.dispose();
    } );

    test( 'a late frame for the dismissed job does NOT resurrect the card', () async {
      final h = await liveCard();

      h.bloc.add( const QuickAskEntryDismissed( ourJob ) );
      await settle();

      // The server had already sent this when the user tapped X.
      h.bloc.add( QuickAskTransitionReceived(
          transitionFrame( from: 'running', to: 'completed' ) ) );
      await settle();

      expect( h.bloc.state.entries, isEmpty,
          reason: 'a card the user deliberately removed must stay removed' );

      await h.dispose();
    } );

    test( 'a failed cancel keeps the card and says so', () async {
      final h = await liveCard();
      when( () => h.repo.cancelJob( any() ) )
          .thenThrow( const QueueApiException( 'server said no' ) );

      h.bloc.add( const QuickAskEntryDismissed( ourJob ) );
      await settle();

      expect( h.bloc.state.entries,      isNotEmpty,
          reason: 'telling the user it is gone while the job runs on is the lie' );
      expect( h.bloc.state.errorMessage, isNotNull );

      await h.dispose();
    } );
  } );

  group( 'dismissing a FINISHED card', () {

    test( 'removes it without calling cancel — there is nothing to cancel', () async {
      final h = await liveCard();
      h.bloc.add( QuickAskTransitionReceived(
          transitionFrame( from: 'running', to: 'completed' ) ) );
      await settle();
      expect( h.bloc.state.entries.single.isTerminal, isTrue, reason: 'setup failed' );

      h.bloc.add( const QuickAskEntryDismissed( ourJob ) );
      await settle();

      expect( h.bloc.state.entries, isEmpty );
      verifyNever( () => h.repo.cancelJob( any() ) );

      await h.dispose();
    } );
  } );

  group( 'dismissing the WRONG card leaves the others alone', () {

    test( 'an unknown job id is a no-op', () async {
      final h = await liveCard();

      h.bloc.add( const QuickAskEntryDismissed( 'not-a-real-job' ) );
      await settle();

      expect( h.bloc.state.entries,   isNotEmpty );
      expect( h.bloc.state.liveJobId, ourJob,
          reason: 'a miss must not clear the live question' );
      verifyNever( () => h.repo.cancelJob( any() ) );

      await h.dispose();
    } );
  } );
}
