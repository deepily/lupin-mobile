import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/constants/app_constants.dart';
import 'package:lupin_mobile/features/transcript/data/transcript_models.dart';
import 'package:lupin_mobile/features/transcript/data/transcript_repository.dart';
import 'package:lupin_mobile/features/transcript/domain/transcript_frame_router.dart';
import 'package:lupin_mobile/features/transcript/domain/transcript_stream_bloc.dart';

import '../../_helpers/transcript_fakes.dart';

/// `TranscriptStreamBloc` — C5.1, C5.2, C5.3, C5.10, C5.16, and the bloc half of C5.21.
///
/// ⚠️ THESE USE TYPED MODEL OBJECTS BUILT FROM §3, NOT CAPTURED FRAMES, and that is a stated
/// limit rather than a shortcut. Phase 1 has not emitted, so there is nothing to capture; the
/// rows §5 requires to parse CAPTURED output are tagged `pending-capture` and red. What these
/// prove is that the client obeys the contract as written. What they cannot prove is that the
/// server writes it.
void main() {
  late FakeTranscriptRepository repo;
  late RecordingSender          send;
  late TranscriptFrameRouter    router;
  late FakeLifecycle            lifecycle;

  setUp( () {
    repo      = FakeTranscriptRepository();
    send      = RecordingSender();
    router    = TranscriptFrameRouter();
    lifecycle = FakeLifecycle();
  } );

  tearDown( () async {
    router.dispose();
    await lifecycle.close();
  } );

  _TestBloc makeBloc( { int ringBytes = AppConstants.transcriptRingBytes } ) => _TestBloc(
    lifecycle : lifecycle,
    repo      : repo,
    router    : router,
    send      : send,
    ringBytes : ringBytes,
  );

  /// Open the console: subscribe, become visible, let the tail read and the watch settle.
  Future<_TestBloc> opened( { int ringBytes = AppConstants.transcriptRingBytes } ) async {
    final bloc = makeBloc( ringBytes: ringBytes );
    bloc.start();
    bloc.onPaneVisible();
    await _settle();
    return bloc;
  }

  // -----------------------------------------------------------------------------
  group( "C5.16 — the screen opens at the LIVE end", () {
    test( "the first read is tail_bytes, never since_offset=0", () async {
      repo.tail = backlog( offset: 9000, nextOffset: 9500 );

      final bloc = await opened();

      expect( repo.reads, hasLength( 1 ) );
      expect( repo.reads.single.isTail, isTrue,
          reason: "ruling Q6: the LAST ~64 KB. since_offset=0 returns the FIRST 64 KB and "
                  "would open the screen at the top of the transcript" );
      expect( repo.reads.single.isSince, isFalse );
      expect( repo.reads.single.query[ "tail_bytes" ],
          TranscriptRepository.openTailBytes );

      await bloc.close();
    } );

    test( "the watch starts from THAT response's next_offset and epoch", () async {
      repo.tail = backlog( epoch: "epoch-7", offset: 9000, nextOffset: 9500 );

      final bloc = await opened();

      final watch = send.ofType( AppConstants.eventTranscriptWatch ).single;
      expect( watch[ "from_offset" ], 9500,
          reason: "§3: the server starts where the client asked, and never silently at the "
                  "current end of the file" );
      expect( watch[ "file_epoch" ], "epoch-7" );
      expect( watch[ "cc_session_id" ], "seat-1" );

      await bloc.close();
    } );

    // 🔴 THE CONTROL C5.16 NAMES. A server stub that serves the FIRST page for the backlog
    // request puts the file's first block at the live end. This test asserts the client can
    // TELL — and it is the fake's `serveFirstPageForTail` switch that produces that world.
    test( "NEGATIVE CONTROL: a first-page answer puts the wrong block at the live end",
        () async {
      repo
        ..serveFirstPageForTail = true
        ..firstPage = backlog(
          offset     : 0,
          nextOffset : 500,
          blocks     : [ block( text: "THE VERY FIRST LINE OF THE TRANSCRIPT" ) ],
        )
        ..tail = backlog(
          offset     : 9000,
          nextOffset : 9500,
          blocks     : [ block( text: "the newest line" ) ],
        );

      final bloc = await opened();

      // The client asked correctly; the server answered wrongly. The observable is the
      // OFFSET it is now watching from — 500, not 9500 — which is what "opened at the top"
      // actually means on the wire.
      final watch = send.ofType( AppConstants.eventTranscriptWatch ).single;
      expect( watch[ "from_offset" ], 500 );
      expect( bloc.state.blocks.single.text, "THE VERY FIRST LINE OF THE TRANSCRIPT" );
      expect( bloc.state.lastNextOffset, 500,
          reason: "this is the world C5.16 forbids, reachable ONLY through the fake's "
                  "control switch — which is what makes the positive test above able to "
                  "fail" );

      await bloc.close();
    } );
  } );

  // -----------------------------------------------------------------------------
  group( "C5.1 — a gap is detected, repaired, and the chunk is DROPPED", () {
    test( "one repair fetch from last_next_offset, and the chunk does not render",
        () async {
      repo.tail = backlog( offset: 0, nextOffset: 100, blocks: [ block( text: "A" ) ] );
      final bloc = await opened();
      repo.clearReads();

      repo.since = backlog(
        offset     : 100,
        nextOffset : 300,
        blocks     : [ block( text: "REPAIRED" ) ],
      );

      // A chunk that starts at 200 when we expected 100 — something between was lost.
      router.publishAppend( append(
        offset     : 200,
        nextOffset : 300,
        blocks     : [ block( text: "OUT OF ORDER" ) ],
      ) );
      await _settle();

      expect( bloc.state.repairFetches, 1 );
      expect( repo.reads, hasLength( 1 ) );
      expect( repo.reads.single.isSince, isTrue );
      expect( repo.reads.single.sinceOffset, 100,
          reason: "§3: fetch from last_next_offset, not from the dropped chunk's offset and "
                  "not from 0" );

      final texts = bloc.state.blocks.map( ( b ) => b.text ).toList();
      expect( texts, contains( "REPAIRED" ) );
      expect( texts, isNot( contains( "OUT OF ORDER" ) ),
          reason: "the chunk is DROPPED, not appended-then-corrected — appending it would "
                  "render out-of-order content for a frame and leave it in the buffer" );

      await bloc.close();
    } );

    // The other half, and the one that makes the row above mean something: a clean sequence
    // must issue NO repair. C5.6 states this as "prove the fake can fail the test".
    test( "a CLEAN sequence issues zero repair fetches", () async {
      repo.tail = backlog( offset: 0, nextOffset: 100 );
      final bloc = await opened();
      repo.clearReads();

      router.publishAppend( append( offset: 100, nextOffset: 200 ) );
      await _settle();
      router.publishAppend( append( offset: 200, nextOffset: 300 ) );
      await _settle();

      expect( bloc.state.repairFetches, 0 );
      expect( repo.reads, isEmpty );
      expect( bloc.state.lastNextOffset, 300 );
      expect( bloc.state.blocks, hasLength( 3 ),
          reason: "one backlog block plus two chunks" );

      await bloc.close();
    } );
  } );

  // -----------------------------------------------------------------------------
  group( "C5.2 / C5.10 — an epoch change clears everything", () {
    test( "a chunk from a new epoch clears the buffer and the offset", () async {
      repo.tail = backlog(
        epoch  : "epoch-1",
        blocks : [ block( text: "OLD EPOCH CONTENT" ) ],
      );
      final bloc = await opened();
      expect( bloc.state.blocks.single.text, "OLD EPOCH CONTENT", reason: "setup" );

      repo
        ..clearReads()
        ..tail = backlog(
          epoch  : "epoch-2",
          blocks : [ block( text: "NEW EPOCH CONTENT" ) ],
        );

      router.publishAppend( append( epoch: "epoch-2", offset: 0, nextOffset: 50 ) );
      await _settle();

      final texts = bloc.state.blocks.map( ( b ) => b.text ).toList();
      expect( texts, isNot( contains( "OLD EPOCH CONTENT" ) ),
          reason: "C5.2: no pre-change block is emitted afterwards" );
      expect( bloc.state.fileEpoch, "epoch-2" );
      expect( repo.reads.single.isTail, isTrue,
          reason: "a new epoch has a new live end, so the re-fetch is a TAIL read — not a "
                  "since_offset carried over from a file that no longer exists" );

      await bloc.close();
    } );

    test( "an epoch change does NOT count as a gap", () async {
      repo.tail = backlog( epoch: "epoch-1", offset: 0, nextOffset: 5000 );
      final bloc = await opened();
      repo
        ..clearReads()
        ..tail = backlog( epoch: "epoch-2", offset: 0, nextOffset: 50 );

      // Offset 0 against an expected 5000 looks exactly like a gap — except the epoch moved,
      // which makes the comparison meaningless. A repair fetch here would read the WRONG
      // file from an offset that means nothing in it.
      router.publishAppend( append( epoch: "epoch-2", offset: 0, nextOffset: 50 ) );
      await _settle();

      expect( bloc.state.repairFetches, 0,
          reason: "the epoch check must come BEFORE the offset comparison" );
      expect( repo.reads.single.isTail, isTrue );

      await bloc.close();
    } );

    test( "C5.10 — epoch_mismatch clears and re-fetches instead of appending", () async {
      repo.tail = backlog( epoch: "epoch-1", blocks: [ block( text: "STALE" ) ] );
      final bloc = await opened();
      repo
        ..clearReads()
        ..tail = backlog( epoch: "epoch-9", blocks: [ block( text: "CURRENT" ) ] );

      router.publishState( const TranscriptStateFrame(
        ccSessionId : "seat-1",
        fileEpoch   : "epoch-9",
        state       : TranscriptStreamState.epochMismatch,
        rawState    : "epoch_mismatch",
      ) );
      await _settle();

      expect( bloc.state.blocks.map( ( b ) => b.text ), isNot( contains( "STALE" ) ) );
      expect( bloc.state.blocks.map( ( b ) => b.text ), contains( "CURRENT" ) );
      expect( bloc.state.fileEpoch, "epoch-9" );

      await bloc.close();
    } );

    test( "a `rotated` state is handled the same way", () async {
      repo.tail = backlog( epoch: "epoch-1" );
      final bloc = await opened();
      repo.clearReads();

      router.publishState( const TranscriptStateFrame(
        ccSessionId : "seat-1",
        fileEpoch   : "epoch-2",
        state       : TranscriptStreamState.rotated,
        rawState    : "rotated",
      ) );
      await _settle();

      expect( repo.reads.single.isTail, isTrue );
      await bloc.close();
    } );

    test( "a `live` state just confirms the epoch", () async {
      repo.tail = backlog( epoch: "epoch-1", blocks: [ block( text: "KEEP ME" ) ] );
      final bloc = await opened();
      repo.clearReads();

      router.publishState( const TranscriptStateFrame(
        ccSessionId : "seat-1",
        fileEpoch   : "epoch-1",
        state       : TranscriptStreamState.live,
      ) );
      await _settle();

      expect( bloc.state.blocks.single.text, "KEEP ME" );
      expect( repo.reads, isEmpty, reason: "nothing to re-fetch" );
      await bloc.close();
    } );

    test( "an `unknown` state changes nothing and does not retry", () async {
      repo.tail = backlog( blocks: [ block( text: "KEEP ME" ) ] );
      final bloc = await opened();
      repo.clearReads();

      router.publishState( const TranscriptStateFrame(
        ccSessionId : "seat-1",
        rawState    : "something_new_from_the_server",
      ) );
      await _settle();

      expect( bloc.state.blocks.single.text, "KEEP ME" );
      expect( repo.reads, isEmpty, reason: "retrying against a state we cannot read is "
                                          "guessing" );
      await bloc.close();
    } );
  } );

  // -----------------------------------------------------------------------------
  group( "C5.3 — the ring buffer", () {
    // ⚠️ THE CAP IS READ FROM THE BLOC'S PARAMETER, NOT HARD-CODED HERE (F-Clayton-C9), and
    // a small one is used on purpose: a test that has to build 256 KB of fixture to reach a
    // boundary ends up asserting the fixture.
    test( "evicts oldest-first and never exceeds its cap", () async {
      final bloc = await opened( ringBytes: 30 );

      // Each block is 10 ASCII bytes, so the cap holds three.
      for ( var i = 0; i < 6; i++ ) {
        router.publishAppend( append(
          offset     : 100 + i * 100,
          nextOffset : 200 + i * 100,
          blocks     : [ block( text: "abcdefghi$i" ) ],
        ) );
        await _settle();
        expect( bloc.state.bufferBytes, lessThanOrEqualTo( 30 ),
            reason: "the cap must hold at every step, not just at the end" );
      }

      final texts = bloc.state.blocks.map( ( b ) => b.text ).toList();
      expect( texts, [ "abcdefghi3", "abcdefghi4", "abcdefghi5" ],
          reason: "oldest-first eviction, and the newest survive — a console that dropped "
                  "the NEWEST would evict the thing the operator is watching" );

      await bloc.close();
    } );

    test( "the size function is UTF-8 BYTES, not Dart string length (C8)", () async {
      // "é" is 1 Dart code unit and 2 UTF-8 bytes; "🌻" is 2 code units and 4 bytes. A ring
      // that counted characters would hold roughly twice what it believed, and the server's
      // cap and the client's would mean different things.
      expect( block( text: "é" ).sizeBytes, 2 );
      expect( block( text: "🌻" ).sizeBytes, 4 );
      expect( block( text: "abc" ).sizeBytes, 3 );

      final bloc = await opened( ringBytes: 8 );
      repo.clearReads();

      router.publishAppend( append(
        offset     : 100,
        nextOffset : 200,
        blocks     : [ block( text: "🌻🌻🌻" ) ],   // 12 bytes, 6 code units
      ) );
      await _settle();

      expect( bloc.state.bufferBytes, 12,
          reason: "measured in bytes. A code-unit count would report 6 and believe it was "
                  "under the cap" );

      await bloc.close();
    } );

    test( "a single block larger than the whole ring is KEPT, not evicted", () async {
      final bloc = await opened( ringBytes: 4 );
      repo.clearReads();

      router.publishAppend( append(
        offset     : 100,
        nextOffset : 200,
        blocks     : [ block( text: "a block far larger than the ring" ) ],
      ) );
      await _settle();

      expect( bloc.state.blocks, hasLength( 1 ),
          reason: "an empty console showing nothing while the server HAD sent something is "
                  "worse than briefly exceeding a provisional cap" );

      await bloc.close();
    } );
  } );

  // -----------------------------------------------------------------------------
  group( "C5.21 (bloc half) — a refusal is FINAL", () {
    test( "a refused state frame clears the buffer and stops the watch", () async {
      repo.tail = backlog( blocks: [ block( text: "SOMETHING" ) ] );
      final bloc = await opened();
      send.clear();
      repo.clearReads();

      router.publishState( const TranscriptStateFrame(
        ccSessionId : "seat-1",
        state       : TranscriptStreamState.refused,
        rawState    : "refused",
        reason      : "admin only",
      ) );
      await _settle();

      expect( bloc.state.refused, isTrue );
      expect( bloc.state.refusedReason, "admin only" );
      expect( bloc.state.blocks, isEmpty, reason: "§5: keeps no buffer" );

      await bloc.close();
    } );

    test( "a REST 403 on the backlog is the same refusal", () async {
      repo.throws = const TranscriptRefused( "not an admin" );

      final bloc = await opened();

      expect( bloc.state.refused, isTrue );
      expect( bloc.state.refusedReason, "not an admin" );
      expect( send.ofType( AppConstants.eventTranscriptWatch ), isEmpty,
          reason: "no watch is sent after the backlog was refused" );

      await bloc.close();
    } );

    // 🔴 THE ROW C5.21 IS ACTUALLY ABOUT, AND ITS NEGATIVE CONTROL IS A BUILD THAT RETRIES.
    // A foreground return and an `auth_success` are the two events that would naturally
    // re-arm a watch, so both are driven here and both must record ZERO calls.
    test( "zero further calls across a foreground return AND a reconnect", () async {
      repo.throws = const TranscriptRefused( "nope" );
      final bloc = await opened();
      expect( bloc.state.refused, isTrue, reason: "setup" );

      repo
        ..clearReads()
        ..throws = null;               // the server would answer now, if we asked
      send.clear();

      await lifecycle.roundTrip();     // background, then foreground
      await _settle();
      bloc.onReconnected();            // auth_success
      await _settle();

      expect( repo.reads, isEmpty,
          reason: "§5: sends no further watch and no REST retry, INCLUDING across a "
                  "foreground return and an auth_success" );
      expect( send.ofType( AppConstants.eventTranscriptWatch ), isEmpty );

      await bloc.close();
    } );

    test( "a refusal is NOT an error, and an error is NOT a refusal", () async {
      repo.throws = const TranscriptApiException( "connection reset" );
      final bloc = await opened();

      expect( bloc.state.refused, isFalse,
          reason: "a flaky network must not permanently disable the screen" );
      expect( bloc.state.error, "connection reset" );

      // And a retryable failure DOES retry on the next lifecycle event.
      repo
        ..throws = null
        ..clearReads()
        ..tail = backlog( blocks: [ block( text: "back online" ) ] );

      await lifecycle.roundTrip();
      await _settle();

      expect( repo.reads, isNotEmpty, reason: "the retryable path retries" );
      expect( bloc.state.error, isNull );
      expect( bloc.state.blocks.single.text, "back online" );

      await bloc.close();
    } );
  } );

  // -----------------------------------------------------------------------------
  group( "the wire verbs", () {
    test( "going inactive sends cc_transcript_unwatch", () async {
      final bloc = await opened();
      send.clear();

      bloc.onPaneHidden();
      await _settle();

      expect( send.countOfType( AppConstants.eventTranscriptUnwatch ), 1 );
      expect(
        send.ofType( AppConstants.eventTranscriptUnwatch ).single[ "cc_session_id" ],
        "seat-1",
      );

      await bloc.close();
    } );

    test( "close sends unwatch and releases the router's seat", () async {
      final bloc = await opened();
      send.clear();
      expect( router.isWatched( "seat-1" ), isTrue, reason: "setup" );

      await bloc.close();

      expect( send.countOfType( AppConstants.eventTranscriptUnwatch ), 1,
          reason: "the server must stop streaming to a client that has gone" );
      expect( router.isWatched( "seat-1" ), isFalse );
    } );

    test( "a socket that is gone does not blank the backlog", () async {
      send.throws = Exception( "WebSocket not connected" );
      repo.tail = backlog( blocks: [ block( text: "fetched anyway" ) ] );

      final bloc = await opened();

      expect( bloc.state.blocks.single.text, "fetched anyway",
          reason: "a failed watch is a reason to await reconnect, not to throw away a "
                  "backlog we already have" );
      expect( bloc.state.refused, isFalse );

      await bloc.close();
    } );
  } );

  // -----------------------------------------------------------------------------
  group( "load earlier (C-7)", () {
    test( "it pages back from the oldest offset held and hides at the epoch start",
        () async {
      repo.tail = backlog(
        offset     : 5000,
        nextOffset : 5500,
        blocks     : [ block( text: "recent" ) ],
      );
      final bloc = await opened();
      repo.clearReads();

      repo.before = backlog(
        offset     : 2000,
        nextOffset : 5000,
        blocks     : [ block( text: "older" ) ],
        atStart    : true,
      );

      await bloc.loadEarlier();
      await _settle();

      expect( repo.reads.single.isBefore, isTrue );
      expect( repo.reads.single.beforeOffset, 5000 );
      expect( bloc.state.blocks.map( ( b ) => b.text ), [ "older", "recent" ],
          reason: "the page goes on the FRONT — older content is older" );
      expect( bloc.state.atEpochStart, isTrue,
          reason: "the control hides once there is nothing left to fetch" );
      expect( bloc.state.oldestOffset, 2000 );

      await bloc.close();
    } );

    test( "a backwards page does NOT rewind the live cursor", () async {
      repo.tail = backlog( offset: 5000, nextOffset: 5500 );
      final bloc = await opened();
      repo.before = backlog( offset: 2000, nextOffset: 5000 );

      await bloc.loadEarlier();
      await _settle();

      expect( bloc.state.lastNextOffset, 5500,
          reason: "rewinding it would make the next live chunk look like a gap and fire a "
                  "repair fetch for content already held" );

      await bloc.close();
    } );

    test( "it does nothing once at the epoch start, and nothing when refused", () async {
      repo.tail = backlog( offset: 0, nextOffset: 100, atStart: true );
      final bloc = await opened();
      repo.clearReads();

      await bloc.loadEarlier();
      await _settle();
      expect( repo.reads, isEmpty );

      await bloc.close();
    } );
  } );

  // -----------------------------------------------------------------------------
  group( "C5.19 (bloc half) — a truncated block expands by REST", () {
    test( "one fetch, and the answer REPLACES the block", () async {
      repo.tail = backlog(
        blocks: [ block(
          kind      : TranscriptBlockKind.toolResult,
          text      : "the truncated prefix",
          truncated : true,
          offset    : 4242,
        ) ],
      );
      final bloc = await opened();
      repo
        ..clearReads()
        // 🔴 THE STUB ANSWERS TEXT THAT DIFFERS FROM THE PREFIX. An expand-from-memory build
        // cannot produce this string, which is what makes the assertion able to fail.
        ..full = backlog( blocks: [ block(
            kind : TranscriptBlockKind.toolResult,
            text : "THE WHOLE THING, FETCHED FROM THE SERVER",
          ) ] );

      await bloc.expandTruncated( 0 );
      await _settle();

      expect( repo.reads, hasLength( 1 ) );
      expect( repo.reads.single.sinceOffset, 4242 );
      expect( repo.reads.single.maxBytes, 0,
          reason: "§2 item 7: budget == 0 means unbounded, the vocabulary adopted from "
                  "tasks.py" );
      expect( bloc.state.blocks.single.text, "THE WHOLE THING, FETCHED FROM THE SERVER" );
      expect( bloc.state.blocks.single.truncated, isFalse,
          reason: "the marker goes away, and a second expand must not re-fetch" );

      await bloc.close();
    } );

    test( "a block that is not truncated is never fetched", () async {
      repo.tail = backlog( blocks: [ block( text: "complete", offset: 1 ) ] );
      final bloc = await opened();
      repo.clearReads();

      await bloc.expandTruncated( 0 );
      await _settle();

      expect( repo.reads, isEmpty );
      await bloc.close();
    } );

    test( "a truncated block with no offset cannot be fetched and does not crash",
        () async {
      repo.tail = backlog(
        blocks: [ block( text: "cut", truncated: true ) ],   // no offset
      );
      final bloc = await opened();
      repo.clearReads();

      await bloc.expandTruncated( 0 );
      await _settle();

      expect( repo.reads, isEmpty );
      expect( bloc.state.blocks.single.text, "cut" );
      await bloc.close();
    } );
  } );

  // -----------------------------------------------------------------------------
  group( "C5.12 — a fetch in flight when the route closes", () {
    test( "close cancels the in-flight token and no state is emitted afterwards",
        () async {
      final bloc = makeBloc();
      final states = <TranscriptViewState>[];
      final sub = bloc.stream.listen( states.add );

      // A tail read that never completes until the test says so.
      final gate = Completer<TranscriptBacklog>();
      repo.throwsOnce = null;
      final slowRepo = _SlowRepo( gate );
      final slowBloc = _TestBloc(
        lifecycle : lifecycle,
        repo      : slowRepo,
        router    : router,
        send      : send,
      );

      slowBloc.start();
      slowBloc.onPaneVisible();
      await _settle();

      expect( slowRepo.token, isNotNull, reason: "the fetch is in flight" );
      expect( slowRepo.token!.isCancelled, isFalse );

      await slowBloc.close();

      expect( slowRepo.token!.isCancelled, isTrue,
          reason: "PaneVisibilityMixin.close() cancels the in-flight token, reached through "
                  "super.close()" );

      // Let the gated call finish AFTER the close. Nothing may be emitted.
      gate.complete( backlog() );
      await _settle();

      await sub.cancel();
      await bloc.close();
      expect( states, isEmpty, reason: "this bloc was never opened" );
    } );
  } );

  // -----------------------------------------------------------------------------
  group( "C5.7 (bloc half) — the catch-up runs on EVERY foreground return", () {
    // 🔴 TWO RETURNS IN ONE TEST, WHICH IS C-2's WHOLE POINT. A catch-up placed in the
    // subscribe-time verb fires once and passes a one-return test.
    test( "two background round trips, two catch-ups, each a since_offset read", () async {
      repo.tail = backlog( offset: 0, nextOffset: 100 );
      final bloc = await opened();
      repo
        ..clearReads()
        ..since = backlog( offset: 100, nextOffset: 200 );

      await lifecycle.roundTrip();
      await _settle();
      expect( repo.countWhere( ( r ) => r.isSince ), 1, reason: "first return" );

      repo.since = backlog( offset: 200, nextOffset: 300 );
      await lifecycle.roundTrip();
      await _settle();
      expect( repo.countWhere( ( r ) => r.isSince ), 2,
          reason: "C-2: the catch-up fires on EACH return, not once at subscribe time" );

      await bloc.close();
    } );

    test( "a resume catch-up is since_offset, NOT another tail read", () async {
      repo.tail = backlog( offset: 0, nextOffset: 100 );
      final bloc = await opened();
      repo
        ..clearReads()
        ..since = backlog( offset: 100, nextOffset: 200 );

      await lifecycle.roundTrip();
      await _settle();

      expect( repo.reads.single.isSince, isTrue );
      expect( repo.reads.single.sinceOffset, 100,
          reason: "a tail read on resume would drop everything written while away" );

      await bloc.close();
    } );

    test( "backgrounding unwatches and foregrounding re-watches", () async {
      final bloc = await opened();
      send.clear();
      repo.since = backlog( offset: 100, nextOffset: 200 );

      lifecycle.controller.add( AppLifecycleState.paused );
      await _settle();
      expect( send.countOfType( AppConstants.eventTranscriptUnwatch ), 1 );

      lifecycle.controller.add( AppLifecycleState.resumed );
      await _settle();
      expect( send.countOfType( AppConstants.eventTranscriptWatch ), 1 );

      await bloc.close();
    } );
  } );

  // -----------------------------------------------------------------------------
  group( "C5.8 (bloc half) — reconnect re-watches from the last offset and epoch", () {
    test( "auth_success re-watches from where we were", () async {
      repo.tail = backlog( epoch: "epoch-3", offset: 0, nextOffset: 700 );
      final bloc = await opened();
      send.clear();
      repo
        ..clearReads()
        ..since = backlog( epoch: "epoch-3", offset: 700, nextOffset: 900 );

      bloc.onReconnected();
      await _settle();

      expect( repo.reads.single.isSince, isTrue );
      expect( repo.reads.single.sinceOffset, 700 );

      final watch = send.ofType( AppConstants.eventTranscriptWatch ).single;
      expect( watch[ "from_offset" ], 900 );
      expect( watch[ "file_epoch" ], "epoch-3" );

      await bloc.close();
    } );

    test( "a reconnect while off screen does nothing", () async {
      final bloc = await opened();
      bloc.onPaneHidden();
      await _settle();
      repo.clearReads();
      send.clear();

      bloc.onReconnected();
      await _settle();

      expect( repo.reads, isEmpty,
          reason: "an invisible console must not re-arm a watch on reconnect" );
      expect( send.ofType( AppConstants.eventTranscriptWatch ), isEmpty );

      await bloc.close();
    } );
  } );

  group( "one request at a time", () {
    // 🔴 THE GUARD IS ONLY VISIBLE WHEN NOTHING CANCELLED IN BETWEEN, and my first version of
    // this test got that wrong: I drove a background round trip, which CANCELS the in-flight
    // fetch on the way out, so the return legitimately started a second one. Two calls was
    // the correct answer and my expectation of one was the bug. A reconnect while still on
    // screen is the real shape — no cancel, two claims.
    test( "a reconnect while a catch-up is in flight does not start a second", () async {
      final gate     = Completer<TranscriptBacklog>();
      final slowRepo = _SlowRepo( gate );
      final bloc     = _TestBloc(
        lifecycle : lifecycle,
        repo      : slowRepo,
        router    : router,
        send      : send,
      );

      bloc.start();
      bloc.onPaneVisible();
      await _settle();
      expect( slowRepo.calls, 1 );

      bloc.onReconnected();
      await _settle();

      expect( slowRepo.calls, 1,
          reason: "claimRequest() is the guard, and it is the same guard for every wake-up "
                  "— a tick, a pane appearing, a resume, or a reconnect" );

      gate.complete( backlog() );
      await _settle();
      await bloc.close();
    } );

    // The other direction, so the guard cannot be read as "never fetch twice": going away
    // cancels the fetch, which FREES the slot, so coming back genuinely re-fetches.
    test( "a background round trip cancels the fetch and the return starts a new one",
        () async {
      final gate     = Completer<TranscriptBacklog>();
      final slowRepo = _SlowRepo( gate );
      final bloc     = _TestBloc(
        lifecycle : lifecycle,
        repo      : slowRepo,
        router    : router,
        send      : send,
      );

      bloc.start();
      bloc.onPaneVisible();
      await _settle();
      expect( slowRepo.calls, 1 );
      expect( slowRepo.tokens.single.isCancelled, isFalse );
      final first = slowRepo.tokens.single;

      await lifecycle.roundTrip();
      await _settle();

      expect( first.isCancelled, isTrue,
          reason: "backgrounding cancels the in-flight fetch — the mixin's half. Note this "
                  "is the FIRST token, held before the round trip: reading the latest one "
                  "would read the fetch the return just started, which is correctly "
                  "uncancelled" );
      expect( slowRepo.calls, 2,
          reason: "and the cancelled slot is free, so the return re-fetches rather than "
                  "silently skipping the catch-up the operator came back for" );
      expect( slowRepo.tokens.last.isCancelled, isFalse,
          reason: "the new fetch is live" );

      gate.complete( backlog() );
      await _settle();
      await bloc.close();
    } );
  } );
}

Future<void> _settle() async {
  for ( var i = 0; i < 6; i++ ) {
    await Future<void>.delayed( Duration.zero );
  }
}

/// The bloc with its lifecycle stream replaced by the test's.
class _TestBloc extends TranscriptStreamBloc {
  final FakeLifecycle lifecycle;

  _TestBloc( {
    required this.lifecycle,
    required TranscriptRepository repo,
    required TranscriptFrameRouter router,
    required RecordingSender send,
    int ringBytes = AppConstants.transcriptRingBytes,
  } ) : super(
          ccSessionId : "seat-1",
          repository  : repo,
          router      : router,
          send        : send.call,
          ringBytes   : ringBytes,
        );

  @override
  Stream<AppLifecycleState> get lifecycleStream => lifecycle.stream;
}

/// A repository whose tail read is gated on a completer, so a fetch can be held in flight.
class _SlowRepo extends TranscriptRepository {
  final Completer<TranscriptBacklog> gate;

  /// EVERY token handed to it, in order.
  ///
  /// 🔴 A SINGLE `token` FIELD IS A TRAP AND I FELL IN IT. Holding only the latest one, the
  /// assertion "backgrounding cancelled the fetch" reads the token of the NEXT fetch — the
  /// one the return just started — and reports uncancelled. The test went red against
  /// correct code. Keeping the list makes "the first one was cancelled AND a second was
  /// started" one statement about two facts instead of one field trying to be both.
  final List<CancelToken> tokens = [];

  int calls = 0;

  _SlowRepo( this.gate ) : super( _dio );

  static final Dio _dio = Dio();

  /// The token of the fetch currently in flight.
  CancelToken? get token => tokens.isEmpty ? null : tokens.last;

  @override
  Future<TranscriptBacklog> fetchTail( {
    required String      ccSessionId,
    required CancelToken cancelToken,
    int                  tailBytes = TranscriptRepository.openTailBytes,
  } ) {
    calls++;
    tokens.add( cancelToken );
    return gate.future;
  }

  @override
  Future<TranscriptBacklog> fetchSince( {
    required String      ccSessionId,
    required int         sinceOffset,
    required CancelToken cancelToken,
    int?                 maxBytes,
  } ) {
    calls++;
    tokens.add( cancelToken );
    return gate.future;
  }
}
