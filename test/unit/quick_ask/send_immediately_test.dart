/// Plan §3.3 / §3.4, the C rows — send immediately, driven through a REAL
/// `QuickAskBloc`.
///
/// 🔴 ONE `StreamController` PER `askSpoken` CALL (C-J2). A single shared
/// controller is single-subscription, so the second listen throws
/// `StateError` and the two-stream rows fail for a reason unrelated to the
/// behaviour. And `hasListener` is never the assertion for "still reading":
/// it stays true under the broken one-handle shape too, because a Dart
/// subscription survives losing its reference. The handle is asserted
/// through `liveSpokenEpochs` instead.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/features/queue/data/queue_models.dart';
import 'package:lupin_mobile/features/queue/domain/job_lifecycle.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_bloc.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_event.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_state.dart';
import 'package:lupin_mobile/services/asr/asr_service.dart';

import '_quick_ask_harness.dart';

/// The first recording's path. Every `stopToFile` call hands out a DISTINCT
/// path (`recordingPathFor( n )`), so a disposal aimed at the wrong stream's
/// file is visible (rev-15 ruling C2-A).
const recordingPath = '/tmp/quick-ask-test-0.m4a';
String recordingPathFor( int n ) => '/tmp/quick-ask-test-$n.m4a';
const spokenText    = 'what is the weather';

/// Wires `askSpoken` to a fresh controller per call, and records each one.
class SpokenStubs {
  final Harness h;
  final List<StreamController<SpokenAskEvent>> streams = [];
  final List<bool> cancelled = [];
  int stops = 0;

  SpokenStubs( this.h ) {
    when( () => h.asr.stopToFile() ).thenAnswer( ( _ ) async => recordingPathFor( stops++ ) );
    when( () => h.asr.stopAndTranscribe() ).thenAnswer( ( _ ) async => spokenText );
    when( () => h.repo.cancelJob( any() ) ).thenAnswer( ( _ ) async {} );
    when( () => h.repo.askSpoken( any(), any() ) ).thenAnswer( ( _ ) {
      final i    = streams.length;
      cancelled.add( false );
      final ctrl = StreamController<SpokenAskEvent>( onCancel: () => cancelled[ i ] = true );
      streams.add( ctrl );
      return ctrl.stream;
    } );
  }

  StreamController<SpokenAskEvent> get last => streams.last;
}

/// Record, release, and let the subscribe land.
Future<void> speak( Harness h ) async {
  h.bloc.add( const QuickAskRecordPressed() );
  await settle();
  h.bloc.add( const QuickAskRecordReleased() );
  await settle();
}

Future<void> push( StreamController<SpokenAskEvent> c, SpokenAskEvent ev ) async {
  c.add( ev );
  await settle();
}

SpokenAskResult resultFor( { String? jobId = ourJob, String status = 'waiting', String? pendingId,
                             String? answer, List<String> argsMissing = const [] } ) =>
    SpokenAskResult( AskResponse(
      path        : 'agent',
      status      : status,
      routeReason : 'args_complete',
      traceId     : 'tr-spoken',
      jobId       : jobId,
      pendingId   : pendingId,
      answer      : answer,
      argsMissing : argsMissing,
    ) );

void main() {
  late Harness     h;
  late SpokenStubs s;
  late List<QuickAskState> seen;
  late StreamSubscription<QuickAskState> tap;

  // `verifyNever( () => repo.ask( any() ) )` needs a fallback for the type.
  setUpAll( () => registerFallbackValue( const AskRequest( question: '_fallback' ) ) );

  setUp( () {
    h    = Harness( sendImmediately: true );
    s    = SpokenStubs( h );
    seen = [];
    tap  = h.bloc.stream.listen( seen.add );
  } );

  tearDown( () async {
    await tap.cancel();
    await h.dispose();
  } );

  group( 'send immediately — the happy path', () {

    test( 'no review phase · repo.ask never called · liveJobId comes from the Result', () async {
      await speak( h );
      verify( () => h.repo.askSpoken( recordingPath, ourSession ) ).called( 1 );

      await push( s.last, const SpokenAskTranscript( spokenText ) );
      expect( h.bloc.state.liveQuestion, spokenText );
      expect( h.bloc.state.phase, QuickAskPhase.submitting );

      await push( s.last, resultFor() );

      expect( seen.map( ( x ) => x.phase ), isNot( contains( QuickAskPhase.review ) ) );
      expect( seen.any( ( x ) => x.draftTranscript != null ), isFalse );
      verifyNever( () => h.repo.ask( any() ) );
      verifyNever( () => h.asr.stopAndTranscribe() );

      expect( h.bloc.state.liveJobId, ourJob );
      expect( h.bloc.state.phase, QuickAskPhase.waiting );
      expect( h.bloc.state.entries.single.jobId, ourJob );
      expect( h.bloc.state.entries.single.questionText, spokenText );
    } );
  } );

  group( 'review first is unchanged', () {

    test( 'a release in review-first mode never touches the spoken door', () async {
      final r = Harness();                      // default: review first
      SpokenStubs( r );
      addTearDown( r.dispose );
      await settle();                           // let the connection replay land first

      await speak( r );

      verify( () => r.asr.stopAndTranscribe() ).called( 1 );
      verifyNever( () => r.asr.stopToFile() );
      verifyNever( () => r.repo.askSpoken( any(), any() ) );
      expect( r.bloc.state.phase, QuickAskPhase.review );
      expect( r.bloc.state.draftTranscript, spokenText );
    } );
  } );

  group( 'C-J1 — the preference is read at RELEASE time', () {

    test( 'flipped to send immediately AFTER construction, the next release uses the spoken door', () async {
      final r = Harness();                      // constructed review-first
      SpokenStubs( r );
      addTearDown( r.dispose );
      await settle();                           // let the connection replay land first

      r.prefs.stored = true;                    // a flip made outside the bloc
      await speak( r );

      verify( () => r.repo.askSpoken( recordingPath, ourSession ) ).called( 1 );
      verifyNever( () => r.asr.stopAndTranscribe() );
    } );

    test( 'and flipped back to review first, the next release holds a draft again', () async {
      h.prefs.stored = false;
      await speak( h );

      verify( () => h.asr.stopAndTranscribe() ).called( 1 );
      verifyNever( () => h.repo.askSpoken( any(), any() ) );
      expect( h.bloc.state.phase, QuickAskPhase.review );
    } );
  } );

  group( "cancel before the job id — Rick's ruling 3", () {

    test( 'cancel after the Transcript, before the Result → cancelJob( id ), no card', () async {
      await speak( h );
      await push( s.last, const SpokenAskTranscript( spokenText ) );

      h.bloc.add( const QuickAskRecordCancelled() );
      await settle();
      expect( h.bloc.state.phase, QuickAskPhase.idle );

      await push( s.last, resultFor() );

      verify( () => h.repo.cancelJob( ourJob ) ).called( 1 );
      expect( h.bloc.state.entries, isEmpty );
      expect( h.bloc.state.liveJobId, isNull );
      expect( h.bloc.state.phase, QuickAskPhase.idle );
    } );

    test( "cancel before the Transcript → no card, and cancelJob on the Result's id", () async {
      await speak( h );

      h.bloc.add( const QuickAskRecordCancelled() );
      await settle();

      await push( s.last, const SpokenAskTranscript( spokenText ) );
      expect( h.bloc.state.liveQuestion, isNull, reason: 'a stale transcript is dropped' );

      await push( s.last, resultFor( jobId: 'job-late' ) );

      verify( () => h.repo.cancelJob( 'job-late' ) ).called( 1 );
      expect( h.bloc.state.entries, isEmpty );
      expect( h.bloc.state.liveJobId, isNull );
    } );

    test( 'a stale Result WITHOUT a job id → no cancel call', () async {
      await speak( h );
      h.bloc.add( const QuickAskRecordCancelled() );
      await settle();

      await push( s.last, const SpokenAskTranscript( spokenText ) );
      await push( s.last, resultFor( jobId: null, status: 'parked', pendingId: 'p-1', answer: 'Which city?' ) );

      verifyNever( () => h.repo.cancelJob( any() ) );
      expect( h.bloc.state.entries, isEmpty );
      expect( h.bloc.state.interview, isNull );
    } );

    test( "a new press while a stream is live cancels the previous question's job on arrival", () async {
      await speak( h );
      final first = s.last;
      await push( first, const SpokenAskTranscript( 'first question' ) );

      h.bloc.add( const QuickAskRecordCancelled() );
      await settle();
      await speak( h );                         // the second press is allowed
      final second = s.last;
      expect( identical( first, second ), isFalse );

      await push( second, const SpokenAskTranscript( 'second question' ) );
      await push( first, resultFor( jobId: 'job-first' ) );

      verify( () => h.repo.cancelJob( 'job-first' ) ).called( 1 );
      expect( h.bloc.state.liveQuestion, 'second question', reason: 'the stale Result did not disturb the live one' );

      await push( second, resultFor( jobId: 'job-second' ) );
      verifyNever( () => h.repo.cancelJob( 'job-second' ) );
      expect( h.bloc.state.liveJobId, 'job-second' );
      expect( h.bloc.state.entries.single.questionText, 'second question' );
    } );
  } );

  group( 'C-J2 — the read continues after cancel, tracked per epoch', () {

    test( 'two streams are live at once, and each terminal removes ONLY its own key', () async {
      await speak( h );
      final first = s.last;
      h.bloc.add( const QuickAskRecordCancelled() );
      await settle();
      await speak( h );
      final second = s.last;

      final epochs = h.bloc.liveSpokenEpochs.toList()..sort();
      expect( epochs, hasLength( 2 ), reason: 'cancel must not stop the first read' );
      expect( s.cancelled, [ false, false ] );

      await push( first, resultFor( jobId: 'job-first' ) );
      expect( h.bloc.liveSpokenEpochs, { epochs.last }, reason: "the first stream's terminal removed the FIRST key" );

      await push( second, const SpokenAskTranscript( 'second' ) );
      await push( second, resultFor( jobId: 'job-second' ) );
      expect( h.bloc.liveSpokenEpochs, isEmpty );
    } );
  } );

  group( 'C-J3 — frames before the transcript are BUFFERED, not dropped (CC1)', () {

    test( 'a transition that lands before line 1 is folded into the card when the Result arrives', () async {
      await speak( h );
      expect( h.bloc.state.liveQuestion, isNull );

      // Matched on the SESSION branch only — no question text exists yet.
      h.bloc.add( QuickAskTransitionReceived( transitionFrame(
        from: 'queued', to: 'running', question: null, sessionId: ourSession ) ) );
      await settle();

      await push( s.last, const SpokenAskTranscript( spokenText ) );
      await push( s.last, resultFor() );

      expect( h.bloc.state.entries.single.state, JobLifecycleState.running,
          reason: 'the pre-transcript frame was buffered and drained, not lost' );
    } );

    // Departure from rev 14 §3.3 step 2 (Mr. Radio, 16:35), test shape per
    // rev 16 (FC-1): fill the buffer to `bufferCap` with stream A's frames,
    // press B, and B's pre-Transcript frame must still be delivered.
    test( "cancel-then-press with the buffer FULL of A's frames: B's pre-transcript frame survives", () async {
      await speak( h );
      final a = s.last;
      for ( var i = 0; i < QuickAskBloc.bufferCap; i++ ) {
        h.bloc.add( QuickAskTransitionReceived( transitionFrame(
          jobId: 'job-a', from: 'queued', to: 'running', question: null, sessionId: ourSession ) ) );
      }
      await settle( 64 );
      expect( h.bloc.bufferedFrameCount, QuickAskBloc.bufferCap, reason: 'positive control: the buffer really is full' );

      h.bloc.add( const QuickAskRecordCancelled() );
      await settle();
      await speak( h );
      final b = s.last;

      // 🔴 The guard on the subscribe-time clear itself. Behaviour alone
      // cannot see it — FIFO eviction keeps B's frame either way — so a
      // deleted clear would otherwise pass this whole test (measured, FC-1).
      expect( h.bloc.bufferedFrameCount, 0, reason: "B's subscribe emptied A's leftovers" );

      h.bloc.add( QuickAskTransitionReceived( transitionFrame(
        jobId: 'job-b', from: 'queued', to: 'running', question: null, sessionId: ourSession ) ) );
      await settle();
      expect( h.bloc.bufferedFrameCount, 1 );

      await push( b, const SpokenAskTranscript( 'question b' ) );
      await push( a, resultFor( jobId: 'job-a' ) );
      await push( b, resultFor( jobId: 'job-b' ) );

      final card = h.bloc.state.entries.single;
      expect( card.jobId, 'job-b' );
      expect( card.state, JobLifecycleState.running, reason: "B's pre-transcript frame was not evicted" );
      expect( h.bloc.state.liveJobId, 'job-b' );
      verify( () => h.repo.cancelJob( 'job-a' ) ).called( 1 );
    } );
  } );

  group( 'D2 — the bloc CALLS discardPendingUpload( its own path ) on every ending', () {

    test( 'on a Result', () async {
      await speak( h );
      await push( s.last, const SpokenAskTranscript( spokenText ) );
      verifyNever( () => h.asr.discardPendingUpload( any() ) );
      await push( s.last, resultFor() );
      verify( () => h.asr.discardPendingUpload( recordingPath ) ).called( 1 );
    } );

    test( 'on a Failed', () async {
      await speak( h );
      await push( s.last, const SpokenAskFailed( 'No speech was recognised, so nothing was asked.', statusCode: 422 ) );
      verify( () => h.asr.discardPendingUpload( recordingPath ) ).called( 1 );
    } );

    test( 'on a CutOff', () async {
      await speak( h );
      await push( s.last, const SpokenAskTranscript( spokenText ) );
      await push( s.last, const SpokenAskCutOff( spokenText ) );
      verify( () => h.asr.discardPendingUpload( recordingPath ) ).called( 1 );
    } );

    test( 'on a stale Result too — cancelling the job does not skip the disposal (C2-B)', () async {
      await speak( h );
      h.bloc.add( const QuickAskRecordCancelled() );
      await settle();
      await push( s.last, resultFor() );
      verify( () => h.asr.discardPendingUpload( recordingPath ) ).called( 1 );
      verify( () => h.repo.cancelJob( ourJob ) ).called( 1 );
    } );

    test( "cancel-then-press: stream A's ending deletes A's file, never B's (C2-A)", () async {
      await speak( h );
      final a = s.last;
      h.bloc.add( const QuickAskRecordCancelled() );
      await settle();
      await speak( h );
      final b = s.last;

      await push( a, resultFor( jobId: 'job-a' ) );
      verify( () => h.asr.discardPendingUpload( recordingPathFor( 0 ) ) ).called( 1 );
      verifyNever( () => h.asr.discardPendingUpload( recordingPathFor( 1 ) ) );

      await push( b, const SpokenAskTranscript( 'question b' ) );
      await push( b, resultFor( jobId: 'job-b' ) );
      verify( () => h.asr.discardPendingUpload( recordingPathFor( 1 ) ) ).called( 1 );
    } );

    test( 'on the never-subscribed path: askSpoken throws before returning a stream', () async {
      when( () => h.repo.askSpoken( any(), any() ) ).thenThrow( StateError( 'boom' ) );

      await speak( h );

      verify( () => h.asr.discardPendingUpload( recordingPath ) ).called( 1 );
      expect( h.bloc.liveSpokenEpochs, isEmpty, reason: 'no key for a stream that never existed' );
      expect( h.bloc.state.phase, QuickAskPhase.idle );
      expect( h.bloc.state.errorMessage, isNotNull );
    } );

    test( 'stopToFile throws: nothing was retained, so nothing is discarded or sent', () async {
      when( () => h.asr.stopToFile() ).thenThrow( const AsrException( 'Recorder produced no file' ) );

      await speak( h );

      verifyNever( () => h.asr.discardPendingUpload( any() ) );
      verifyNever( () => h.repo.askSpoken( any(), any() ) );
      expect( h.bloc.liveSpokenEpochs, isEmpty );
      expect( h.bloc.state.errorMessage, 'Recorder produced no file' );
    } );

    test( 'a cancel while the recorder is stopping sends nothing and discards the file', () async {
      final stopped = Completer<String>();
      when( () => h.asr.stopToFile() ).thenAnswer( ( _ ) => stopped.future );

      h.bloc.add( const QuickAskRecordPressed() );
      await settle();
      h.bloc.add( const QuickAskRecordReleased() );
      await settle();
      h.bloc.add( const QuickAskRecordCancelled() );
      await settle();
      stopped.complete( recordingPath );
      await settle();

      verifyNever( () => h.repo.askSpoken( any(), any() ) );
      verify( () => h.asr.discardPendingUpload( recordingPath ) ).called( 1 );
      expect( h.bloc.liveSpokenEpochs, isEmpty );
    } );
  } );

  group( 'every other ending of the stream', () {

    test( 'Result parked → the interview opens', () async {
      await speak( h );
      await push( s.last, const SpokenAskTranscript( spokenText ) );
      await push( s.last, resultFor( jobId: null, status: 'parked', pendingId: 'p-1',
          answer: 'Which city?', argsMissing: const [ 'location' ] ) );

      expect( h.bloc.state.interview?.pendingId, 'p-1' );
      expect( h.bloc.state.interview?.question, 'Which city?' );
      expect( h.bloc.state.liveQuestion, spokenText );
    } );

    test( 'Result needs_input → a failed card naming what was missing', () async {
      await speak( h );
      await push( s.last, const SpokenAskTranscript( spokenText ) );
      await push( s.last, resultFor( jobId: null, status: 'needs_input', argsMissing: const [ 'location' ] ) );

      final card = h.bloc.state.entries.single;
      expect( card.state, JobLifecycleState.failed );
      expect( card.details?.error, 'Missing: location' );
    } );

    test( 'CutOff → the "cut off" card, nothing to cancel', () async {
      await speak( h );
      await push( s.last, const SpokenAskTranscript( spokenText ) );
      await push( s.last, const SpokenAskCutOff( spokenText ) );

      final card = h.bloc.state.entries.single;
      expect( card.state, JobLifecycleState.failed );
      expect( card.questionText, spokenText );
      expect( card.details?.error, QuickAskBloc.cutOffMessage );
      expect( h.bloc.state.phase, QuickAskPhase.idle );
      expect( h.bloc.state.liveJobId, isNull );
      verifyNever( () => h.repo.cancelJob( any() ) );
    } );

    test( 'Failed → idle with the error, no card', () async {
      await speak( h );
      await push( s.last, const SpokenAskFailed( 'Could not accept the audio. Nothing was asked.', statusCode: 500 ) );

      expect( h.bloc.state.phase, QuickAskPhase.idle );
      expect( h.bloc.state.errorMessage, 'Could not accept the audio. Nothing was asked.' );
      expect( h.bloc.state.entries, isEmpty );
    } );

    // N-C1: the row says "cancels EVERY subscription", so two are live here —
    // a close() that cancelled only the current epoch's stream would pass a
    // one-stream test.
    test( 'close() mid-stream cancels EVERY live subscription, and discards nothing', () async {
      await speak( h );
      await push( s.last, const SpokenAskTranscript( spokenText ) );
      h.bloc.add( const QuickAskRecordCancelled() );
      await settle();
      await speak( h );
      expect( h.bloc.liveSpokenEpochs, hasLength( 2 ) );
      expect( s.cancelled, [ false, false ] );

      await h.bloc.close();

      expect( s.cancelled, [ true, true ] );
      verifyNever( () => h.asr.discardPendingUpload( any() ) );    // C2-D
    } );

    // N-C3: `connected` goes true only after the session id is validated
    // (websocket_service.dart:153-167), but `disconnect()` nulls it (:412-413)
    // without stopping a capture that already started. A release then has no
    // session to route the answer to, and an empty websocket_id would make
    // the server fall back to api-<uid8>, where nobody is listening.
    test( 'no session id at release: nothing is sent, the recording is discarded, and the user is told', () async {
      final r = Harness( sendImmediately: true, sessionId: null );
      final rs = SpokenStubs( r );
      addTearDown( r.dispose );
      await settle();

      await speak( r );

      verifyNever( () => r.repo.askSpoken( any(), any() ) );
      verify( () => r.asr.discardPendingUpload( recordingPathFor( 0 ) ) ).called( 1 );
      expect( rs.streams, isEmpty );
      expect( r.bloc.liveSpokenEpochs, isEmpty );
      expect( r.bloc.state.phase, QuickAskPhase.idle );
      expect( r.bloc.state.errorMessage, QuickAskBloc.noSessionMessage );
    } );
  } );
}
