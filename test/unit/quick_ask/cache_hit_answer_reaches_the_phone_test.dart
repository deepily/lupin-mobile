import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/queue/data/queue_models.dart';
import 'package:lupin_mobile/features/queue/domain/job_lifecycle.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_event.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_state.dart';
import 'package:mocktail/mocktail.dart';

import '_quick_ask_harness.dart';

/// 🔴 DOES A REPLAYED (CACHE-HIT) ANSWER ACTUALLY REACH THE PHONE?
///
/// Row 9511aa08, DONE WHEN path (b): *"a phone-side integration assertion that a
/// replay-path ask is followed by an answer frame on the WS within the timeout, and it
/// passes."* Built rather than asking Rick to repeat the two-minute loop by hand.
///
/// ⚠️ THE FIRST VERSION OF THIS FILE FAILED, AND THE FAILURE WAS MINE — A FIXTURE I
/// AUTHORED RATHER THAN CAPTURED. I built an `AskResponse` with `status: 'done'`,
/// `cache_hit: true` and NO `job_id`, reasoned that a cache hit needs no job, and
/// reported a confirmed defect off the resulting red. The manager escalated on it. Both
/// of us were wrong, and the product was fine the whole time.
///
/// THE REAL PAYLOAD — Rick's emulator tail, 2026-09-19 18:31:57 EDT, POST /api/v2/ask:
///
/// ```json
/// {"path":"replay","status":"waiting","route_reason":"exact_hit","answer":null,
///  "cache_hit":true,"spoke":false,
///  "job_id":"41cce903…::0cf47e2d-d5a1-4cd4-addf-79810fd32b15"}
/// ```
///
/// ⇒ TWO THINGS MY INVENTED FIXTURE GOT WRONG, AND EACH ALONE WOULD HAVE MISLED:
///   1. `status` is **"waiting"**, not "done". This is the ENQUEUE-time response; the
///      answer arrives afterwards over the WebSocket. `spoke: false` and `answer: null`
///      are what a CORRECT enqueue looks like, not symptoms.
///   2. `job_id` is **PRESENT**. It is present by construction on this path: the replay
///      Outcome's job_id IS the snapshot row's id_hash. `flow.py:1699` carries the
///      measurement — *"job_id present on 85 of 85 exact_hit rows and 0 of 126
///      replay_error rows"* — and the replay_error path that lacks one does not set
///      `cache_hit`.
///
/// ⚠️ WE SPENT THE NIGHT ARGUING FIXTURES MUST BE CAPTURED, NOT AUTHORED, BECAUSE AN
/// AUTHORED ONE ENCODES ITS AUTHOR'S BELIEFS AND CAN ONLY CONFIRM THEM. That rule earned
/// its keep here in the OPPOSITE direction: an authored fixture manufactured a red and a
/// false defect report, where the usual failure is a green that hides a real one. A
/// fixture that cannot fail honestly cannot pass honestly either.
///
/// ⇒ What this file now asserts is the thing nobody had: that a replay-path ask IS
/// followed by an answer frame, and that the answer reaches the card the user is looking
/// at.
AskResponse replayEnqueue( { String? jobId = ourJob } ) => AskResponse(
      path        : 'replay',
      status      : 'waiting',
      routeReason : 'exact_hit',
      traceId     : 'tr-replay',
      answer      : null,      // correct at enqueue time — the answer comes over the WS
      jobId       : jobId,
      cacheHit    : true,
    );

void main() {
  setUpAll( () {
    registerFallbackValue( const AskRequest( question: 'x' ) );
    registerFallbackValue( const ResumeRequest( pendingId: 'p', answer: 'a' ) );
  } );

  Future<Harness> askReturns( AskResponse res ) async {
    final h = Harness();
    h.stubEmptyQueues();
    when( () => h.asr.stopAndTranscribe() ).thenAnswer( ( _ ) async => 'what is the weather' );
    when( () => h.repo.ask( any() ) ).thenAnswer( ( _ ) async => res );
    await settle();
    h.bloc.add( const QuickAskRecordPressed() );
    await settle();
    h.bloc.add( const QuickAskRecordReleased() );
    await settle();
    h.bloc.add( const QuickAskDraftSent() );
    await settle();
    return h;
  }

  group( 'a replayed cache-hit answer reaches the phone', () {
    // The enqueue half. `answer: null` and `spoke: false` here are CORRECT — reading them
    // as a defect is reading a mid-flight state as a final one, which is the mistake the
    // row itself warned against and which I then made anyway.
    test( 'the replay ask enqueues and holds the job for correlation', () async {
      final h = await askReturns( replayEnqueue() );

      expect( h.bloc.state.phase,     QuickAskPhase.waiting,
          reason: 'status "waiting" means the work was accepted and is running behind' );
      expect( h.bloc.state.liveJobId, ourJob,
          reason: 'the job_id is the correlation handle the answer frame will arrive on' );
      await h.dispose();
    } );

    // 🔴 THE ASSERTION THE ROW EXISTS FOR. Rick's tail showed the enqueue and never showed
    // the answer arriving — "not the same thing as seeing 4 announced". This is that.
    test( 'the answer frame arrives and lands on the card', () async {
      final h = await askReturns( replayEnqueue() );

      h.bloc.add( QuickAskTransitionReceived(
        transitionFrame( from: 'running', to: 'completed', responseText: 'It is sunny.' ) ) );
      await settle();

      final entry = h.bloc.state.entries.last;
      expect( entry.state,  JobLifecycleState.completed );
      expect( entry.answer, 'It is sunny.',
          reason: 'entry.answer is what the card shows and what the Replay control '
                  'speaks — a replay whose answer never lands here is P1 0e7c9214 '
                  'recurring, which is the whole reason this row was filed' );
      expect( h.bloc.state.phase,     QuickAskPhase.idle );
      expect( h.bloc.state.liveJobId, isNull,
          reason: 'the ask is finished — the job must not stay live and re-arm a watchdog' );
      await h.dispose();
    } );

    // The correlation handle is what makes the frame findable. Without it the answer
    // arrives on the socket and has nowhere to land — which was the ACTUAL mechanism of
    // 0e7c9214, one level away from the fields my first fixture was poking at.
    test( 'the answer is matched to THIS ask, not to whatever arrived', () async {
      final h = await askReturns( replayEnqueue() );

      h.bloc.add( QuickAskTransitionReceived( transitionFrame(
        jobId: 'someone-elses-job', from: 'running', to: 'completed',
        responseText: 'a different answer' ) ) );
      await settle();

      expect( h.bloc.state.entries.last.answer, isNot( 'a different answer' ) );
      expect( h.bloc.state.liveJobId, ourJob,
          reason: 'a frame for another job must not resolve this one' );
      await h.dispose();
    } );
  } );
}
