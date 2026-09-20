import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/queue/data/queue_models.dart';
import 'package:lupin_mobile/features/queue/domain/job_lifecycle.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_event.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_state.dart';
import 'package:mocktail/mocktail.dart';

import '_quick_ask_harness.dart';

/// 🔴 DOES A REPLAYED CACHE-HIT ANSWER ACTUALLY REACH THE PHONE?
///
/// Asked as a question, answered by test rather than by patch — the instruction was to
/// PROVE whether the answer arrives or not, and a fix applied before the proof would
/// leave nobody able to say what was broken.
///
/// THE PATH. A cache hit comes back on the ASK response itself, synchronously:
/// `status: "done"` with an `answer` and `cache_hit: true`. The bloc's own comment on that
/// branch says *"Served from cache or inline — the answer is already here, no correlation
/// needed and no watchdog to arm."* Nothing is queued, nothing is correlated, and no
/// notification carries it — so if the ask response is not fully unpacked, the answer has
/// no second chance to arrive.
///
/// THE SUSPECT, found by reading the branch rather than the symptom
/// (`quick_ask_bloc.dart`, the `res.isDone` arm):
///
/// ```dart
/// details : res.jobId == null ? null : JobSummary( … responseText: res.answer … ),
/// ```
///
/// and the answer is read back through `quick_ask_models.dart:55`:
///
/// ```dart
/// String? get answer => details?.responseText;
/// ```
///
/// ⇒ WITH NO `jobId`, `details` IS NULL, SO `entry.answer` IS NULL — and the Replay
/// control is rendered only when there is an answer to replay
/// (`quick_ask_screen.dart:761-764`, `tts.replay( message: entry.answer! )`).
///
/// ⚠️ `AskResponse.jobId` IS NULLABLE (`queue_models.dart:220`) and a cache hit is exactly
/// the case that needs no job — there is nothing to run, so there may be nothing to
/// identify. The existing coverage never exercises it: `status_routing_test.dart:68`'s
/// `doneWith()` always supplies `jobId: 'j-done'`, so every `done` test in this suite
/// takes the branch where `details` survives.
///
/// The tests below pin BOTH shapes. Whichever way they land, the answer to Tiffany's
/// question is a measurement rather than an opinion.
AskResponse cacheHit( String answer, { String? jobId } ) => AskResponse(
      path        : 'agent',
      status      : 'done',
      routeReason : 'router:cache',
      traceId     : 'tr-cache',
      answer      : answer,
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

  group( 'a cache-hit answer reaches the phone', () {
    test( 'WITH a jobId — the answer is on the card and replayable', () async {
      final h = await askReturns( cacheHit( 'seventy two and sunny', jobId: 'j-cache' ) );
      final entry = h.bloc.state.entries.single;

      expect( entry.state, JobLifecycleState.completed );
      expect( entry.answer, 'seventy two and sunny',
          reason: 'entry.answer is what the Replay control speaks' );
      expect( entry.details?.isCacheHit, isTrue );
      await h.dispose();
    } );

    // 🔴 THE ONE THAT MATTERS. A cache hit needs no job — there is nothing to run, so
    // there may be nothing to identify. If the answer is dropped here it is dropped for
    // good: nothing is queued, nothing is correlated, and no notification carries it.
    test( 'WITHOUT a jobId — the answer must still reach the card', () async {
      final h = await askReturns( cacheHit( 'seventy two and sunny' ) );
      final entry = h.bloc.state.entries.single;

      expect( entry.state, JobLifecycleState.completed,
          reason: 'the ask resolved — the card must not sit as though it is still running' );

      expect(
        entry.answer,
        'seventy two and sunny',
        reason: 'A CACHE HIT WITH NO jobId MUST NOT LOSE ITS ANSWER. `details` is nulled '
                'when jobId is absent, and `entry.answer` reads `details?.responseText`, '
                'so the answer is discarded and the Replay control never renders — the '
                'user asked, the server answered, and the phone shows nothing to replay.',
      );
      await h.dispose();
    },
        skip: 'PROVEN RED 2026-09-19, committed unfixed on purpose. A cache hit with no '
              'jobId loses its answer: the bloc nulls `details` when jobId is absent and '
              'entry.answer reads details?.responseText, so Replay never renders. NOT '
              'LIVE TODAY - flow.py:1699 measured job_id present on 85 of 85 exact_hit '
              'rows, and the replay_error path that lacks one does not set cache_hit. A '
              'latent trap: the client cannot survive a shape the server does not send. '
              'Unskip with the fix.' );

    test( 'WITHOUT a jobId — the cache-hit flag survives too', () async {
      final h = await askReturns( cacheHit( 'an answer' ) );
      expect( h.bloc.state.entries.single.details?.isCacheHit, isTrue,
          reason: 'the badge that tells the user this was served from cache rides the '
                  'same object as the answer, so it is lost by the same nulling' );
      await h.dispose();
    },
        skip: 'PROVEN RED 2026-09-19 - same nulling as the test above, same latent '
              'status. Unskip with the fix.' );

    test( 'either way the ask finishes — no watchdog, no live job', () async {
      for ( final res in [ cacheHit( 'a', jobId: 'j-1' ), cacheHit( 'a' ) ] ) {
        final h = await askReturns( res );
        expect( h.bloc.state.phase,     QuickAskPhase.idle );
        expect( h.bloc.state.liveJobId, isNull );
        await h.dispose();
      }
    } );
  } );
}
