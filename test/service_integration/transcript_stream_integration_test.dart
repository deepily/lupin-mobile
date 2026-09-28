import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/constants/app_constants.dart';
import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/transcript/data/transcript_models.dart';
import 'package:lupin_mobile/features/transcript/data/transcript_repository.dart';
import 'package:lupin_mobile/features/transcript/domain/transcript_frame_router.dart';
import 'package:lupin_mobile/features/transcript/domain/transcript_stream_bloc.dart';
import 'package:lupin_mobile/features/transcript/presentation/live_console_screen.dart';

import '../_helpers/transcript_fakes.dart';

/// The Live Console end to end over a fake socket and a fake REST layer — C5.6, C5.7, C5.8,
/// C5.11 and C5.12.
///
/// 🔴 THESE DRIVE A REAL ROUTE, WHICH IS THE POINT. The bloc tests next door prove the
/// reducers; these prove the wiring that carries a frame from the router, through a
/// route-scoped bloc, onto a screen — and, more importantly, prove what happens when the
/// route GOES AWAY. C5.11's whole subject is a non-event, and only a real route can produce
/// it.
///
/// ⚠️ NO `pumpAndSettle`. A console with live async work never reaches a quiescent frame.
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
    repo.tail = backlog( offset: 0, nextOffset: 100, blocks: [ block( text: "opening" ) ] );
  } );

  tearDown( () async {
    router.dispose();
    await lifecycle.close();
  } );

  Future<void> settle( WidgetTester tester, { int frames = 6 } ) async {
    for ( var i = 0; i < frames; i++ ) {
      await tester.pump( const Duration( milliseconds: 10 ) );
    }
  }

  /// A host that can push the console route and pop it — which is what C5.11 and C5.12 need.
  Future<void> pumpHost( WidgetTester tester ) async {
    tester.view.physicalSize     = const Size( 360, 800 );
    tester.view.devicePixelRatio = 1.0;
    addTearDown( tester.view.resetPhysicalSize );
    addTearDown( tester.view.resetDevicePixelRatio );

    await tester.pumpWidget( MaterialApp(
      home: Builder(
        builder: ( context ) => Scaffold(
          body: Center(
            child: ElevatedButton(
              child     : const Text( "open console" ),
              onPressed : () => Navigator.of( context ).push( MaterialPageRoute<void>(
                builder: ( _ ) => LiveConsoleScreen(
                  ccSessionId : "seat-1",
                  whoLabel    : "maya",
                  blocFactory : ( _ ) => _TestBloc(
                    lifecycle : lifecycle,
                    repo      : repo,
                    router    : router,
                    send      : send,
                  ),
                ),
              ) ),
            ),
          ),
        ),
      ),
    ) );
  }

  Future<void> openConsole( WidgetTester tester ) async {
    await tester.tap( find.text( "open console" ) );
    await tester.pump();
    await tester.pump( const Duration( milliseconds: 400 ) );   // run the transition out
    await settle( tester );
  }

  Future<void> popConsole( WidgetTester tester ) async {
    final open = find.byType( LiveConsoleScreen );
    Navigator.of( tester.element( open ) ).pop();
    await tester.pump();
    await tester.pump( const Duration( milliseconds: 400 ) );
    await settle( tester );
  }

  // ---------------------------------------------------------------------------
  group( "C5.6 — a fake socket with a deliberate gap fires the REST repair", () {
    testWidgets( "the gap is repaired and the repaired content renders", ( tester ) async {
      await pumpHost( tester );
      await openConsole( tester );
      repo
        ..clearReads()
        ..since = backlog(
          offset     : 100,
          nextOffset : 400,
          blocks     : [ block( text: "REPAIRED CONTENT" ) ],
        );

      // Expected 100, arrives at 300: something between was lost.
      router.publishAppend( append(
        offset     : 300,
        nextOffset : 400,
        blocks     : [ block( text: "dropped chunk" ) ],
      ) );
      await settle( tester );

      expect( repo.countWhere( ( r ) => r.isSince ), 1 );
      expect( repo.reads.single.sinceOffset, 100 );
      expect( find.textContaining( "REPAIRED CONTENT", findRichText: true ), findsWidgets );
      expect( find.textContaining( "dropped chunk", findRichText: true ), findsNothing );

      await popConsole( tester );
    } );

    // 🔴 C5.6 SAYS IT IN AS MANY WORDS: "Prove the fake can fail the test: feed a clean
    // sequence and assert no repair fetch happens." Without this row, a bloc that repaired on
    // EVERY chunk would pass the row above.
    testWidgets( "a clean sequence fires NO repair fetch", ( tester ) async {
      await pumpHost( tester );
      await openConsole( tester );
      repo.clearReads();

      router.publishAppend( append( offset: 100, nextOffset: 200 ) );
      await settle( tester );
      router.publishAppend( append( offset: 200, nextOffset: 300 ) );
      await settle( tester );
      router.publishAppend( append( offset: 300, nextOffset: 400 ) );
      await settle( tester );

      expect( repo.reads, isEmpty,
          reason: "three contiguous chunks and not one repair — otherwise the row above is "
                  "asserting a fetch that always happens" );

      await popConsole( tester );
    } );
  } );

  // ---------------------------------------------------------------------------
  group( "C5.7 — background unwatches, foreground catches up then re-watches", () {
    // 🔴 TWO FOREGROUND RETURNS IN ONE TEST (C-2). A catch-up placed in the subscribe-time
    // verb fires once and passes a one-return test, which is exactly the shape the plan warns
    // about. And it is driven through the OVERRIDDEN `lifecycleStream`, never by calling the
    // bloc's methods — the singleton is never faked.
    testWidgets( "the catch-up fires on EACH of two returns", ( tester ) async {
      await pumpHost( tester );
      await openConsole( tester );
      repo
        ..clearReads()
        ..since = backlog( offset: 100, nextOffset: 200 );
      send.clear();

      // Return one.
      lifecycle.controller.add( AppLifecycleState.paused );
      await settle( tester );
      expect( send.countOfType( AppConstants.eventTranscriptUnwatch ), 1,
          reason: "backgrounding tells the server to stop" );

      lifecycle.controller.add( AppLifecycleState.resumed );
      await settle( tester );
      expect( repo.countWhere( ( r ) => r.isSince ), 1, reason: "return one: catch-up" );
      expect( send.countOfType( AppConstants.eventTranscriptWatch ), 1,
          reason: "return one: re-watch" );

      // Return two.
      repo.since = backlog( offset: 200, nextOffset: 300 );
      lifecycle.controller.add( AppLifecycleState.paused );
      await settle( tester );
      lifecycle.controller.add( AppLifecycleState.resumed );
      await settle( tester );

      expect( repo.countWhere( ( r ) => r.isSince ), 2,
          reason: "C-2: the catch-up runs on EVERY return, not once at subscribe time" );
      expect( send.countOfType( AppConstants.eventTranscriptWatch ), 2 );
      expect( send.countOfType( AppConstants.eventTranscriptUnwatch ), 2 );

      await popConsole( tester );
    } );

    // ⚠️ "Only meaningful together with C5.11": on an app-root bloc this test goes green over
    // a watch that never closes (C1). That is why the pair is run in one file.
    testWidgets( "the catch-up is since_offset, and the watch resumes from its next_offset",
        ( tester ) async {
      await pumpHost( tester );
      await openConsole( tester );
      repo
        ..clearReads()
        ..since = backlog( epoch: "epoch-1", offset: 100, nextOffset: 250 );
      send.clear();

      await lifecycle.roundTrip();
      await settle( tester );

      expect( repo.reads.single.isSince, isTrue,
          reason: "a tail read on resume would drop everything written while away" );
      expect( repo.reads.single.sinceOffset, 100 );

      final watch = send.ofType( AppConstants.eventTranscriptWatch ).single;
      expect( watch[ "from_offset" ], 250 );
      expect( watch[ "file_epoch" ], "epoch-1" );

      await popConsole( tester );
    } );
  } );

  // ---------------------------------------------------------------------------
  group( "C5.8 — on auth_success after a drop, the open screen re-watches", () {
    testWidgets( "a reconnect re-watches from the last offset and epoch", ( tester ) async {
      repo.tail = backlog( epoch: "epoch-5", offset: 0, nextOffset: 800 );
      await pumpHost( tester );
      await openConsole( tester );
      repo
        ..clearReads()
        ..since = backlog( epoch: "epoch-5", offset: 800, nextOffset: 950 );
      send.clear();

      // `WsBlocDispatcher` calls this on an `auth_success` frame — the same seam the four
      // pane blocs' reconnect re-hydration uses.
      _consoleBloc( tester ).onReconnected();
      await settle( tester );

      expect( repo.reads.single.sinceOffset, 800 );
      final watch = send.ofType( AppConstants.eventTranscriptWatch ).single;
      expect( watch[ "from_offset" ], 950 );
      expect( watch[ "file_epoch" ], "epoch-5" );

      await popConsole( tester );
    } );

    // 🔴 THE STALE-EPOCH PATH, AND A PHONE IS THE CLIENT MOST LIKELY TO HIT IT (§5, T15). If
    // the seat cleared while the phone was away, the server answers epoch_mismatch rather
    // than silently rebasing — a rebase "would hand the client the whole new file labelled as
    // its own continuation".
    testWidgets( "a reconnect into a cleared seat gets epoch_mismatch, clears and re-fetches",
        ( tester ) async {
      repo.tail = backlog(
        epoch  : "epoch-5",
        blocks : [ block( text: "CONTENT FROM BEFORE THE CLEAR" ) ],
      );
      await pumpHost( tester );
      await openConsole( tester );
      expect( find.textContaining( "CONTENT FROM BEFORE", findRichText: true ), findsWidgets,
          reason: "setup" );

      repo
        ..clearReads()
        ..tail = backlog(
          epoch  : "epoch-6",
          blocks : [ block( text: "THE NEW FILE" ) ],
        );

      router.publishState( const TranscriptStateFrame(
        ccSessionId : "seat-1",
        fileEpoch   : "epoch-6",
        state       : TranscriptStreamState.epochMismatch,
        rawState    : "epoch_mismatch",
      ) );
      await settle( tester );

      expect( find.textContaining( "CONTENT FROM BEFORE", findRichText: true ), findsNothing,
          reason: "the screen CLEARS rather than appending a different file onto this one" );
      expect( find.textContaining( "THE NEW FILE", findRichText: true ), findsWidgets );
      expect( repo.reads.last.isTail, isTrue,
          reason: "a new epoch has a new live end" );

      await popConsole( tester );
    } );
  } );

  // ---------------------------------------------------------------------------
  group( "C5.11 — console closed ⇒ ZERO frames", () {
    // 🔴 THE ROW WHOSE SUBJECT IS A NON-EVENT, AND THE ROUTER'S COUNTER IS WHAT MAKES IT
    // ASSERTABLE. "Nothing happened" is indistinguishable from "the router was never called",
    // so the observable is `droppedFrames` moving.
    testWidgets( "pop the route, emit a frame: unwatch was sent and the frame is dropped",
        ( tester ) async {
      await pumpHost( tester );
      await openConsole( tester );
      expect( router.isWatched( "seat-1" ), isTrue, reason: "setup: the route is listening" );
      send.clear();

      await popConsole( tester );

      expect( send.countOfType( AppConstants.eventTranscriptUnwatch ), 1,
          reason: "the fake socket RECORDED an unwatch — the server must stop streaming" );
      expect( router.isWatched( "seat-1" ), isFalse,
          reason: "no bloc is alive to receive anything" );

      final droppedBefore = router.droppedFrames;
      router.publishAppend( append( offset: 100, nextOffset: 200 ) );
      await settle( tester );

      expect( router.droppedFrames, droppedBefore + 1,
          reason: "the TranscriptFrameRouter drops it. NEGATIVE CONTROL: with the "
                  "route-scoping removed — the bloc registered app-root — the bloc would "
                  "still be alive, `isWatched` would still be true, and this counter would "
                  "NOT move. That is the build C1 forbids and this row fails" );
      expect( find.byType( LiveConsoleScreen ), findsNothing );
    } );

    testWidgets( "and no lifecycle event can revive it", ( tester ) async {
      await pumpHost( tester );
      await openConsole( tester );
      await popConsole( tester );
      repo.clearReads();
      send.clear();

      // A backgrounded-then-foregrounded app, after the console is gone. An app-root bloc
      // would catch up and re-watch here, against a screen nobody can see.
      await lifecycle.roundTrip();
      await settle( tester );

      expect( repo.reads, isEmpty,
          reason: "a closed bloc's lifecycle subscription was cancelled by "
                  "PaneVisibilityMixin.close()" );
      expect( send.ofType( AppConstants.eventTranscriptWatch ), isEmpty );
    } );
  } );

  // ---------------------------------------------------------------------------
  group( "C5.12 — popping the route mid-fetch cancels the request", () {
    testWidgets( "the CancelToken is cancelled and no state lands in a closed bloc",
        ( tester ) async {
      final gate     = Completer<TranscriptBacklog>();
      final slowRepo = _SlowRepo( gate );

      tester.view.physicalSize     = const Size( 360, 800 );
      tester.view.devicePixelRatio = 1.0;
      addTearDown( tester.view.resetPhysicalSize );
      addTearDown( tester.view.resetDevicePixelRatio );

      late _TestBloc made;

      await tester.pumpWidget( MaterialApp(
        home: Builder(
          builder: ( context ) => Scaffold(
            body: Center(
              child: ElevatedButton(
                child     : const Text( "open console" ),
                onPressed : () => Navigator.of( context ).push( MaterialPageRoute<void>(
                  builder: ( _ ) => LiveConsoleScreen(
                    ccSessionId : "seat-1",
                    whoLabel    : "maya",
                    blocFactory : ( _ ) => made = _TestBloc(
                      lifecycle : lifecycle,
                      repo      : slowRepo,
                      router    : router,
                      send      : send,
                    ),
                  ),
                ) ),
              ),
            ),
          ),
        ),
      ) );

      await openConsole( tester );
      expect( slowRepo.token, isNotNull, reason: "the backlog fetch is in flight" );
      expect( slowRepo.token!.isCancelled, isFalse );

      await popConsole( tester );

      expect( slowRepo.token!.isCancelled, isTrue,
          reason: "the token held as `_inFlight` in PaneVisibilityMixin is cancelled by "
                  "close(), reached through PanePollingMixin-free super.close() (C3)" );
      expect( made.isClosed, isTrue );

      // Let the gated call complete AFTER the close. Emitting into a closed bloc would throw
      // a StateError, which `takeException` would surface.
      gate.complete( backlog() );
      await settle( tester );

      expect( tester.takeException(), isNull,
          reason: "a response must never land in a closed bloc" );
    } );
  } );

  // ---------------------------------------------------------------------------
  testWidgets( "a frame for ANOTHER seat never reaches this console", ( tester ) async {
    // §5's belt (C6), end to end: if A-T2 ever resolves to `emit_to_user`, the phone's
    // receive-all subscription would see other clients' watched seats.
    await pumpHost( tester );
    await openConsole( tester );

    router.publishAppend( append(
      id     : "some-other-seat",
      offset : 100,
      blocks : [ block( text: "ANOTHER SEAT'S OUTPUT" ) ],
    ) );
    await settle( tester );

    expect( find.textContaining( "ANOTHER SEAT'S OUTPUT", findRichText: true ), findsNothing,
        reason: "one seat's console under another seat's heading is the one failure this "
                "surface must never have" );

    await popConsole( tester );
  } );
}

/// The route-scoped console bloc, read off its own route's context.
TranscriptStreamBloc _consoleBloc( WidgetTester tester ) => BlocProvider.of<TranscriptStreamBloc>(
  tester.element( find.byKey( const Key( TestKeys.liveConsoleScreen ) ) ),
);

/// A repository whose backlog fetch is gated, so it can be held in flight.
class _SlowRepo extends TranscriptRepository {
  final Completer<TranscriptBacklog> gate;

  final List<CancelToken> tokens = [];
  CancelToken? get token => tokens.isEmpty ? null : tokens.last;

  _SlowRepo( this.gate ) : super( _dio );

  static final Dio _dio = Dio();

  @override
  Future<TranscriptBacklog> fetchTail( {
    required String      ccSessionId,
    required CancelToken cancelToken,
    int                  tailBytes = TranscriptRepository.openTailBytes,
  } ) {
    tokens.add( cancelToken );
    return gate.future;
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
  } ) : super(
          ccSessionId : "seat-1",
          repository  : repo,
          router      : router,
          send        : send.call,
        );

  @override
  Stream<AppLifecycleState> get lifecycleStream => lifecycle.stream;
}
