import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/broadcast/data/broadcast_models.dart';
import 'package:lupin_mobile/features/broadcast/data/broadcast_repository.dart';
import 'package:lupin_mobile/features/broadcast/domain/broadcast_bloc.dart';
import 'package:lupin_mobile/services/asr/asr_service.dart';
import 'package:lupin_mobile/services/asr/voice_capture_session.dart';
import 'package:mocktail/mocktail.dart';

import '../_helpers/stub_dio.dart';

class _MockAsr extends Mock implements AsrService {}

void main() {
  late StubAdapter adapter;
  late _MockAsr asr;

  dynamic fixture( String name ) =>
      jsonDecode( File( 'test/fixtures/commons/$name' ).readAsStringSync() );

  BroadcastBloc makeBloc( { VoiceCaptureSession? voice } ) {
    final bloc = BroadcastBloc( BroadcastRepository( makeDio( adapter ) ), voice: voice );
    addTearDown( bloc.close );
    return bloc;
  }

  VoiceCaptureSession voiceSession() => VoiceCaptureSession(
    asr               : asr,
    requestPermission : () async => true,
  );

  /// Let the bloc's synchronous handlers drain.
  ///
  /// ⚠️ ONE `Duration.zero` IS NOT ENOUGH AND THE FAILURE IS MISLEADING. A handler goes
  /// through Dio's interceptor chain and the stub adapter, several futures deep, so a
  /// single microtask turn returns mid-flight and the assertion then fails as though the
  /// FEATURE were broken rather than the wait.
  Future<void> settle() => Future<void>.delayed( const Duration( milliseconds: 20 ) );

  /// 🔴 WAIT FOR THE POST-CONDITION, NOT FOR A DURATION.
  ///
  /// A fixed delay is a guess about someone else's scheduler, and it fails the way all
  /// such guesses do: green on a quiet machine, red when the file runs beside others.
  /// Measured here — `settle()` alone passed the roster tests in isolation and failed one
  /// of them under a full-directory run, which is the worst possible failure because it
  /// looks like a real defect and is not reproducible on the next attempt.
  ///
  /// This waits for the state the test is actually about and FAILS LOUDLY with the state
  /// it got, so a genuine regression still reads as one.
  Future<void> until(
    BroadcastBloc bloc,
    bool Function( BroadcastState s ) predicate,
    String because,
  ) async {
    final deadline = DateTime.now().add( const Duration( seconds: 5 ) );
    while ( !predicate( bloc.state ) ) {
      if ( DateTime.now().isAfter( deadline ) ) {
        fail( 'timed out waiting for $because — state was ${bloc.state}' );
      }
      await Future<void>.delayed( const Duration( milliseconds: 5 ) );
    }
  }

  /// The roster fetch has landed, one way or the other.
  Future<void> rosterSettled( BroadcastBloc bloc ) =>
      until( bloc, ( s ) => !s.rosterLoading && ( s.hasRecipients || s.rosterError != null ),
             'the roster fetch to finish' );

  /// The send has landed, one way or the other — accepted, refused, or rate-limited.
  Future<void> sendSettled( BroadcastBloc bloc ) => until(
    bloc,
    ( s ) => !s.sending &&
        ( s.aggregate != null || s.sendError != null || s.rateLimitedForSeconds != null ),
    'the send to finish',
  );

  setUp( () {
    adapter = StubAdapter();
    asr     = _MockAsr();
    when( () => asr.startRecording()  ).thenAnswer( ( _ ) async {} );
    when( () => asr.cancelRecording() ).thenAnswer( ( _ ) async {} );
    when( () => asr.isCapturing       ).thenReturn( false );

    adapter.handlers[ 'GET ${BroadcastRepository.activeSessionsPath}' ] =
        ( _ ) => jsonBody( fixture( 'active_sessions.json' ) );
    adapter.handlers[ 'POST ${BroadcastRepository.broadcastPath}' ] =
        ( _ ) => jsonBody( fixture( 'broadcast_send_queued.json' ) );
  } );

  group( '🔴 Send is disabled on TWO conditions, and the reason must be READABLE', () {
    test( 'body alone is not enough', () async {
      final bloc = makeBloc();
      bloc.add( const BroadcastBodyChanged( 'all hands' ) );
      await settle();

      // Zero live sessions. On the web this button is tappable and the confirm silently
      // no-ops; here it must be dead AND say why.
      expect( bloc.state.hasBody,       isTrue );
      expect( bloc.state.hasRecipients, isFalse );
      expect( bloc.state.canSend,       isFalse );
    } );

    test( 'recipients alone are not enough', () async {
      final bloc = makeBloc();
      bloc.add( const BroadcastRosterRequested() );
      await rosterSettled( bloc );

      expect( bloc.state.hasRecipients, isTrue );
      expect( bloc.state.canSend,       isFalse );
    } );

    test( 'both together enable it', () async {
      final bloc = makeBloc();
      bloc.add( const BroadcastRosterRequested() );
      bloc.add( const BroadcastBodyChanged( 'all hands' ) );
      await rosterSettled( bloc );

      expect( bloc.state.canSend,        isTrue );
      expect( bloc.state.disabledReason, isNull );
    } );

    test( '🔴 a FAILED roster names itself, instead of leaving a dead button', () async {
      adapter.handlers[ 'GET ${BroadcastRepository.activeSessionsPath}' ] =
          ( _ ) => jsonBody( { 'detail' : 'down' }, status: 500 );

      final bloc = makeBloc();
      bloc.add( const BroadcastRosterRequested() );
      bloc.add( const BroadcastBodyChanged( 'all hands' ) );
      await rosterSettled( bloc );

      // The web communicates this through `btn.title` — a tooltip, which a phone cannot
      // show. On flaky LTE a stale fetch would otherwise leave the operator holding a
      // typed message and a dead button with no reachable explanation.
      expect( bloc.state.canSend,        isFalse );
      expect( bloc.state.disabledReason, contains( 'did not load' ) );
      expect( bloc.state.disabledReason, contains( '↻' ) );
    } );

    test( 'every disabled path produces a reason, and an enabled one produces none', () async {
      final bloc = makeBloc();
      await settle();
      expect( bloc.state.disabledReason, isNotNull );

      bloc.add( const BroadcastRosterRequested() );
      bloc.add( const BroadcastBodyChanged( 'x' ) );
      await rosterSettled( bloc );
      expect( bloc.state.disabledReason, isNull );
    } );
  } );

  group( 'sending', () {
    test( 'clears the body on success and opens a tally', () async {
      final bloc = makeBloc();
      bloc.add( const BroadcastRosterRequested() );
      bloc.add( const BroadcastBodyChanged( 'all hands' ) );
      await rosterSettled( bloc );

      bloc.add( const BroadcastSendConfirmed() );
      await sendSettled( bloc );

      expect( bloc.state.body,                       '' );
      expect( bloc.state.aggregate?.broadcastId,     'b-fixture-0001' );
      expect( bloc.state.aggregate?.recipientsAtSend, 3 );
      expect( bloc.state.aggregate?.confidence,      AckConfidence.observed );
    } );

    test( '🔴 a FAILURE keeps the operator\'s words', () async {
      adapter.handlers[ 'POST ${BroadcastRepository.broadcastPath}' ] =
          ( _ ) => jsonBody( { 'detail' : 'nope' }, status: 400 );

      final bloc = makeBloc();
      bloc.add( const BroadcastRosterRequested() );
      bloc.add( const BroadcastBodyChanged( 'a message worth keeping' ) );
      await rosterSettled( bloc );

      bloc.add( const BroadcastSendConfirmed() );
      await sendSettled( bloc );

      // Clearing the box on failure destroys exactly the text the operator cared enough
      // to type, at the moment they are least able to retype it.
      expect( bloc.state.body,      'a message worth keeping' );
      expect( bloc.state.sendError, isNotNull );
    } );

    test( '🔴 `queued` with failed recipients is NOT reported as clean success', () async {
      adapter.handlers[ 'POST ${BroadcastRepository.broadcastPath}' ] = ( _ ) => jsonBody( {
        'broadcast_id'      : 'b9',
        'recipients'        : 2,
        'failed_recipients' : [ 'sess-9' ],
        'status'            : 'queued',
      } );

      final bloc = makeBloc();
      bloc.add( const BroadcastRosterRequested() );
      bloc.add( const BroadcastBodyChanged( 'x' ) );
      await rosterSettled( bloc );
      bloc.add( const BroadcastSendConfirmed() );
      await sendSettled( bloc );

      // Same shape as the 202 sentinel: a status that means accepted, read as delivered.
      expect( bloc.state.sendError, contains( '1 session' ) );
    } );

    test( 'a rate limit is its own state, not a generic failure', () async {
      adapter.handlers[ 'POST ${BroadcastRepository.broadcastPath}' ] = ( _ ) =>
          jsonBody( { 'detail' : 'rate limit exceeded' }, status: 429 );

      final bloc = makeBloc();
      bloc.add( const BroadcastRosterRequested() );
      bloc.add( const BroadcastBodyChanged( 'x' ) );
      await rosterSettled( bloc );
      bloc.add( const BroadcastSendConfirmed() );
      await sendSettled( bloc );

      expect( bloc.state.rateLimitedForSeconds, isNotNull );
      expect( bloc.state.sendError,             isNull );
      // And the body survives, because the server already has an opinion about it.
      expect( bloc.state.body,                  'x' );
    } );

    test( 'send is a no-op when the button would have been disabled', () async {
      final bloc = makeBloc();
      bloc.add( const BroadcastBodyChanged( 'x' ) );   // no roster
      await settle();

      bloc.add( const BroadcastSendConfirmed() );
      // ⚠️ A FIXED WAIT IS CORRECT HERE AND ONLY HERE. Every other send waits for the
      // send's post-condition, but this test asserts a send NEVER HAPPENS — so waiting
      // for one to finish could only ever time out. Proving a negative needs a bounded
      // wait and then an assertion that nothing arrived.
      await settle();

      expect( bloc.state.aggregate, isNull );
      expect( adapter.captured.where( ( r ) => r.method == 'POST' ), isEmpty );
    } );
  } );

  group( '🔴 the ack tally, and the one event it cannot take back', () {
    Future<BroadcastBloc> sent() async {
      final bloc = makeBloc();
      bloc.add( const BroadcastRosterRequested() );
      bloc.add( const BroadcastBodyChanged( 'x' ) );
      await rosterSettled( bloc );
      bloc.add( const BroadcastSendConfirmed() );
      await sendSettled( bloc );
      return bloc;
    }

    test( 'folds an ack that arrives on the socket', () async {
      final bloc = await sent();

      bloc.add( const BroadcastAckReceived(
        BroadcastAck( broadcastId: 'b-fixture-0001', sessionId: 's1', personaName: 'maria' ),
      ) );
      await settle();

      expect( bloc.state.aggregate?.ackedCount, 1 );
      expect( bloc.state.aggregate?.summary,    '1 of 3 acked' );
    } );

    test( '🔴 backgrounding makes the tally say so, permanently', () async {
      final bloc = await sent();

      bloc.add( const BroadcastAckReceived(
        BroadcastAck( broadcastId: 'b-fixture-0001', sessionId: 's1' ),
      ) );
      bloc.add( const BroadcastListeningInterrupted() );
      await settle();

      expect( bloc.state.aggregate?.summary, contains( 'could not be confirmed' ) );
      expect( bloc.state.aggregate?.summary, isNot( contains( ' of 3' ) ) );
    } );

    test( '🔴 an ack arriving AFTER the interruption does not restore the exact count', () async {
      final bloc = await sent();

      bloc.add( const BroadcastListeningInterrupted() );
      bloc.add( const BroadcastAckReceived(
        BroadcastAck( broadcastId: 'b-fixture-0001', sessionId: 's2' ),
      ) );
      await settle();

      // The socket coming back proves the socket is back. It says nothing about the acks
      // pushed while it was down, and those are gone — not in the undelivered drain, and
      // the io_tbl row an ack produces never receives `payload` at all.
      expect( bloc.state.aggregate?.confidence, AckConfidence.interrupted );
      expect( bloc.state.aggregate?.ackedCount, 1 );
      expect( bloc.state.aggregate?.summary,    contains( 'At least 1' ) );
    } );

    test( 'an interruption before anything was sent is harmless', () async {
      final bloc = makeBloc();
      bloc.add( const BroadcastListeningInterrupted() );
      await settle();

      expect( bloc.state.aggregate, isNull );
    } );
  } );

  group( 'the mic — it is the point of this pane, not a garnish', () {
    test( 'a heard transcript APPENDS rather than replacing what was typed', () async {
      when( () => asr.stopAndTranscribe() )
          .thenAnswer( ( _ ) async => 'and bring the logs' );

      final bloc = makeBloc( voice: voiceSession() );
      bloc.add( const BroadcastBodyChanged( 'all hands' ) );
      bloc.add( const BroadcastMicToggled() );            // start
      await settle();
      bloc.add( const BroadcastMicToggled() );            // stop + transcribe
      await settle();

      // Replacing would silently destroy the half the operator bothered to type.
      expect( bloc.state.body, 'all hands and bring the logs' );
      expect( bloc.state.mic,  MicState.idle );
    } );

    test( 'an empty box takes the transcript alone, with no leading space', () async {
      when( () => asr.stopAndTranscribe() ).thenAnswer( ( _ ) async => 'standup in five' );

      final bloc = makeBloc( voice: voiceSession() );
      bloc.add( const BroadcastMicToggled() );
      await settle();
      bloc.add( const BroadcastMicToggled() );
      await settle();

      expect( bloc.state.body, 'standup in five' );
    } );

    test( 'a refused microphone says so and does not strand the button', () async {
      final bloc = makeBloc( voice: VoiceCaptureSession(
        asr               : asr,
        requestPermission : () async => false,
      ) );

      bloc.add( const BroadcastMicToggled() );
      await settle();

      expect( bloc.state.mic,      MicState.idle );
      expect( bloc.state.micError, isNotNull );
    } );

    test( 'no voice service at all is reported, not crashed through', () async {
      final bloc = makeBloc();   // voice: null
      bloc.add( const BroadcastMicToggled() );
      await settle();

      expect( bloc.state.micError, isNotNull );
    } );
  } );

  group( '🔴 STATE EQUALITY — a summary in `props` silently drops rebuilds', () {
    // bloc skips an emit when the new state compares equal to the old one. So anything
    // `props` summarises into a NUMBER can change without the pane ever hearing about it.
    // These three cases are what that actually costs.

    test( '🔴 a RE-ack from a session already counted still changes the state', () async {
      final bloc = makeBloc();
      bloc.add( const BroadcastRosterRequested() );
      bloc.add( const BroadcastBodyChanged( 'x' ) );
      await rosterSettled( bloc );
      bloc.add( const BroadcastSendConfirmed() );
      await sendSettled( bloc );

      bloc.add( const BroadcastAckReceived( BroadcastAck(
        broadcastId : 'b-fixture-0001', sessionId : 's1', personaName : 'maria',
      ) ) );
      await settle();
      final before = bloc.state;

      // Same session, so the COUNT does not move. Only the summary text arrives.
      bloc.add( const BroadcastAckReceived( BroadcastAck(
        broadcastId : 'b-fixture-0001', sessionId : 's1', personaName : 'maria',
        bodySummary : 'on it — picking this up now',
      ) ) );
      await settle();

      expect( bloc.state.aggregate!.ackedCount, 1, reason: 'still one session' );
      expect( bloc.state, isNot( equals( before ) ),
              reason: 'the state must differ, or bloc skips the emit and the pane never '
                      'shows what the seat actually said' );
      expect( bloc.state.aggregate!.acks.single.bodySummary, isNotEmpty );
    } );

    test( '🔴 a roster of three replaced by a DIFFERENT three changes the state', () async {
      final bloc = makeBloc();
      bloc.add( const BroadcastRosterRequested() );
      await rosterSettled( bloc );
      final before = bloc.state;

      // One seat left, another joined. Still three.
      adapter.handlers[ 'GET ${BroadcastRepository.activeSessionsPath}' ] = ( _ ) => jsonBody( {
        'sessions' : [
          { 'session_id' : 'x1', 'persona_name' : 'chloe' },
          { 'session_id' : 'x2', 'persona_name' : 'sam' },
          { 'session_id' : 'x3', 'persona_name' : 'rachel' },
        ],
      } );
      bloc.add( const BroadcastRosterRequested() );
      await until( bloc, ( s ) => s.roster.sessions.any( ( x ) => x.sessionId == 'x1' ),
                   'the second roster to land' );

      expect( bloc.state.roster.count, 3, reason: 'the count is deliberately unchanged' );
      expect( bloc.state, isNot( equals( before ) ),
              reason: 'otherwise the confirm modal names the WRONG PEOPLE — the one screen '
                      'whose job is saying who is about to be interrupted' );
    } );

    test( '🔴 history entries swapped for the same NUMBER of entries changes the state',
        () async {
      adapter.handlers[ 'GET ${BroadcastRepository.historyPath}' ] =
          ( _ ) => jsonBody( const { 'entries' : [ { 'body' : 'one' } ] } );
      final bloc = makeBloc();
      bloc.add( const BroadcastHistoryRequested() );
      await until( bloc, ( s ) => s.history.isNotEmpty, 'the first history' );
      final before = bloc.state;

      adapter.handlers[ 'GET ${BroadcastRepository.historyPath}' ] =
          ( _ ) => jsonBody( const { 'entries' : [ { 'body' : 'two' } ] } );
      bloc.add( const BroadcastHistoryRequested() );
      await until( bloc, ( s ) => s.history.first[ 'body' ] == 'two', 'the second history' );

      expect( bloc.state.history, hasLength( 1 ) );
      expect( bloc.state, isNot( equals( before ) ) );
    } );
  } );

  group( 'history — decoration that must not disturb compose', () {
    test( 'a history failure leaves the compose state alone', () async {
      adapter.handlers[ 'GET ${BroadcastRepository.historyPath}' ] =
          ( _ ) => jsonBody( { 'detail' : 'down' }, status: 500 );

      final bloc = makeBloc();
      bloc.add( const BroadcastBodyChanged( 'keep me' ) );
      bloc.add( const BroadcastHistoryRequested() );
      await settle();

      expect( bloc.state.body,      'keep me' );
      expect( bloc.state.sendError, isNull );
      expect( bloc.state.history,   isEmpty );
    } );
  } );
}
