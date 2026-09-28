@Tags( [ "pending-capture" ] )
library;

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/constants/app_constants.dart';
import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/transcript/data/transcript_models.dart';
import 'package:lupin_mobile/features/transcript/data/transcript_repository.dart';
import 'package:lupin_mobile/features/transcript/domain/transcript_frame_router.dart';
import 'package:lupin_mobile/features/transcript/domain/transcript_stream_bloc.dart';
import 'package:lupin_mobile/features/transcript/presentation/live_console_screen.dart';

import '../../_helpers/fixture_loader.dart';
import '../../_helpers/transcript_fakes.dart';
import '../../unit/_helpers/stub_dio.dart';

/// C5.18, C5.21 and C5.22 — the **CAPTURED ARMS**, against real server output. Red until
/// Mr. Radio's phase 1 emits.
///
/// 🔴 THIS FILE IS SUPPOSED TO BE RED RIGHT NOW, AND THAT IS THE RULING RATHER THAN A DEFECT.
/// All three rows name captured input in as many words — C5.18 "from a captured frame
/// carrying prose, a `tool_call` and a `tool_result`", C5.21 "from a **captured**
/// `cc_transcript_state {state: refused}` frame, and separately from a REST **403**", C5.22
/// "from a captured frame carrying `kind: thinking`". `test/fixtures/transcript/` does not
/// exist yet, so `fixture_loader` throws `FileSystemException` on every test below.
///
/// §5 chose red over skipped on purpose: *"They are red, not skipped, until the capture
/// lands… So phase 3 cannot close with any row still pending, and nothing can quietly pass
/// without its fixture."* The gate for a slice is
/// `./flutter.sh test --exclude-tags pending-capture` plus the roster from
/// `./flutter.sh test --tags pending-capture`; **phase 3 closes only on a plain
/// `./flutter.sh test` with zero exclusions.**
///
/// ⚠️ MARÍA'S FIRST CONDITION KEEPS THE TAG HONEST: a test may carry it ONLY IF ITS SOLE
/// FAILURE IS the missing-file `FileSystemException`. So every test below loads its fixture
/// on its FIRST line, before any widget is pumped and before any assertion.
///
/// ⚠️ THE TYPED TWINS IN `live_console_test.dart` ARE GREEN AND DO NOT DISCHARGE THESE ROWS.
/// They prove the BEHAVIOUR over model objects the test built; these prove the same
/// behaviour over bytes the server wrote, which is a different claim — a parser that
/// mis-reads a real `kind` string produces a screen that is wrong in a way no typed test can
/// see. That is stated in the slice report rather than rounded off.
///
/// ## What the capture script must record, for this file to go green
///
/// `src/scripts/capture-transcript-fixtures.py` (§5, "Real frames, not invented ones" — the
/// same shape as the six existing `capture-*-fixtures.py`), redacted per
/// `test/fixtures/README.md`:
///
///   - `transcript/append_mixed_kinds.json` — ONE real `cc_transcript_append` frame whose
///     `blocks` carry, in the same frame, a prose block, a `tool_call` and a `tool_result`.
///     The tool_result must be **not** `truncated`: C5.18 asks what a collapsed result shows
///     when expanded, and a truncated one answers over REST instead (that is C5.19's row, and
///     conflating them would make this row pass for the wrong reason)
///   - `transcript/append_thinking.json` — ONE real append frame carrying a `kind: thinking`
///     block with non-trivial text
///   - `transcript/state_refused.json` — ONE real `cc_transcript_state` frame with
///     `state: "refused"`, carrying the server's own `reason`
///   - `transcript/backlog_403.json` — the REST endpoint's real **403 body** for a seat the
///     caller may not read, so the refusal reason on screen is the server's string
///
/// 🔴 AND THE FRAMES MUST CARRY THEIR OWN `cc_session_id` AND `offset`, BECAUSE THIS FILE
/// USES THEM RATHER THAN SUBSTITUTING ITS OWN. The console is opened for the id the capture
/// names, and the tail read is seeded so the captured append's `offset` is CONTINUOUS with
/// it — otherwise §3's gap rule drops the frame and repairs over REST, and a row about
/// rendering would fail on routing. If a captured frame arrives with no `offset`, these rows
/// fail saying so: an append with no offset is a phase-1 finding, not a test bug.
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

  /// Mount the console for the seat the CAPTURE names, with the tail read answering at
  /// [tailNextOffset] so a captured append at that offset is continuous with the backlog.
  ///
  /// 🔴 NO `pumpAndSettle`: a console with live async work never reaches a quiescent frame.
  Future<_TestBloc> pumpFor(
    WidgetTester tester, {
    required String       ccSessionId,
    int?                  tailNextOffset,
    String?               epoch,
    TranscriptRepository? repository,
  } ) async {
    repo.tail = backlog(
      epoch      : epoch,
      offset     : 0,
      nextOffset : tailNextOffset,
      blocks     : const [],
    );

    tester.view.physicalSize     = const Size( 360, 800 );
    tester.view.devicePixelRatio = 1.0;
    addTearDown( tester.view.resetPhysicalSize );
    addTearDown( tester.view.resetDevicePixelRatio );

    late _TestBloc made;

    await tester.pumpWidget( MaterialApp(
      home: LiveConsoleScreen(
        ccSessionId : ccSessionId,
        whoLabel    : "captured",
        blocFactory : ( _ ) => made = _TestBloc(
          ccSessionId : ccSessionId,
          lifecycle   : lifecycle,
          repo        : repository ?? repo,
          router      : router,
          send        : send,
        ),
      ),
    ) );

    await settle( tester );
    return made;
  }

  /// A distinctive slice of a captured block's text, for an on-screen / not-on-screen check.
  ///
  /// ⚠️ NEVER `find.text( block.text )` ON CAPTURED CONTENT. Real tool output is multi-line
  /// and wrapped, and `find.text` matches a whole `Text` widget's string — so an exact match
  /// fails on content that IS displayed, which would read as a rendering bug. The snippet is
  /// matched with `findRichText`, and a capture too short to yield one fails loudly rather
  /// than silently asserting nothing.
  String snippetOf( TranscriptBlock block, String label ) {
    final firstLine = block.text.split( "\n" ).map( ( l ) => l.trim() )
        .firstWhere( ( l ) => l.length >= 8, orElse: () => "" );
    expect( firstLine, isNotEmpty,
        reason: "the captured $label block has no line of 8+ characters, so neither "
                "'it is hidden' nor 'it is shown' can be asserted about it. Re-capture with "
                "real content — text: '${ block.text }'" );
    return firstLine.length > 40 ? firstLine.substring( 0, 40 ) : firstLine;
  }

  TranscriptBlock onlyKind( TranscriptAppend frame, TranscriptBlockKind kind, String label ) {
    final matching = frame.blocks.where( ( b ) => b.kind == kind ).toList();
    expect( matching, isNotEmpty,
        reason: "the captured frame carries no $label block, so this row cannot prove "
                "anything about one. Kinds present: "
                "${ frame.blocks.map( ( b ) => b.rawKind ?? b.kind.name ).toList() }" );
    return matching.first;
  }

  String idOf( TranscriptAppend frame ) {
    expect( frame.ccSessionId, isNotNull,
        reason: "a captured append with no cc_session_id cannot be routed to any console — "
                "§3 pins the field, and its absence is a phase-1 finding" );
    return frame.ccSessionId!;
  }

  int offsetOf( TranscriptAppend frame ) {
    expect( frame.offset, isNotNull,
        reason: "a captured append with no offset cannot be placed against a backlog: §3's "
                "gap rule is 'if chunk.offset != last_next_offset, drop the chunk'. Its "
                "absence is a phase-1 finding, not a test bug" );
    return frame.offset!;
  }

  // ---------------------------------------------------------------------------
  group( "C5.18 (captured) — ruling Q2's content model over real server output", () {
    testWidgets( "prose open, tool call a one-line chip, tool result collapsed",
        ( tester ) async {
      // FIRST LINE, deliberately: the only way this test can fail today is the missing
      // fixture, which is what lets it carry the `pending-capture` tag.
      final frame = TranscriptAppend.fromJson(
        loadFixture( "transcript/append_mixed_kinds.json" ) );

      final prose  = onlyKind( frame, TranscriptBlockKind.text,       "prose" );
      final call   = onlyKind( frame, TranscriptBlockKind.toolCall,   "tool_call" );
      final result = onlyKind( frame, TranscriptBlockKind.toolResult, "tool_result" );

      expect( result.truncated, isFalse,
          reason: "C5.18 asks what a COLLAPSED result shows when expanded; a truncated one "
                  "answers over REST instead, which is C5.19's row. Re-capture a frame whose "
                  "tool_result is whole" );
      expect( call.name, isNotNull,
          reason: "the chip is 'the tool name on one line' — a captured tool_call with no "
                  "`name` leaves nothing to put on it" );

      await pumpFor( tester,
          ccSessionId : idOf( frame ),
          epoch       : frame.fileEpoch,
          tailNextOffset : offsetOf( frame ) );
      router.publishAppend( frame );
      await settle( tester );

      // Prose: open, and rendered as prose.
      expect( find.byKey( const Key( TestKeys.transcriptProse ) ), findsWidgets );
      expect( find.textContaining( snippetOf( prose, "prose" ), findRichText: true ),
          findsWidgets, reason: "captured prose renders open (ruling Q2)" );

      // Tool call: a one-line chip naming the tool, arguments hidden.
      expect( find.text( call.name! ), findsWidgets );
      expect( find.byKey( const Key( "${ TestKeys.transcriptChipPrefix }tool_call" ) ),
          findsOneWidget );
      expect( find.byKey( const Key( "${ TestKeys.transcriptPlainPrefix }tool_call" ) ),
          findsNothing, reason: "the captured arguments are not on screen" );

      // Tool result: collapsed, and its captured text absent until asked for.
      expect( find.text( "Result — ${ result.name }" ), findsOneWidget );
      expect( find.byKey( const Key( "${ TestKeys.transcriptPlainPrefix }tool_result" ) ),
          findsNothing );
      expect( find.textContaining( snippetOf( result, "tool_result" ), findRichText: true ),
          findsNothing,
          reason: "C5.18's negative control: a build that renders every block expanded shows "
                  "the captured tool output here and fails exactly this line" );
    } );

    testWidgets( "an expanded tool result shows its full CAPTURED text", ( tester ) async {
      final frame = TranscriptAppend.fromJson(
        loadFixture( "transcript/append_mixed_kinds.json" ) );

      final result = onlyKind( frame, TranscriptBlockKind.toolResult, "tool_result" );

      await pumpFor( tester,
          ccSessionId : idOf( frame ),
          epoch       : frame.fileEpoch,
          tailNextOffset : offsetOf( frame ) );
      router.publishAppend( frame );
      await settle( tester );

      // The CHIP is what is on screen while the result is collapsed; the plain body does not
      // exist yet, which is the whole claim of the row above.
      await tester.tap(
        find.byKey( const Key( "${ TestKeys.transcriptChipPrefix }tool_result" ) ) );
      await tester.pump();

      expect( find.byKey( const Key( "${ TestKeys.transcriptPlainPrefix }tool_result" ) ),
          findsOneWidget );
      expect( find.textContaining( snippetOf( result, "tool_result" ), findRichText: true ),
          findsWidgets, reason: "the server-budgeted text, as captured" );
    } );
  } );

  // ---------------------------------------------------------------------------
  group( "C5.22 (captured) — a `thinking` block is folded, then expandable (OSQ-7)", () {
    testWidgets( "collapsed by default: the captured scratch text is NOT on screen",
        ( tester ) async {
      final frame = TranscriptAppend.fromJson(
        loadFixture( "transcript/append_thinking.json" ) );

      final thinking = onlyKind( frame, TranscriptBlockKind.thinking, "thinking" );
      final snippet  = snippetOf( thinking, "thinking" );

      await pumpFor( tester,
          ccSessionId : idOf( frame ),
          epoch       : frame.fileEpoch,
          tailNextOffset : offsetOf( frame ) );
      router.publishAppend( frame );
      await settle( tester );

      expect( find.text( "Thinking…" ), findsOneWidget );
      expect( find.byKey( const Key( "${ TestKeys.transcriptChipPrefix }thinking" ) ),
          findsOneWidget,
          reason: "`thinking` is the FOURTH KNOWN kind (OSQ-7), not the default arm — the "
                  "default's slug is `unknown`. A captured `kind` string this parser does "
                  "not know lands there, which is the failure this captured arm exists to "
                  "catch: raw kind was '${ thinking.rawKind }'" );
      expect( find.byKey( const Key( "${ TestKeys.transcriptChipPrefix }unknown" ) ),
          findsNothing );
      expect( find.textContaining( snippet, findRichText: true ), findsNothing,
          reason: "C5.22's negative control: a build routing `thinking` through the default "
                  "arm shows the text unfolded and fails exactly here" );
    } );

    testWidgets( "expands in place to monospace SelectableText, never Markdown",
        ( tester ) async {
      final frame = TranscriptAppend.fromJson(
        loadFixture( "transcript/append_thinking.json" ) );

      final thinking = onlyKind( frame, TranscriptBlockKind.thinking, "thinking" );

      await pumpFor( tester,
          ccSessionId : idOf( frame ),
          epoch       : frame.fileEpoch,
          tailNextOffset : offsetOf( frame ) );
      router.publishAppend( frame );
      await settle( tester );

      await tester.tap( find.byKey( const Key( "${ TestKeys.transcriptChipPrefix }thinking" ) ) );
      await tester.pump();

      final body = find.byKey( const Key( "${ TestKeys.transcriptPlainPrefix }thinking" ) );
      expect( body, findsOneWidget );
      expect( tester.widget<SelectableText>( body ).data, thinking.text,
          reason: "the whole captured text, not a re-flowed version of it" );
      expect( tester.widget<SelectableText>( body ).style?.fontFamily, "monospace" );
      expect( find.byType( MarkdownBody ), findsNothing,
          reason: "model scratch text is not prose and must not be re-flowed as prose" );
    } );
  } );

  // ---------------------------------------------------------------------------
  group( "C5.21 (captured) — a refused watch is FINAL", () {
    testWidgets( "a captured refused STATE frame: static message, no buffer, no retry",
        ( tester ) async {
      final refusal = TranscriptStateFrame.fromJson(
        loadFixture( "transcript/state_refused.json" ) );

      expect( refusal.state, TranscriptStreamState.refused,
          reason: "this fixture must be a `state: refused` frame; captured raw state was "
                  "'${ refusal.rawState }'" );
      final id = refusal.ccSessionId;
      expect( id, isNotNull, reason: "a state frame with no cc_session_id routes nowhere" );

      // A buffer first, so "keeps no buffer" is a change rather than a starting condition.
      repo.tail = backlog( blocks: [ block( text: "content that must go" ) ] );
      final bloc = await pumpFor( tester, ccSessionId: id! );
      expect( find.byKey( const Key( TestKeys.liveConsoleList ) ), findsOneWidget,
          reason: "setup: there was a buffer" );

      repo.clearReads();
      send.clear();
      router.publishState( refusal );
      await settle( tester );

      expect( find.byKey( const Key( TestKeys.liveConsoleRefused ) ), findsOneWidget );
      expect( find.text( "Console not available for this session" ), findsOneWidget );
      expect( find.text( "content that must go" ), findsNothing, reason: "keeps no buffer" );
      expect( find.byKey( const Key( TestKeys.liveConsoleBack ) ), findsOneWidget );
      expect( find.text( "Retry" ), findsNothing );
      if ( refusal.reason != null ) {
        expect( find.text( refusal.reason! ), findsOneWidget,
            reason: "§5: with the server's reason if one is given — and it is the SERVER's "
                    "string, which is why this arm reads it from the capture" );
      }

      // 🔴 THE ROW IS ABOUT WHAT HAPPENS NEXT, AND ITS NEGATIVE CONTROL IS A BUILD THAT
      // RETRIES. A foreground return and an `auth_success` are the two paths that re-arm a
      // healthy console; after a refusal both must be silent.
      await lifecycle.roundTrip( gap: () => tester.pump( const Duration( milliseconds: 10 ) ) );
      bloc.onReconnected();
      await settle( tester );

      expect( repo.reads, isEmpty, reason: "no REST retry after a refusal" );
      expect( send.ofType( AppConstants.eventTranscriptWatch ), isEmpty,
          reason: "and no further watch, across a foreground return AND an auth_success" );
    } );

    testWidgets( "a captured REST 403 body: the server's reason, and nothing asked again",
        ( tester ) async {
      final body = loadFixture( "transcript/backlog_403.json" );

      // 🔴 THE REAL REPOSITORY, NOT A FAKE THAT THROWS. This arm's subject is the mapping
      // from a 403 BODY to the refusal screen — `_detailFrom` picking the server's `detail`
      // out of the bytes it actually sends. A fake configured to throw
      // `TranscriptRefused( "admin only" )` asserts a string I invented and would stay green
      // over a body shaped differently from the one the server writes.
      const id      = "captured-403-seat";
      final adapter = StubAdapter( {
        "GET ${ TranscriptRepository.pathPrefix }/$id":
            ( _ ) => jsonBodyFromFixture( "transcript/backlog_403.json", status: 403 ),
      } );
      final real = TranscriptRepository( makeDio( adapter ) );

      final bloc = await pumpFor( tester, ccSessionId: id, repository: real );

      expect( find.byKey( const Key( TestKeys.liveConsoleRefused ) ), findsOneWidget,
          reason: "a 403 is a refusal, not a retryable failure" );
      expect( find.byKey( const Key( TestKeys.liveConsoleList ) ), findsNothing,
          reason: "keeps no buffer" );
      expect( find.text( "Retry" ), findsNothing );
      expect( find.byType( CircularProgressIndicator ), findsNothing );

      final detail = body[ "detail" ];
      if ( detail is String && detail.isNotEmpty ) {
        expect( find.text( detail ), findsOneWidget,
            reason: "the reason on screen is the CAPTURED server string, read through the "
                    "repository's own 403 mapping" );
      }

      final callsAfterRefusal = adapter.captured.length;
      expect( callsAfterRefusal, 1, reason: "exactly the one backlog read that was refused" );

      await lifecycle.roundTrip( gap: () => tester.pump( const Duration( milliseconds: 10 ) ) );
      bloc.onReconnected();
      await settle( tester );

      expect( adapter.captured.length, callsAfterRefusal,
          reason: "a build that retries the backlog on resume or on reconnect fails exactly "
                  "here — C5.21's named negative control" );
      expect( send.ofType( AppConstants.eventTranscriptWatch ), isEmpty );
    } );
  } );
}

/// The bloc with its lifecycle stream replaced by the test's, and its seat id taken from the
/// capture rather than hardcoded.
class _TestBloc extends TranscriptStreamBloc {
  final FakeLifecycle lifecycle;

  _TestBloc( {
    required String               ccSessionId,
    required this.lifecycle,
    required TranscriptRepository repo,
    required TranscriptFrameRouter router,
    required RecordingSender      send,
  } ) : super(
          ccSessionId : ccSessionId,
          repository  : repo,
          router      : router,
          send        : send.call,
        );

  @override
  Stream<AppLifecycleState> get lifecycleStream => lifecycle.stream;
}

Future<void> settle( WidgetTester tester, { int frames = 6 } ) async {
  for ( var i = 0; i < frames; i++ ) {
    await tester.pump( const Duration( milliseconds: 10 ) );
  }
}
