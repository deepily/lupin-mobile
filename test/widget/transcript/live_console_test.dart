import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/transcript/data/transcript_models.dart';
import 'package:lupin_mobile/features/transcript/data/transcript_repository.dart';
import 'package:lupin_mobile/features/transcript/domain/transcript_frame_router.dart';
import 'package:lupin_mobile/features/transcript/domain/transcript_stream_bloc.dart';
import 'package:lupin_mobile/features/transcript/presentation/live_console_screen.dart';

import '../../_helpers/transcript_fakes.dart';

/// The Live Console screen — C5.4, C5.5, C5.14, C5.15, C5.17, C5.18, C5.19 and C5.22.
///
/// ⚠️ TYPED MODEL OBJECTS, NOT CAPTURED FRAMES, and §5 requires captured ones for C5.18,
/// C5.21 and C5.22. Those captured twins live in `live_console_captured_test.dart`, tagged
/// `pending-capture` and RED until phase 1 emits. **What is here proves the BEHAVIOUR; it
/// does not discharge the rows that demand captured input**, and the slice report says so
/// rather than rounding it off.
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

  /// Mount the console over the fakes.
  ///
  /// 🔴 NO `pumpAndSettle` ANYWHERE IN THIS FILE. `FleetStatusScreen`'s tests learned it the
  /// hard way: a screen with live async work never reaches a quiescent frame, and the
  /// framework fails on "a Timer is still pending" rather than on anything asserted. Every
  /// wait here is an explicit `pump`.
  Future<_TestBloc> pump(
    WidgetTester tester, {
    List<TranscriptBlock>? blocks,
    int?  offset,
    int?  nextOffset,
    bool  atStart = false,
    Size  surface = const Size( 360, 800 ),
  } ) async {
    repo.tail = backlog(
      offset     : offset ?? 0,
      nextOffset : nextOffset ?? 100,
      blocks     : blocks ?? [ block( text: "hello" ) ],
      atStart    : atStart,
    );

    tester.view.physicalSize     = surface;
    tester.view.devicePixelRatio = 1.0;
    addTearDown( tester.view.resetPhysicalSize );
    addTearDown( tester.view.resetDevicePixelRatio );

    late _TestBloc made;

    await tester.pumpWidget( MaterialApp(
      home: LiveConsoleScreen(
        ccSessionId : "seat-1",
        whoLabel    : "maya",
        blocFactory : ( _ ) => made = _TestBloc(
          lifecycle : lifecycle,
          repo      : repo,
          router    : router,
          send      : send,
        ),
      ),
    ) );

    // The post-frame callback starts the bloc; then the tail read and the first build land.
    for ( var i = 0; i < 6; i++ ) {
      await tester.pump( const Duration( milliseconds: 10 ) );
    }
    return made;
  }

  // ---------------------------------------------------------------------------
  group( "C5.5 — no input affordance of any kind (ruling Q8)", () {
    testWidgets( "no text field, no send button, no reply action", ( tester ) async {
      await pump( tester, blocks: [
        block( text: "prose" ),
        block( kind: TranscriptBlockKind.toolCall, text: "ls", name: "Bash" ),
      ] );

      expect( find.byType( TextField ), findsNothing );
      expect( find.byType( TextFormField ), findsNothing );

      // 🔴 I ASSERTED `findsNothing` ON `EditableText` AND THAT WAS WRONG ABOUT FLUTTER, not
      // about this screen. `SelectableText` and `MarkdownBody( selectable: true )` BOTH build
      // an `EditableText` with `readOnly: true` — selection is implemented by the same widget
      // as editing. So the absence of the type is not the property worth asserting, and my
      // version would have forced a choice between the test and selectable text.
      //
      // ⇒ The property IS `readOnly` on every one of them. That is a stronger claim than
      // "there is no EditableText": it stays true as more selectable content is added, and it
      // goes red the moment anything on this screen accepts a keystroke.
      final editables = tester.widgetList<EditableText>( find.byType( EditableText ) );
      expect( editables, isNotEmpty,
          reason: "the prose IS selectable, so at least one read-only EditableText is "
                  "expected — an empty list here means the assertion below is vacuous" );
      for ( final e in editables ) {
        expect( e.readOnly, isTrue,
            reason: "ruling Q8: nothing flows from client to seat. Selecting is not typing, "
                    "but only `readOnly` says so" );
      }
      expect( find.byType( FloatingActionButton ), findsNothing,
          reason: "the only FAB on this screen is Jump-to-live, and it appears only when "
                  "scrolled away" );
      expect( find.byIcon( Icons.send ), findsNothing );
      expect( find.byIcon( Icons.mic ), findsNothing );
      expect( find.byIcon( Icons.reply ), findsNothing );
      expect( find.byType( BottomNavigationBar ), findsNothing );
    } );

    testWidgets( "the text IS selectable, which is allowed and is not input", ( tester ) async {
      await pump( tester, blocks: [
        block( kind: TranscriptBlockKind.toolResult, text: "output", name: "Bash" ),
      ] );

      await tester.tap( find.byKey( const Key( "transcript.chip.tool_result" ) ) );
      await tester.pump();

      expect( find.byType( SelectableText ), findsWidgets,
          reason: "§5: selectable text and copy allowed; no input" );
      for ( final e in tester.widgetList<EditableText>( find.byType( EditableText ) ) ) {
        expect( e.readOnly, isTrue );
      }
    } );
  } );

  // ---------------------------------------------------------------------------
  group( "C5.14 — tool output NEVER goes through Markdown", () {
    // The text is chosen to be maximally markdown-ish: a heading marker and an indented
    // line. If it reaches a markdown renderer, the `#` becomes a heading and the indentation
    // becomes a code block — which is how a diff or a config file renders wrong.
    const mangleBait = "# not a heading\n    indented";

    testWidgets( "a tool_result renders verbatim in a SelectableText with no Markdown ancestor",
        ( tester ) async {
      await pump( tester, blocks: [
        block( kind: TranscriptBlockKind.toolResult, text: mangleBait, name: "Read" ),
      ] );

      await tester.tap( find.byKey( const Key( "transcript.chip.tool_result" ) ) );
      await tester.pump();

      final body = find.byKey( const Key( "transcript.plain.tool_result" ) );
      expect( body, findsOneWidget );

      final widget = tester.widget<SelectableText>( body );
      expect( widget.data, mangleBait, reason: "verbatim, including the leading '#'" );
      expect( widget.style?.fontFamily, "monospace" );

      expect(
        find.ancestor( of: body, matching: find.byType( MarkdownBody ) ),
        findsNothing,
      );
      expect( find.byType( MarkdownBody ), findsNothing,
          reason: "there is no prose in this fixture, so there should be no markdown widget "
                  "on screen at all" );
    } );

    // 🔴 THE SECOND HALF IS WHAT PROVES THE TEST CAN TELL THE PATHS APART. The same string as
    // assistant prose MUST render as markdown. Without this, a build that sent everything to
    // SelectableText would pass the first half.
    testWidgets( "the SAME text as assistant prose DOES render as markdown",
        ( tester ) async {
      await pump( tester, blocks: [ block( text: mangleBait ) ] );

      expect( find.byType( MarkdownBody ), findsOneWidget );
      expect( find.byKey( const Key( TestKeys.transcriptProse ) ), findsOneWidget );

      // The markdown renderer produces a heading — a RichText whose style is larger than
      // body text. Asserting the widget type plus the absence of the raw string is what
      // distinguishes "rendered" from "printed".
      expect( find.text( mangleBait ), findsNothing,
          reason: "if the raw source is on screen verbatim, it was NOT rendered as markdown "
                  "and this test is passing for the wrong reason" );
      expect( find.textContaining( "not a heading", findRichText: true ), findsWidgets );
    } );
  } );

  // ---------------------------------------------------------------------------
  group( "C5.15 — an unrecognised kind renders as plain text", () {
    testWidgets( "a kind invented for the test is on screen, and nothing throws",
        ( tester ) async {
      await pump( tester, blocks: [
        TranscriptBlock.fromJson( {
          "kind" : "hologram_from_the_future",
          "text" : "CONTENT THAT MUST NOT VANISH",
        } ),
      ] );

      expect( tester.takeException(), isNull );

      final body = find.byKey( const Key( "transcript.plain.unknown" ) );
      expect( body, findsOneWidget,
          reason: "§3's default arm: never dropped and never thrown on. A three-literal "
                  "switch would render nothing in the one surface whose job is to show "
                  "everything" );
      expect( tester.widget<SelectableText>( body ).data, "CONTENT THAT MUST NOT VANISH" );
      expect(
        find.ancestor( of: body, matching: find.byType( MarkdownBody ) ),
        findsNothing,
        reason: "plain text is the safe arm because it cannot mangle and cannot execute",
      );
    } );

    testWidgets( "an unknown kind is NAMED, so the operator can see what it was",
        ( tester ) async {
      await pump( tester, blocks: [
        TranscriptBlock.fromJson( { "kind": "hologram", "text": "x" } ),
      ] );

      expect( find.text( "Block — hologram" ), findsOneWidget,
          reason: "whoever adds the fifth kind needs to see it already arriving" );
    } );

    testWidgets( "an unknown kind renders OPEN, not folded behind a chip", ( tester ) async {
      await pump( tester, blocks: [
        TranscriptBlock.fromJson( { "kind": "hologram", "text": "VISIBLE AT ONCE" } ),
      ] );

      expect( find.byKey( const Key( "transcript.plain.unknown" ) ), findsOneWidget,
          reason: "the one thing worse than mis-styling an unknown block is hiding it behind "
                  "a chip the operator has no reason to tap" );
    } );
  } );

  // ---------------------------------------------------------------------------
  group( "C5.22 — a `thinking` block is folded, then expandable (OSQ-7)", () {
    testWidgets( "collapsed by default: its text is NOT on screen", ( tester ) async {
      await pump( tester, blocks: [
        block( kind: TranscriptBlockKind.thinking, text: "THE MODEL'S SCRATCH TEXT" ),
      ] );

      expect( find.text( "Thinking…" ), findsOneWidget );
      expect( find.byKey( const Key( "transcript.plain.thinking" ) ), findsNothing );
      expect( find.text( "THE MODEL'S SCRATCH TEXT" ), findsNothing,
          reason: "a build that routed `thinking` through the default arm would show the "
                  "text unfolded and fail exactly here — C5.22's negative control" );
    } );

    testWidgets( "expands in place to monospace SelectableText, never Markdown",
        ( tester ) async {
      await pump( tester, blocks: [
        block( kind: TranscriptBlockKind.thinking, text: "THE MODEL'S SCRATCH TEXT" ),
      ] );

      await tester.tap( find.byKey( const Key( "transcript.chip.thinking" ) ) );
      await tester.pump();

      final body = find.byKey( const Key( "transcript.plain.thinking" ) );
      expect( body, findsOneWidget );
      expect( tester.widget<SelectableText>( body ).data, "THE MODEL'S SCRATCH TEXT" );
      expect( tester.widget<SelectableText>( body ).style?.fontFamily, "monospace" );
      expect( find.byType( MarkdownBody ), findsNothing,
          reason: "model scratch text is not prose and must not be re-flowed as prose" );
    } );

    testWidgets( "it is the FOURTH KNOWN kind, not the default arm", ( tester ) async {
      await pump( tester, blocks: [
        block( kind: TranscriptBlockKind.thinking, text: "scratch" ),
      ] );

      // The default arm's key is `transcript.chip.unknown` and its label is "Block".
      expect( find.byKey( const Key( "transcript.chip.thinking" ) ), findsOneWidget );
      expect( find.byKey( const Key( "transcript.chip.unknown" ) ), findsNothing );
      expect( find.text( "Thinking…" ), findsOneWidget );
    } );
  } );

  // ---------------------------------------------------------------------------
  group( "C5.18 — ruling Q2's content model, not just the widget choice", () {
    testWidgets( "prose open, tool call a one-line chip, tool result collapsed",
        ( tester ) async {
      await pump( tester, blocks: [
        block( text: "assistant prose" ),
        block( kind: TranscriptBlockKind.toolCall, text: "ls -la", name: "Bash" ),
        block( kind: TranscriptBlockKind.toolResult, text: "TOOL OUTPUT", name: "Bash" ),
      ] );

      // Prose: open.
      expect( find.byType( MarkdownBody ), findsOneWidget );
      expect( find.textContaining( "assistant prose", findRichText: true ), findsWidgets );

      // Tool call: a one-line chip naming the tool, with its arguments hidden.
      expect( find.text( "Bash" ), findsOneWidget );
      expect( find.byKey( const Key( "transcript.plain.tool_call" ) ), findsNothing );
      expect( find.text( "ls -la" ), findsNothing );

      // Tool result: collapsed, and its text absent until asked for.
      expect( find.text( "Result — Bash" ), findsOneWidget );
      expect( find.byKey( const Key( "transcript.plain.tool_result" ) ), findsNothing );
      expect( find.text( "TOOL OUTPUT" ), findsNothing );
    } );

    // 🔴 C5.18's NAMED NEGATIVE CONTROL: "a build that renders every block expanded must
    // fail." The assertions above ARE that control — `findsNothing` on the two bodies is what
    // an always-expanded build cannot satisfy. Stated as its own row so the control is not
    // just implied by a `findsNothing` a reader might skim past.
    testWidgets( "an expanded tool result shows its full server-budgeted text",
        ( tester ) async {
      await pump( tester, blocks: [
        block( kind: TranscriptBlockKind.toolResult, text: "TOOL OUTPUT", name: "Bash" ),
      ] );

      await tester.tap( find.byKey( const Key( "transcript.chip.tool_result" ) ) );
      await tester.pump();

      expect( find.text( "TOOL OUTPUT" ), findsOneWidget );

      // And it collapses again — a one-way chip would be a different control.
      await tester.tap( find.byKey( const Key( "transcript.chip.tool_result" ) ) );
      await tester.pump();
      expect( find.text( "TOOL OUTPUT" ), findsNothing );
    } );
  } );

  // ---------------------------------------------------------------------------
  group( "C5.19 — a server-truncated block expands by REST, not from memory", () {
    testWidgets( "the marker shows, and expanding renders the REST answer", ( tester ) async {
      await pump( tester, blocks: [
        block(
          kind      : TranscriptBlockKind.toolResult,
          text      : "the truncated prefix",
          name      : "Bash",
          truncated : true,
          offset    : 4242,
        ),
      ] );

      expect( find.byKey( const Key( TestKeys.transcriptTruncatedMarker ) ), findsOneWidget,
          reason: "the truncation is a fact about the content, so it is visible before the "
                  "expand" );

      repo
        ..clearReads()
        // 🔴 THE CONTROL: text that DIFFERS from the prefix. An expand-from-memory build
        // cannot produce this string.
        ..full = backlog( blocks: [ block(
            kind : TranscriptBlockKind.toolResult,
            text : "THE WHOLE THING FROM THE SERVER",
            name : "Bash",
          ) ] );

      await tester.tap( find.byKey( const Key( "transcript.chip.tool_result" ) ) );
      for ( var i = 0; i < 6; i++ ) {
        await tester.pump( const Duration( milliseconds: 10 ) );
      }

      expect( repo.reads, hasLength( 1 ), reason: "EXACTLY one fetch" );
      expect( repo.reads.single.sinceOffset, 4242 );
      expect( repo.reads.single.maxBytes, 0, reason: "unbounded, §2 item 7's sentinel" );

      expect( find.text( "THE WHOLE THING FROM THE SERVER" ), findsOneWidget );
      expect( find.text( "the truncated prefix" ), findsNothing,
          reason: "the REST text replaced the prefix. A build that expanded from memory shows "
                  "the prefix and calls it the whole thing" );
      expect( find.byKey( const Key( TestKeys.transcriptTruncatedMarker ) ), findsNothing,
          reason: "the marker goes with the truncation" );
    } );
  } );

  // ---------------------------------------------------------------------------
  group( "C5.4 — auto-follow and the Jump-to-live pill", () {
    /// Enough blocks to overflow the surface, so there is somewhere to scroll.
    List<TranscriptBlock> manyBlocks() => List.generate(
      40,
      ( i ) => block( text: "line $i" ),
    );

    testWidgets( "the live end is the BOTTOM edge — the newest block's rect is lowest",
        ( tester ) async {
      await pump( tester, blocks: manyBlocks() );

      // 🔴 NOT "THE OFFSET IS 0", WHICH C5.9's SIBLING ROW WARNS AGAINST. Under
      // `reverse: true`, minScrollExtent is the visual BOTTOM, so an offset assertion alone
      // is true for either orientation. The observable that distinguishes them is the
      // geometry: assert the newest block's rect is LOWER on screen than an older one's.
      final newest = find.textContaining( "line 39", findRichText: true );
      final older  = find.textContaining( "line 38", findRichText: true );
      expect( newest, findsWidgets );
      expect( older, findsWidgets );

      final newestY = tester.getCenter( newest.first ).dy;
      final olderY  = tester.getCenter( older.first ).dy;
      expect( newestY, greaterThan( olderY ),
          reason: "OSQ-9 ruled Option B: newest at the BOTTOM, terminal convention. If the "
                  "newest block is higher on screen, this list is the app's usual "
                  "newest-at-top and the ruling has been undone" );
    } );

    testWidgets( "the pill is absent while following, appears when scrolled away, and "
                 "returns the view", ( tester ) async {
      await pump( tester, blocks: manyBlocks() );

      final pill = find.byKey( const Key( TestKeys.liveConsoleJumpToLive ) );
      expect( pill, findsNothing, reason: "pinned to live — nothing to offer" );

      // Drag DOWN, which under `reverse: true` scrolls back through history.
      await tester.drag( find.byKey( const Key( TestKeys.liveConsoleList ) ),
          const Offset( 0, 400 ) );
      await tester.pump();

      expect( pill, findsOneWidget, reason: "scrolled away from the live end" );

      await tester.tap( pill );
      await tester.pump();

      expect( pill, findsNothing, reason: "back at live, so the pill retires" );
      final controller = tester.widget<ListView>(
        find.byKey( const Key( TestKeys.liveConsoleList ) ) ).controller!;
      expect( controller.position.pixels, controller.position.minScrollExtent,
          reason: "and it landed exactly at the live end" );
    } );

    testWidgets( "a new chunk while following keeps the newest on screen", ( tester ) async {
      final bloc = await pump( tester, blocks: manyBlocks(), nextOffset: 100 );

      router.publishAppend( append(
        offset     : 100,
        nextOffset : 200,
        blocks     : [ block( text: "THE NEWEST LINE" ) ],
      ) );
      for ( var i = 0; i < 4; i++ ) {
        await tester.pump( const Duration( milliseconds: 10 ) );
      }

      expect( find.textContaining( "THE NEWEST LINE", findRichText: true ), findsWidgets,
          reason: "a `reverse: true` list anchored at minScrollExtent keeps the live end in "
                  "view without any follow code, which is why OSQ-9's option B is cheaper "
                  "here than it looked" );
      expect( bloc.state.lastNextOffset, 200 );
    } );
  } );

  // ---------------------------------------------------------------------------
  group( "C5.17 — Load earlier", () {
    testWidgets( "it is at the far end from live, pages back, and hides at the epoch start",
        ( tester ) async {
      await pump(
        tester,
        blocks     : [ block( text: "recent" ) ],
        offset     : 5000,
        nextOffset : 5500,
      );

      final button = find.byKey( const Key( TestKeys.liveConsoleLoadEarlier ) );
      expect( button, findsOneWidget );

      // The far end from live: under `reverse: true`, live is the bottom, so this sits ABOVE
      // the newest block.
      final buttonY = tester.getCenter( button ).dy;
      final newestY = tester.getCenter(
        find.textContaining( "recent", findRichText: true ).first ).dy;
      expect( buttonY, lessThan( newestY ),
          reason: "\"Load earlier\" belongs at the far end from live (C-7)" );

      repo.before = backlog(
        offset     : 2000,
        nextOffset : 5000,
        blocks     : [ block( text: "OLDER CONTENT" ) ],
        atStart    : true,
      );

      await tester.tap( button );
      for ( var i = 0; i < 6; i++ ) {
        await tester.pump( const Duration( milliseconds: 10 ) );
      }

      expect( repo.reads.last.isBefore, isTrue );
      expect( repo.reads.last.beforeOffset, 5000 );
      expect( find.textContaining( "OLDER CONTENT", findRichText: true ), findsWidgets );
      expect( button, findsNothing,
          reason: "it hides once the response reaches the start of the epoch" );
    } );

    testWidgets( "it is absent when the backlog already starts at the epoch start",
        ( tester ) async {
      await pump( tester, offset: 0, nextOffset: 100, atStart: true );

      expect( find.byKey( const Key( TestKeys.liveConsoleLoadEarlier ) ), findsNothing );
    } );
  } );

  // ---------------------------------------------------------------------------
  group( "C5.21 (widget half) — the refusal screen", () {
    testWidgets( "a REST 403 shows the static message and offers only Back",
        ( tester ) async {
      repo.throws = const TranscriptRefused( "admin only" );
      await pump( tester );

      expect( find.byKey( const Key( TestKeys.liveConsoleRefused ) ), findsOneWidget );
      expect( find.text( "Console not available for this session" ), findsOneWidget );
      expect( find.text( "admin only" ), findsOneWidget,
          reason: "§5: with the server's reason if one is given" );
      expect( find.byKey( const Key( TestKeys.liveConsoleBack ) ), findsOneWidget );

      // 🔴 NO RETRY AND NO SPINNER. §5 names both absences, and a Retry button here would be
      // the whole defect: the button only hides a refusal, the server is the gate, and
      // asking again cannot change the answer.
      expect( find.text( "Retry" ), findsNothing );
      expect( find.byType( CircularProgressIndicator ), findsNothing );
      expect( find.byKey( const Key( TestKeys.liveConsoleList ) ), findsNothing,
          reason: "keeps no buffer" );
    } );

    testWidgets( "a refused STATE frame shows the same screen", ( tester ) async {
      await pump( tester, blocks: [ block( text: "content that must go" ) ] );
      expect( find.byKey( const Key( TestKeys.liveConsoleList ) ), findsOneWidget,
          reason: "setup: there was a buffer" );

      router.publishState( const TranscriptStateFrame(
        ccSessionId : "seat-1",
        state       : TranscriptStreamState.refused,
        rawState    : "refused",
      ) );
      for ( var i = 0; i < 4; i++ ) {
        await tester.pump( const Duration( milliseconds: 10 ) );
      }

      expect( find.byKey( const Key( TestKeys.liveConsoleRefused ) ), findsOneWidget );
      expect( find.text( "content that must go" ), findsNothing, reason: "keeps no buffer" );
    } );
  } );

  // ---------------------------------------------------------------------------
  testWidgets( "the app bar names the seat", ( tester ) async {
    await pump( tester );
    expect( find.text( "Console — maya" ), findsOneWidget );
  } );

  testWidgets( "leaving the route sends unwatch", ( tester ) async {
    await pump( tester );
    send.clear();

    // Replacing the widget tree disposes the route, which closes the bloc.
    await tester.pumpWidget( const MaterialApp( home: SizedBox() ) );
    await tester.pump( const Duration( milliseconds: 10 ) );

    expect( send.sent.any( ( f ) => f[ "type" ] == "cc_transcript_unwatch" ), isTrue );
  } );
}

/// The bloc with its lifecycle stream replaced by the test's.
class _TestBloc extends TranscriptStreamBloc {
  final FakeLifecycle lifecycle;

  _TestBloc( {
    required this.lifecycle,
    required FakeTranscriptRepository repo,
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
