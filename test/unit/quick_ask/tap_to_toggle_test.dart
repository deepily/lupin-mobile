/// Tap-to-toggle capture and the stop-and-hold step, against a REAL bloc.
///
/// 🔴 The defect this replaces: the record button was a hold, and letting go
/// submitted. A user who stumbled mid-sentence broke the press and the
/// half-finished question went to the server on its own. Stopping now only
/// parks the transcript; `QuickAskDraftSent` is the only thing that submits.
///
/// The falsifier for the whole file is `verifyNever( repo.ask )` after a stop:
/// a bloc that still auto-submits passes every OTHER assertion here.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/features/queue/data/queue_models.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_event.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_state.dart';

import '_quick_ask_harness.dart';

void main() {
  setUpAll( () { registerFallbackValue( const AskRequest( question: 'x' ) ); } );

  /// Records and stops — the two taps — leaving a held draft behind.
  Future<Harness> recordAndStop( { String transcript = 'what is the weather' } ) async {
    final h = Harness();
    h.stubEmptyQueues();
    when( () => h.asr.stopAndTranscribe() ).thenAnswer( ( _ ) async => transcript );
    when( () => h.repo.ask( any() ) ).thenAnswer( ( _ ) async => waitingAsk() );
    await settle();

    h.bloc.add( const QuickAskRecordPressed() );
    await settle();
    h.bloc.add( const QuickAskRecordReleased() );
    await settle();
    return h;
  }

  group( 'the second tap STOPS but does not send', () {

    test( 'stopping parks the transcript in review and submits NOTHING', () async {
      final h = await recordAndStop();

      expect( h.bloc.state.phase,           QuickAskPhase.review );
      expect( h.bloc.state.draftTranscript, 'what is the weather' );
      expect( h.bloc.state.hasDraft,        isTrue );
      // THE falsifier. Under the old button this call had already happened.
      verifyNever( () => h.repo.ask( any() ) );
      expect( h.bloc.state.liveJobId, isNull );

      await h.dispose();
    } );

    test( 'the microphone goes inert while a draft is held', () async {
      final h = await recordAndStop();

      // Nothing is blocking in the four-clause sense — the draft alone is what
      // takes the button out of service, so no misleading reason is shown.
      expect( h.bloc.state.canRecord,      isFalse );
      expect( h.bloc.state.blockReason,    isNull );
      expect( h.bloc.state.blockedMessage, isNull );

      // And a stray tap on the mic cannot start over on top of the draft.
      h.bloc.add( const QuickAskRecordPressed() );
      await settle();
      expect( h.bloc.state.phase,           QuickAskPhase.review );
      expect( h.bloc.state.draftTranscript, 'what is the weather' );

      await h.dispose();
    } );

    test( 'a blank transcript is refused rather than held as a sendable draft', () async {
      final h = await recordAndStop( transcript: '   ' );

      expect( h.bloc.state.phase,     QuickAskPhase.idle );
      expect( h.bloc.state.hasDraft,  isFalse );
      expect( h.bloc.state.errorMessage, isNotNull );
      verifyNever( () => h.repo.ask( any() ) );

      await h.dispose();
    } );
  } );

  group( 'the send button is the only route to the server', () {

    test( 'sending submits the held transcript and clears the holding pen', () async {
      final h = await recordAndStop();

      h.bloc.add( const QuickAskDraftSent() );
      await settle();

      final sent = verify( () => h.repo.ask( captureAny() ) ).captured.single as AskRequest;
      expect( sent.question, 'what is the weather' );
      expect( h.bloc.state.liveQuestion, 'what is the weather' );
      expect( h.bloc.state.hasDraft,     isFalse,
          reason: 'a draft left behind would offer a second send of the same question' );

      await h.dispose();
    } );

    test( 'send with no draft is a no-op — nothing reaches the server', () async {
      final h = Harness();
      h.stubEmptyQueues();
      when( () => h.repo.ask( any() ) ).thenAnswer( ( _ ) async => waitingAsk() );
      await settle();

      h.bloc.add( const QuickAskDraftSent() );
      await settle();

      verifyNever( () => h.repo.ask( any() ) );
      expect( h.bloc.state.phase, QuickAskPhase.idle );

      await h.dispose();
    } );
  } );

  group( 'the clear button throws the draft away', () {

    test( 'clearing returns to idle with nothing sent and the mic live again', () async {
      final h = await recordAndStop();

      h.bloc.add( const QuickAskDraftCleared() );
      await settle();

      expect( h.bloc.state.phase,     QuickAskPhase.idle );
      expect( h.bloc.state.hasDraft,  isFalse );
      expect( h.bloc.state.canRecord, isTrue );
      verifyNever( () => h.repo.ask( any() ) );

      await h.dispose();
    } );

    test( 'a cleared draft cannot be sent afterwards', () async {
      final h = await recordAndStop();

      h.bloc.add( const QuickAskDraftCleared() );
      await settle();
      h.bloc.add( const QuickAskDraftSent() );
      await settle();

      verifyNever( () => h.repo.ask( any() ) );

      await h.dispose();
    } );

    test( 'after clearing, a fresh capture runs normally', () async {
      final h = await recordAndStop();

      h.bloc.add( const QuickAskDraftCleared() );
      await settle();

      when( () => h.asr.stopAndTranscribe() ).thenAnswer( ( _ ) async => 'second question' );
      h.bloc.add( const QuickAskRecordPressed() );
      await settle();
      h.bloc.add( const QuickAskRecordReleased() );
      await settle();

      expect( h.bloc.state.phase,           QuickAskPhase.review );
      expect( h.bloc.state.draftTranscript, 'second question' );

      await h.dispose();
    } );
  } );
}
