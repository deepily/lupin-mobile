/// AC-S1.4 / AC-S1.4b / AC-S1.4c / AC-S1.4d — the silence watchdog.
///
/// There is NO terminal event for a server restart: `JobState.INTERRUPTED`
/// appears only in a DB startup sweep, never in a WS emit, so a bounce
/// mid-job produces no frame at all and the UI would spin forever. The
/// watchdog is required, not optional.
///
/// 🔴 Every horizon below is COMPUTED from the bloc's own cadence constants,
/// never hardcoded. `315s` is only `sum(45, 90, 180)` for today's ladder —
/// retune it to 60/120/240 and the death point moves to 420s, at which point a
/// hardcoded 315 stops discriminating and the test passes for the wrong
/// reason.
library;

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/features/queue/data/queue_models.dart';
import 'package:lupin_mobile/features/queue/domain/job_lifecycle.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_bloc.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_event.dart';

import '_quick_ask_harness.dart';

/// The moment the ladder would run out if EVERY probe came back
/// found-nowhere — derived, not written down.
Duration get deathPoint => QuickAskBloc.watchdogLadder.fold(
  Duration.zero, ( a, b ) => a + b );

/// Comfortably past it, with margin that scales when the ladder is retuned.
Duration get drivePast => deathPoint * 2 + const Duration( seconds: 30 );

void main() {
  setUpAll( () { registerFallbackValue( const AskRequest( question: 'x' ) ); } );

  /// Drives a real bloc to the `waiting` state inside a FakeAsync zone.
  void withLiveJob( void Function( FakeAsync async, Harness h ) body, {
    required void Function( Harness h ) stubs,
  } ) {
    fakeAsync( ( async ) {
      final h = Harness( now: () => DateTime( 2026, 8, 29 ).add( async.elapsed ) );
      stubs( h );
      // Let the connection stream's replay land before the first gesture —
      // `canRecord`'s socket clause is false until it does.
      async.elapse( const Duration( milliseconds: 10 ) );
      when( () => h.repo.ask( any() ) ).thenAnswer( ( _ ) async => waitingAsk() );
      when( () => h.asr.stopAndTranscribe() ).thenAnswer( ( _ ) async => 'what is the weather' );

      h.bloc.add( const QuickAskRecordPressed() );
      async.elapse( const Duration( milliseconds: 10 ) );
      h.bloc.add( const QuickAskRecordReleased() );
      async.elapse( const Duration( milliseconds: 50 ) );

      expect( h.bloc.state.liveJobId, ourJob, reason: 'setup failed — no live job to watch' );
      body( async, h );
      h.bloc.close();
      async.elapse( const Duration( seconds: 1 ) );
    } );
  }

  group( 'AC-S1.4 — the watchdog reconciles through the QUEUE LISTINGS', () {

    test( 'found in DONE completes the entry with responseText', () {
      withLiveJob(
        stubs: ( h ) {
          h.stubEmptyQueues();
          when( () => h.repo.getQueue( 'done' ) ).thenAnswer( ( _ ) async =>
              queueWith( 'done', [ summaryRow( status: 'completed', responseText: 'It is sunny.' ) ] ) );
        },
        ( async, h ) {
          async.elapse( QuickAskBloc.watchdogLadder.first + const Duration( seconds: 1 ) );
          expect( h.bloc.state.entries.last.state,  JobLifecycleState.completed );
          expect( h.bloc.state.entries.last.answer, 'It is sunny.' );
          expect( h.bloc.state.liveJobId, isNull );
        },
      );
    } );

    test( 'found in DEAD fails the entry with the error', () {
      withLiveJob(
        stubs: ( h ) {
          h.stubEmptyQueues();
          when( () => h.repo.getQueue( 'dead' ) ).thenAnswer( ( _ ) async =>
              queueWith( 'dead', [ summaryRow( status: 'failed', error: 'agent exploded' ) ] ) );
        },
        ( async, h ) {
          async.elapse( QuickAskBloc.watchdogLadder.first + const Duration( seconds: 1 ) );
          expect( h.bloc.state.entries.last.state, JobLifecycleState.failed );
          expect( h.bloc.state.entries.last.error, 'agent exploded' );
        },
      );
    } );

    test( 'getJobHistoryEntry is NEVER called — it is the wrong door and would 404', () {
      // All PostgreSQL persistence is gated on `is_agentic_job_type()` against
      // a 10-entry allowlist. A plain question is not an agentic type, so no
      // row is ever written and the history door cannot answer.
      withLiveJob(
        stubs: ( h ) => h.stubEmptyQueues(),
        ( async, h ) {
          async.elapse( drivePast );
          verifyNever( () => h.repo.getJobHistoryEntry( any() ) );
          verify( () => h.repo.getQueue( 'done' ) ).called( greaterThan( 0 ) );
        },
      );
    } );
  } );

  group( 'AC-S1.4c — found-alive RESETS the ladder; only found-nowhere decrements', () {

    test( 'a job visible in RUN on every probe NEVER reaches lost', () {
      // 🔴 This is the F-Chloé-S1-8 falsifier. An implementation that runs
      // found-alive and found-nowhere down one shared rearm path declares a
      // plainly RUNNING job `lost` at the death point, and tells the user it is
      // gone while the server is happily running it.
      withLiveJob(
        stubs: ( h ) => h.stubFoundIn( 'run' ),
        ( async, h ) {
          async.elapse( drivePast );
          expect( h.bloc.state.lost, isFalse,
              reason: 'the server can SEE the job — that is positive proof of life, not a strike' );
          expect( h.bloc.state.liveJobId, ourJob, reason: 'still live, still being watched' );
        },
      );
    } );

    test( 'a job visible in TODO on every probe NEVER reaches lost either', () {
      withLiveJob(
        stubs: ( h ) => h.stubFoundIn( 'todo', row: summaryRow( status: 'queued' ) ),
        ( async, h ) {
          async.elapse( drivePast );
          expect( h.bloc.state.lost, isFalse );
        },
      );
    } );

    test( 'EXACTLY 3 consecutive found-nowhere probes reach lost — bounded, not open-ended', () {
      withLiveJob(
        stubs: ( h ) => h.stubEmptyQueues(),
        ( async, h ) {
          // Not lost before the third strike lands.
          var elapsed = Duration.zero;
          for ( var i = 0; i < QuickAskBloc.lostAfterStrikes - 1; i++ ) {
            elapsed += QuickAskBloc.watchdogLadder[ i ] + const Duration( seconds: 1 );
          }
          async.elapse( elapsed );
          expect( h.bloc.state.lost, isFalse,
              reason: 'two strikes is not three — N is bounded at ${QuickAskBloc.lostAfterStrikes}' );

          async.elapse( drivePast );
          expect( h.bloc.state.lost, isTrue,
              reason: 'a watchdog that can never terminate spins the UI forever' );
        },
      );
    } );

    test( 'lost is FLOORED by the server\'s own stall threshold, never declared earlier', () {
      withLiveJob(
        stubs: ( h ) => h.stubEmptyQueues(),
        ( async, h ) {
          // Never tell the user a job is lost while the server still considers
          // it healthy: `cj flow consumer stall threshold seconds`.
          async.elapse( QuickAskBloc.serverStallThreshold );
          expect( h.bloc.state.lost, isFalse,
              reason: 'inside the server\'s own patience window, silence is not death' );
          async.elapse( drivePast );
          expect( h.bloc.state.lost, isTrue );
        },
      );
    } );

    test( 'found-alive AFTER strikes CLEARS them — the count is consecutive, not cumulative', () {
      fakeAsync( ( async ) {
        final h = Harness( now: () => DateTime( 2026, 8, 29 ).add( async.elapsed ) );
        async.elapse( const Duration( milliseconds: 10 ) );
        h.stubEmptyQueues();
        when( () => h.repo.ask( any() ) ).thenAnswer( ( _ ) async => waitingAsk() );
        when( () => h.asr.stopAndTranscribe() ).thenAnswer( ( _ ) async => 'what is the weather' );
        h.bloc.add( const QuickAskRecordPressed() );
        async.elapse( const Duration( milliseconds: 10 ) );
        h.bloc.add( const QuickAskRecordReleased() );
        async.elapse( const Duration( milliseconds: 50 ) );

        // Two strikes accumulate...
        async.elapse( QuickAskBloc.watchdogLadder[ 0 ] + QuickAskBloc.watchdogLadder[ 1 ]
                    + const Duration( seconds: 2 ) );
        expect( h.bloc.state.lost, isFalse );

        // ...then the job turns up alive, and the count must go back to zero.
        h.stubFoundIn( 'run' );
        async.elapse( drivePast );
        expect( h.bloc.state.lost, isFalse,
            reason: 'strikes are CONSECUTIVE; proof of life clears the tally' );

        h.bloc.close();
        async.elapse( const Duration( seconds: 1 ) );
      } );
    } );
  } );

  group( 'AC-S1.4d — reconcile-vs-folded precedence', () {

    test( 'a TERMINAL reconcile result WINS over a non-terminal folded state', () {
      withLiveJob(
        stubs: ( h ) {
          h.stubEmptyQueues();
          when( () => h.repo.getQueue( 'done' ) ).thenAnswer( ( _ ) async =>
              queueWith( 'done', [ summaryRow( status: 'completed', responseText: 'from the listing' ) ] ) );
        },
        ( async, h ) {
          h.bloc.add( QuickAskTransitionReceived( transitionFrame( from: 'queued', to: 'running' ) ) );
          async.elapse( const Duration( milliseconds: 50 ) );
          expect( h.bloc.state.liveEntry?.state, JobLifecycleState.running );

          async.elapse( QuickAskBloc.watchdogLadder.first + const Duration( seconds: 1 ) );
          expect( h.bloc.state.entries.last.state,  JobLifecycleState.completed,
              reason: 'the listing is the server\'s own record, and we are only here because frames went missing' );
          expect( h.bloc.state.entries.last.answer, 'from the listing' );
        },
      );
    } );

    test( 'a NON-TERMINAL reconcile result NEVER overrides a terminal folded state', () {
      // 🔴 The falsifier: a reconciler that applies its result unconditionally
      // overwrites a `completed` we actually received with a stale `run` row.
      fakeAsync( ( async ) {
        final h = Harness( now: () => DateTime( 2026, 8, 29 ).add( async.elapsed ) );
        async.elapse( const Duration( milliseconds: 10 ) );
        h.stubFoundIn( 'run' );                       // the listing has not caught up
        when( () => h.repo.ask( any() ) ).thenAnswer( ( _ ) async => waitingAsk() );
        when( () => h.asr.stopAndTranscribe() ).thenAnswer( ( _ ) async => 'what is the weather' );
        h.bloc.add( const QuickAskRecordPressed() );
        async.elapse( const Duration( milliseconds: 10 ) );
        h.bloc.add( const QuickAskRecordReleased() );
        async.elapse( const Duration( milliseconds: 50 ) );

        h.bloc.add( QuickAskTransitionReceived( transitionFrame(
          from: 'running', to: 'completed', responseText: 'the real answer' ) ) );
        async.elapse( const Duration( milliseconds: 50 ) );
        expect( h.bloc.state.entries.last.state, JobLifecycleState.completed );

        async.elapse( drivePast );
        expect( h.bloc.state.entries.last.state,  JobLifecycleState.completed,
            reason: 'a completed frame we received is not undone by a stale listing' );
        expect( h.bloc.state.entries.last.answer, 'the real answer' );

        h.bloc.close();
        async.elapse( const Duration( seconds: 1 ) );
      } );
    } );
  } );

  group( 'AC-S1.4b — a response_requested notification RESETS the watchdog', () {

    test( 'in the PRE-JOB-ID window it rearms and attempts NO reconcile', () {
      // Chloé's finding: the Door C confirm is the one thing that arrives in
      // the window where no job id exists yet, and that window is long — the
      // ask blocks up to ~210s while the confirm ladder runs, and no
      // `job_state_transition` can arrive because nothing has been queued. A
      // watchdog armed at submission would fire into that silence with NOTHING
      // to reconcile: no job_id to look up, every probe "not found", and a
      // false `lost` on a request that is alive and waiting for the user.
      fakeAsync( ( async ) {
        final h = Harness( now: () => DateTime( 2026, 8, 29 ).add( async.elapsed ) );
        async.elapse( const Duration( milliseconds: 10 ) );
        h.stubEmptyQueues();
        final gate = Completer<AskResponse>();
        when( () => h.repo.ask( any() ) ).thenAnswer( ( _ ) => gate.future );
        when( () => h.asr.stopAndTranscribe() ).thenAnswer( ( _ ) async => 'what is the weather' );

        h.bloc.add( const QuickAskRecordPressed() );
        async.elapse( const Duration( milliseconds: 10 ) );
        h.bloc.add( const QuickAskRecordReleased() );
        async.elapse( const Duration( milliseconds: 50 ) );
        expect( h.bloc.state.liveJobId, isNull, reason: 'the ask is still blocked — no job id yet' );

        // Door C's confirm arrives.
        h.bloc.add( QuickAskNotificationReceived( notif( id: 'confirm-1', responseRequested: true ) ) );
        async.elapse( drivePast );

        expect( h.bloc.state.lost, isFalse, reason: 'a live request must never be declared lost' );
        verifyNever( () => h.repo.getQueue( any() ) );
        expect( h.bloc.state.pendingPromptId, 'confirm-1' );

        gate.complete( waitingAsk() );
        async.elapse( const Duration( milliseconds: 50 ) );
        h.bloc.close();
        async.elapse( const Duration( seconds: 1 ) );
      } );
    } );

    test( 'with a live job it resets the ladder exactly as an accepted frame does', () {
      withLiveJob(
        stubs: ( h ) => h.stubEmptyQueues(),
        ( async, h ) {
          // Two strikes accumulate, then a confirm lands and clears them.
          async.elapse( QuickAskBloc.watchdogLadder[ 0 ] + QuickAskBloc.watchdogLadder[ 1 ]
                      + const Duration( seconds: 2 ) );
          h.bloc.add( QuickAskNotificationReceived( notif( id: 'c-2', responseRequested: true ) ) );
          async.elapse( const Duration( milliseconds: 50 ) );

          // From the reset, one more full ladder must not be enough to die.
          async.elapse( QuickAskBloc.watchdogLadder[ 0 ] + const Duration( seconds: 1 ) );
          expect( h.bloc.state.lost, isFalse );
        },
      );
    } );
  } );

  group( 'the belt channel — independent completion evidence', () {

    test( 'a notification whose jobId matches the live job completes it, message as the answer', () {
      withLiveJob(
        stubs: ( h ) => h.stubFoundIn( 'run' ),
        ( async, h ) {
          h.bloc.add( QuickAskNotificationReceived(
            notif( id: 'n-9', message: 'It is sunny.', jobId: ourJob ) ) );
          async.elapse( const Duration( milliseconds: 50 ) );
          expect( h.bloc.state.entries.last.state,  JobLifecycleState.completed );
          expect( h.bloc.state.entries.last.answer, 'It is sunny.' );
          expect( h.bloc.state.liveJobId, isNull );
        },
      );
    } );

    test( 'a notification for a DIFFERENT job leaves the live entry alone', () {
      withLiveJob(
        stubs: ( h ) => h.stubFoundIn( 'run' ),
        ( async, h ) {
          h.bloc.add( QuickAskNotificationReceived(
            notif( id: 'n-9', message: 'someone else', jobId: 'other-job' ) ) );
          async.elapse( const Duration( milliseconds: 50 ) );
          expect( h.bloc.state.entries.last.state, isNot( JobLifecycleState.completed ) );
        },
      );
    } );
  } );
}
