@Tags( [ "live" ] )
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:lupin_mobile/app.dart';
import 'package:lupin_mobile/core/constants/app_constants.dart';
import 'package:lupin_mobile/features/transcript/data/transcript_repository.dart';
import 'package:lupin_mobile/features/transcript/domain/transcript_frame_router.dart';
import 'package:lupin_mobile/features/transcript/domain/transcript_stream_bloc.dart';
import 'package:lupin_mobile/services/websocket/websocket_service.dart';

/// C5.20 — **the cross-repo live arm**: does the SERVER actually send a
/// `cc_transcript_append`, and does it reach a bloc through the real dispatcher `case`?
///
/// 🔴 THIS IS THE ONLY ROW THAT CAN CATCH A FIFTH DEAD ARM, AND NOTHING LOCAL CAN SUBSTITUTE
/// FOR IT. `WsBlocDispatcher.dispatch` already carries four `queue_*_update` arms that have
/// never fired — no emit site exists in the server (§2). A local test proves the arm carries
/// a frame it was handed; only a real server proves a frame is ever handed to it.
/// `transcript_dispatch_test.dart` is the local half and runs on every gate; this is the
/// other half, and the slice report cites both because either alone is green over the bug.
///
/// ⚠️ NOT THE PHONE UI, AND THAT IS STATED RATHER THAN IMPLIED. A full-app `integration_test/`
/// run needs an Android device or emulator, which the venue does not have today, so the widget
/// half stays on the fake socket fed captured frames (C5.1–C5.19). §5: "This is stated as
/// not-yet-automated, not deferred to a human." This file is VM-tier: a real socket, a real
/// dispatcher, a real bloc, and no widgets at all.
///
/// ## How this runs, and how it does NOT run
///
/// **Submit-only, through the venue.** `:8000` is the shared test server; nothing here fires
/// an ad hoc request at it. The runner is
/// `./flutter.sh test --tags live test/live/` with the base URL pointed at the venue's host,
/// scheduled as a test-suite job (§6). Two `--dart-define`s carry what it needs:
///
///   LUPIN_LIVE_BASE   e.g. http://127.0.0.1:8000     (default below)
///   LUPIN_LIVE_SEAT   the seeded seat's stable_session_id
///
/// 🔴 IT IS GATED ON PHASE 1 AND WILL FAIL UNTIL THAT LANDS — deliberately. C9 sequences the
/// mobile `case` after the server's emit site, and this row is how "the emit site exists" gets
/// verified instead of assumed. A timeout here means one of exactly three things, and the
/// failure message says which to check: no emit site, a name mismatch, or a missing `case`.
///
/// **Negative control (C5.20's own):** remove the `cc_transcript_append` case from
/// `app.dart` and this test times out red. That control is the reason the assertion is
/// "a frame arrived" rather than "the socket connected".
void main() {
  const baseUrl = String.fromEnvironment( "LUPIN_LIVE_BASE",
      defaultValue: "http://127.0.0.1:8000" );
  const seat    = String.fromEnvironment( "LUPIN_LIVE_SEAT", defaultValue: "" );

  /// How long to wait for the first frame. The server coalesces at ~300 ms per seat
  /// (ruling Q7), so anything under a second would be a flake generator rather than a test.
  const waitForFirstFrame = Duration( seconds: 20 );

  late WebSocketService      ws;
  late TranscriptFrameRouter router;
  late WsBlocDispatcher      dispatcher;
  /// Nullable, because the guard on `LUPIN_LIVE_SEAT` fails BEFORE the subscribe — and a
  /// `late` field would then turn that clear failure into a LateInitializationError from
  /// tearDown, which is the wrong message about the wrong thing.
  StreamSubscription<dynamic>? frames;

  setUp( () {
    AppConstants.apiBaseUrl = baseUrl;
    AppConstants.wsBaseUrl  = baseUrl.replaceFirst( RegExp( r"^http" ), "ws" );

    router     = TranscriptFrameRouter();
    dispatcher = WsBlocDispatcher();
    ws         = WebSocketService( Dio() );

    GetIt.instance.registerSingleton<TranscriptFrameRouter>( router );
  } );

  tearDown( () async {
    await frames?.cancel();
    await ws.disconnect();
    router.dispose();
    await GetIt.instance.reset();
  } );

  // 🔴 `--exclude-tags pending-capture` DOES NOT EXCLUDE `live`, AND THAT COST A RED GATE.
  // Measured 2026-09-27: this file ran inside the ordinary local gate, tried to open a socket
  // to a server that was not there, and failed — a red line about the venue in a run that has
  // nothing to do with it. The two tags are independent filters; excluding one says nothing
  // about the other, and María's gate command names only the first.
  //
  // ⇒ The seat define is the switch. Without it there is no seat to watch, so the row skips
  // with the reason printed rather than failing. A venue run that FORGETS the define
  // therefore skips too — it does not pass. That is the intended reading: the job report
  // shows a skip, and no slice may claim C5.20 off a skipped row.
  final skipReason = seat.isEmpty
      ? "venue-only: pass --dart-define=LUPIN_LIVE_SEAT=<stable_session_id> (and "
        "LUPIN_LIVE_BASE) and schedule it as a test-suite job. There is no sensible default "
        "seat: watching the wrong one times out exactly like a missing dispatcher case"
      : null;

  test( "a real cc_transcript_append reaches a real bloc through the real case", () async {
    await ws.connect();
    expect( ws.isConnected, isTrue, reason: "no socket, nothing to assert about frames" );

    // 🔴 THE FRAMES GO THROUGH THE DISPATCHER, NOT STRAIGHT TO THE ROUTER. Handing the
    // router the frame here would test this file's own plumbing and leave the `case` — the
    // subject of the row — unexecuted. This is the same subscribe the app does.
    frames = ws.stream.listen( ( raw ) {
      if ( raw is Map ) {
        final data = Map<String, dynamic>.from( raw );
        final type = data[ "type" ];
        if ( type is String ) dispatcher.dispatch( type, data );
      }
    } );

    final bloc = TranscriptStreamBloc(
      ccSessionId : seat,
      repository  : TranscriptRepository( Dio( BaseOptions( baseUrl: baseUrl ) ) ),
      router      : router,
      send        : ws.sendMessage,
    );
    addTearDown( bloc.close );

    final firstAppend = Completer<void>();
    final sub = bloc.stream.listen( ( s ) {
      if ( s.blocks.isNotEmpty && !firstAppend.isCompleted ) firstAppend.complete();
    } );
    addTearDown( sub.cancel );

    // The real open path: subscribe, then become visible, which fetches the backlog over
    // REST and watches from that response's next_offset.
    bloc.start();
    bloc.onPaneVisible();

    await expectLater(
      firstAppend.future.timeout( waitForFirstFrame ),
      completes,
      reason: "no cc_transcript_append reached the bloc within "
              "${ waitForFirstFrame.inSeconds }s. Check, in this order: (1) does the server "
              "emit it at all — phase 1's emit site, which C9 sequences BEFORE this row; "
              "(2) is the name still `${ AppConstants.eventTranscriptAppend }` on both sides, "
              "including `conf/lupin-app.ini` websocket available events; (3) is the `case` "
              "still in WsBlocDispatcher.dispatch. A missing case is this row's own negative "
              "control and times out exactly here",
    );

    expect( bloc.state.lastNextOffset, isNotNull,
        reason: "a frame arrived but carried no next_offset, so the client cannot resume — "
                "§3 requires every append to advance the cursor on a complete-line boundary" );
    expect( bloc.state.refused, isFalse,
        reason: "the seeded seat must be readable by the identity the venue runs as; a "
                "refusal here is a fixture problem, not a client one (ruling Q5 gates the "
                "watch on session_is_admin)" );
  }, timeout: const Timeout( Duration( minutes: 2 ) ), skip: skipReason );
}
