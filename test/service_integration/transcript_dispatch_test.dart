/// 🔴 THE DISPATCHER ARM — a real socket frame reaching a real route-scoped
/// `TranscriptStreamBloc` through the REAL `app.dart` dispatcher.
///
/// **Why this file exists, in one sentence: four arms of that same switch have never fired.**
/// `WsBlocDispatcher.dispatch` carries `queue_todo_update`, `queue_running_update`,
/// `queue_done_update` and `queue_dead_update`, and §2 records the finding — "no emit site
/// exists in the server". F-Clayton-C2 and C9 exist so the transcript arm does not become a
/// fifth, and C5.20 is the row: the live arm drives a real server and asserts a frame
/// arrives. This file is its LOCAL half, and the two answer different questions —
///
///   - **this file**: given a frame of §3's shape, does the arm carry it all the way to a
///     bloc? Runs on every gate, on the VM, with no server.
///   - **C5.20** (`test/live/transcript_wire_live_test.dart`, tag `live`): does the SERVER
///     ever send that frame? Venue-scheduled, and nothing local can answer it.
///
/// ⚠️ A DEAD ARM IS GREEN IN BOTH DIRECTIONS UNTIL BOTH RUN. This file stays green if the
/// server never emits; the live arm stays red if the `case` is missing. Neither is sufficient
/// alone, which is why the slice report cites both rather than one.
///
/// ⇒ Nothing above the repository is substituted: the dispatcher is real, the router is real,
/// the bloc is real, and the frames are the maps §3 pins — `{cc_session_id, file_epoch,
/// offset, next_offset, blocks[], ts}`.
library;

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:lupin_mobile/app.dart';
import 'package:lupin_mobile/core/constants/app_constants.dart';
import 'package:lupin_mobile/features/transcript/data/transcript_repository.dart';
import 'package:lupin_mobile/features/transcript/domain/transcript_frame_router.dart';
import 'package:lupin_mobile/features/transcript/domain/transcript_stream_bloc.dart';

import '../_helpers/transcript_fakes.dart';

/// An append frame exactly as §3's table writes it.
Map<String, dynamic> appendFrame( {
  String id         = "seat-1",
  String epoch      = "epoch-1",
  int    offset     = 100,
  int    nextOffset = 200,
  String text       = "a line off the wire",
} ) => {
  "type"          : AppConstants.eventTranscriptAppend,
  "cc_session_id" : id,
  "file_epoch"    : epoch,
  "offset"        : offset,
  "next_offset"   : nextOffset,
  "blocks"        : [ { "kind": "text", "text": text } ],
  "ts"            : "2026-09-27T21:30:00Z",
};

Map<String, dynamic> stateFrame( {
  String id    = "seat-1",
  String epoch = "epoch-1",
  String state = "live",
} ) => {
  "type"          : AppConstants.eventTranscriptState,
  "cc_session_id" : id,
  "file_epoch"    : epoch,
  "state"         : state,
};

void main() {
  late FakeTranscriptRepository repo;
  late RecordingSender          send;
  late TranscriptFrameRouter    router;
  late FakeLifecycle            lifecycle;
  late WsBlocDispatcher         dispatcher;

  setUp( () {
    repo       = FakeTranscriptRepository();
    send       = RecordingSender();
    router     = TranscriptFrameRouter();
    lifecycle  = FakeLifecycle();
    dispatcher = WsBlocDispatcher();

    // The ONLY registration these arms need: they resolve the router, never a bloc.
    GetIt.instance.registerSingleton<TranscriptFrameRouter>( router );
  } );

  tearDown( () async {
    router.dispose();
    await lifecycle.close();
    await GetIt.instance.reset();
  } );

  Future<_TestBloc> openedConsole( { int nextOffset = 100 } ) async {
    repo.tail = backlog( offset: 0, nextOffset: nextOffset );
    final bloc = _TestBloc( lifecycle: lifecycle, repo: repo, router: router, send: send );
    bloc.start();
    bloc.onPaneVisible();
    await settle();
    return bloc;
  }

  group( "cc_transcript_append", () {
    test( "a frame off the wire lands in the open console's buffer", () async {
      final bloc = await openedConsole();
      final before = bloc.state.blocks.length;

      dispatcher.dispatch( AppConstants.eventTranscriptAppend, appendFrame( offset: 100 ) );
      await settle();

      expect( bloc.state.blocks.length, before + 1,
          reason: "delete the `case` from app.dart and this is the line that fails — which "
                  "is the whole point of the file" );
      expect( bloc.state.blocks.last.text, "a line off the wire" );
      expect( bloc.state.lastNextOffset, 200,
          reason: "the cursor advances, so the next watch resumes where this frame ended" );

      await bloc.close();
    } );

    test( "a frame for a seat with NO open console is dropped, and counted", () async {
      final bloc = await openedConsole();
      final droppedBefore = router.droppedFrames;

      dispatcher.dispatch(
        AppConstants.eventTranscriptAppend, appendFrame( id: "some-other-seat" ) );
      await settle();

      // The belt to the server's braces (C6). If A-T2 ever resolves to `emit_to_user`, the
      // phone's receive-all subscription sees other clients' watched seats — and this is
      // where they stop. `droppedFrames` is the receipt, not diagnostics.
      expect( router.droppedFrames, droppedBefore + 1 );
      expect( bloc.state.blocks.every( ( b ) => b.text != "a line off the wire" ), isTrue,
          reason: "another seat's output must never appear under this seat's heading" );

      await bloc.close();
    } );

    test( "a malformed frame cannot throw out of the dispatcher", () async {
      final bloc = await openedConsole();

      // A socket frame is untrusted input arriving at arbitrary times on a stream shared
      // with every other pane: an exception here would take the whole dispatch down.
      dispatcher.dispatch( AppConstants.eventTranscriptAppend, <String, dynamic>{} );
      dispatcher.dispatch( AppConstants.eventTranscriptAppend,
          { "cc_session_id": "seat-1", "blocks": "not a list" } );
      await settle();

      expect( bloc.state.refused, isFalse );
      await bloc.close();
    } );
  } );

  group( "cc_transcript_state", () {
    test( "an epoch change clears the buffer and re-reads", () async {
      final bloc = await openedConsole();
      expect( bloc.state.blocks, isNotEmpty, reason: "setup: there was a buffer" );
      repo.clearReads();

      dispatcher.dispatch( AppConstants.eventTranscriptState,
          stateFrame( epoch: "epoch-2", state: "rotated" ) );
      await settle();

      expect( repo.reads, isNotEmpty,
          reason: "a byte offset means nothing in a new file, so the client re-fetches "
                  "rather than repairing (§3, item 5)" );
      expect( repo.reads.last.isTail, isTrue,
          reason: "and it re-opens at the LIVE end, not at since_offset=0" );

      await bloc.close();
    } );

    test( "a refused state frame off the wire is FINAL", () async {
      final bloc = await openedConsole();
      send.clear();

      dispatcher.dispatch(
        AppConstants.eventTranscriptState, stateFrame( state: "refused" ) );
      await settle();

      expect( bloc.state.refused, isTrue );
      expect( send.ofType( AppConstants.eventTranscriptWatch ), isEmpty );

      await bloc.close();
    } );
  } );

  group( "auth_success", () {
    test( "an open console re-watches from its last offset and epoch (C5.8)", () async {
      final bloc = await openedConsole();
      repo
        ..clearReads()
        ..since = backlog( epoch: "epoch-1", offset: 100, nextOffset: 450 );
      send.clear();

      dispatcher.dispatch( AppConstants.eventAuthSuccess, <String, dynamic>{} );
      await settle();

      expect( repo.reads.single.isSince, isTrue,
          reason: "a tail read on reconnect would drop everything written while away" );
      final watch = send.ofType( AppConstants.eventTranscriptWatch ).single;
      expect( watch[ "from_offset" ], 450 );

      await bloc.close();
    } );

    test( "a CLOSED console hears nothing, and the arm still cannot throw", () async {
      final bloc = await openedConsole();
      await bloc.close();
      repo.clearReads();
      send.clear();

      dispatcher.dispatch( AppConstants.eventAuthSuccess, <String, dynamic>{} );
      await settle();

      expect( repo.reads, isEmpty,
          reason: "an app-root bloc would catch up here against a screen nobody can see — "
                  "the build C1 forbids and C5.11 fails" );
      expect( send.sent, isEmpty );
    } );
  } );

  test( "the two frame names are the SERVER's strings, not ours", () {
    // 🔴 THE CHEAPEST WAY FOR THIS ARM TO BE DEAD IS A NAME THAT DOES NOT MATCH. §3 pins
    // all four, and `conf/lupin-app.ini`'s `websocket available events` carries them. A
    // rename on either side has to fail somewhere, and a string comparison is the only
    // thing that can fail locally — the server is not here to ask.
    expect( AppConstants.eventTranscriptAppend, "cc_transcript_append" );
    expect( AppConstants.eventTranscriptState,  "cc_transcript_state" );
    expect( AppConstants.eventTranscriptWatch,  "cc_transcript_watch" );
    expect( AppConstants.eventTranscriptUnwatch, "cc_transcript_unwatch" );
  } );
}

class _TestBloc extends TranscriptStreamBloc {
  final FakeLifecycle lifecycle;

  _TestBloc( {
    required this.lifecycle,
    required TranscriptRepository repo,
    required super.router,
    required RecordingSender send,
  } ) : super(
          ccSessionId : "seat-1",
          repository  : repo,
          send        : send.call,
        );

  @override
  Stream<AppLifecycleState> get lifecycleStream => lifecycle.stream;
}

Future<void> settle() async {
  for ( var i = 0; i < 6; i++ ) {
    await Future<void>.delayed( Duration.zero );
  }
}
