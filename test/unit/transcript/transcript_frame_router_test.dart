import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/transcript/data/transcript_models.dart';
import 'package:lupin_mobile/features/transcript/domain/transcript_frame_router.dart';

import '../../_helpers/transcript_fakes.dart';

/// `TranscriptFrameRouter` — the app-root seam, and §5's first belt (C6).
///
/// 🔴 THE PROPERTY UNDER TEST IS A NON-EVENT, WHICH IS WHY THE ROUTER COUNTS. "A frame for a
/// seat with no open route is dropped" cannot be asserted directly: a silent drop is
/// indistinguishable from a router that was never called. `droppedFrames` is the observable
/// that makes C5.11 able to fail.
void main() {
  late TranscriptFrameRouter router;

  setUp( () => router = TranscriptFrameRouter() );
  tearDown( () => router.dispose() );

  test( "a frame reaches the seat that is listening", () async {
    final got = <TranscriptAppend>[];
    final sub = router.appendsFor( "seat-a" ).listen( got.add );
    await _tick();

    router.publishAppend( append( id: "seat-a", offset: 1 ) );
    await _tick();

    expect( got, hasLength( 1 ) );
    expect( got.single.offset, 1 );
    expect( router.droppedFrames, 0 );

    await sub.cancel();
  } );

  test( "the SAME stream comes back for the same id", () async {
    // Two subscribers on one seat — a route re-entered before its predecessor's cancel has
    // settled is exactly that, and a single-subscription stream would throw.
    final a = <TranscriptAppend>[];
    final b = <TranscriptAppend>[];
    final subA = router.appendsFor( "seat-a" ).listen( a.add );
    final subB = router.appendsFor( "seat-a" ).listen( b.add );
    await _tick();

    router.publishAppend( append( id: "seat-a" ) );
    await _tick();

    expect( a, hasLength( 1 ) );
    expect( b, hasLength( 1 ) );

    await subA.cancel();
    await subB.cancel();
  } );

  // 🔴 C5.11's ROUTER HALF. The integration row pops a real route; this one proves the
  // mechanism in isolation, and the counter is what says "dropped" rather than "never
  // arrived".
  test( "a frame for an UNWATCHED seat is dropped and counted", () async {
    final got = <TranscriptAppend>[];
    final sub = router.appendsFor( "seat-a" ).listen( got.add );
    await _tick();

    router.publishAppend( append( id: "seat-b" ) );      // nobody is watching seat-b
    await _tick();

    expect( got, isEmpty );
    expect( router.droppedFrames, 1,
        reason: "§5's belt (C6): if the server ever fans out wider than its watcher set, the "
                "phone's receive-all subscription would see other clients' seats. This drop "
                "is what makes that harmless" );

    await sub.cancel();
  } );

  test( "a frame that arrives AFTER the listener cancels is dropped", () async {
    final got = <TranscriptAppend>[];
    final sub = router.appendsFor( "seat-a" ).listen( got.add );
    await _tick();
    await sub.cancel();
    await _tick();

    router.publishAppend( append( id: "seat-a" ) );
    await _tick();

    expect( got, isEmpty );
    expect( router.droppedFrames, 1 );
    expect( router.isWatched( "seat-a" ), isFalse );
  } );

  // 🔴 THE ONE FAILURE THIS SURFACE MUST NEVER HAVE. A frame with no `cc_session_id` cannot
  // be routed, and "deliver it to the only open console" would show ANOTHER seat's output
  // under this seat's heading. Dropping it is the only safe answer.
  test( "a frame with no cc_session_id is dropped, never guessed at", () async {
    final got = <TranscriptAppend>[];
    final sub = router.appendsFor( "seat-a" ).listen( got.add );
    await _tick();

    router.publishAppend( const TranscriptAppend( offset: 1, nextOffset: 2 ) );
    router.publishState( const TranscriptStateFrame( state: TranscriptStreamState.live ) );
    await _tick();

    expect( got, isEmpty,
        reason: "delivering it to the single open console would put one seat's console under "
                "another seat's name" );
    expect( router.droppedFrames, 2 );

    await sub.cancel();
  } );

  test( "state frames route the same way", () async {
    final got = <TranscriptStateFrame>[];
    final sub = router.statesFor( "seat-a" ).listen( got.add );
    await _tick();

    router.publishState( const TranscriptStateFrame(
      ccSessionId : "seat-a",
      state       : TranscriptStreamState.refused,
    ) );
    router.publishState( const TranscriptStateFrame(
      ccSessionId : "seat-z",
      state       : TranscriptStreamState.live,
    ) );
    await _tick();

    expect( got.single.state, TranscriptStreamState.refused );
    expect( router.droppedFrames, 1 );

    await sub.cancel();
  } );

  test( "isWatched reflects the live listeners", () async {
    expect( router.isWatched( "seat-a" ), isFalse );

    // A stream asked for but not listened to is NOT watched — the getter has to mean "someone
    // is receiving", not "someone once asked".
    router.appendsFor( "seat-a" );
    await _tick();
    expect( router.isWatched( "seat-a" ), isFalse );

    final sub = router.appendsFor( "seat-a" ).listen( ( _ ) {} );
    await _tick();
    expect( router.isWatched( "seat-a" ), isTrue );

    await sub.cancel();
    await _tick();
    expect( router.isWatched( "seat-a" ), isFalse );
  } );

  // ⚠️ WITHOUT `release`, `_appends` GROWS BY ONE ENTRY PER CONSOLE EVER OPENED. Small, but
  // unbounded, and this object lives as long as the app does. The bloc's `close()` calls it.
  test( "release frees the seat's controllers", () async {
    final sub = router.appendsFor( "seat-a" ).listen( ( _ ) {} );
    await _tick();
    expect( router.isWatched( "seat-a" ), isTrue );

    router.release( "seat-a" );
    await _tick();

    expect( router.isWatched( "seat-a" ), isFalse );
    // Publishing after a release is a drop, not a crash.
    router.publishAppend( append( id: "seat-a" ) );
    expect( router.droppedFrames, 1 );

    await sub.cancel();
  } );

  test( "two seats are independent", () async {
    final a = <TranscriptAppend>[];
    final b = <TranscriptAppend>[];
    final subA = router.appendsFor( "seat-a" ).listen( a.add );
    final subB = router.appendsFor( "seat-b" ).listen( b.add );
    await _tick();

    router.publishAppend( append( id: "seat-a", offset: 1 ) );
    router.publishAppend( append( id: "seat-b", offset: 2 ) );
    await _tick();

    expect( a.single.offset, 1 );
    expect( b.single.offset, 2 );
    expect( router.droppedFrames, 0 );

    await subA.cancel();
    await subB.cancel();
  } );
}

Future<void> _tick() => Future<void>.delayed( Duration.zero );
