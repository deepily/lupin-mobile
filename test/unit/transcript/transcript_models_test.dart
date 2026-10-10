import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/transcript/data/transcript_models.dart';

/// §3's wire contract, parsed. The rule under test everywhere here: **a malformed frame
/// yields a frame with nulls, never an exception.**
///
/// 🔴 THAT IS NOT DEFENSIVENESS FOR ITS OWN SAKE. A socket frame arrives on a stream with no
/// caller to catch for it, so a throw in a parser is a DEAD STREAM — and the surface whose
/// whole job is to show everything would then show nothing, silently. The fleet models
/// already follow the same rule for the same reason.
void main() {
  group( "kind mapping", () {
    test( "the four known wire names map, and the names are SNAKE_CASE", () {
      expect( TranscriptBlockKind.fromWire( "text" ), TranscriptBlockKind.text );
      expect( TranscriptBlockKind.fromWire( "tool_call" ), TranscriptBlockKind.toolCall );
      expect( TranscriptBlockKind.fromWire( "tool_result" ),
          TranscriptBlockKind.toolResult );
      expect( TranscriptBlockKind.fromWire( "thinking" ), TranscriptBlockKind.thinking );
    } );

    test( "the DART spelling is not a wire name", () {
      // A `.name`-based comparison would match these and silently stop matching the real
      // wire names. Stated as a test so the mapping cannot quietly become a `.name` lookup.
      expect( TranscriptBlockKind.fromWire( "toolCall" ), TranscriptBlockKind.unknown );
      expect( TranscriptBlockKind.fromWire( "toolResult" ), TranscriptBlockKind.unknown );
    } );

    // 🔴 THE DEFAULT ARM IS A FEATURE (§3). The server's mapper is open-ended by design and
    // OSQ-7 already added a fourth kind after the first three were written.
    test( "anything else is `unknown`, never an error", () {
      for ( final raw in <Object?>[ null, "", "audio", 7, <String>[], {} ] ) {
        expect( TranscriptBlockKind.fromWire( raw ), TranscriptBlockKind.unknown,
            reason: "kind '$raw' must degrade, not throw" );
      }
    } );

    test( "only `text` renders as markdown", () {
      expect( TranscriptBlockKind.text.isPlainText, isFalse );
      for ( final k in TranscriptBlockKind.values ) {
        if ( k == TranscriptBlockKind.text ) continue;
        expect( k.isPlainText, isTrue,
            reason: "$k must not reach a markdown renderer — `#` would become a heading and "
                    "indentation a code block, so a diff or a config file renders wrong" );
      }
    } );

    test( "prose starts open; tool content and thinking start collapsed (ruling Q2 + OSQ-7)",
        () {
      expect( TranscriptBlockKind.text.startsCollapsed, isFalse );
      expect( TranscriptBlockKind.toolCall.startsCollapsed, isTrue );
      expect( TranscriptBlockKind.toolResult.startsCollapsed, isTrue );
      expect( TranscriptBlockKind.thinking.startsCollapsed, isTrue );
      // An unrecognised kind renders OPEN, because the one thing worse than mis-styling it
      // is hiding it behind a chip the operator has no reason to tap.
      expect( TranscriptBlockKind.unknown.startsCollapsed, isFalse );
    } );
  } );

  group( "TranscriptBlock.fromJson", () {
    test( "a full block parses", () {
      final b = TranscriptBlock.fromJson( {
        "kind"      : "tool_result",
        "text"      : "output",
        "truncated" : true,
        "name"      : "Bash",
        "offset"    : 4242,
      } );

      expect( b.kind, TranscriptBlockKind.toolResult );
      expect( b.rawKind, "tool_result" );
      expect( b.text, "output" );
      expect( b.truncated, isTrue );
      expect( b.name, "Bash" );
      expect( b.offset, 4242 );
    } );

    test( "the RAW kind is kept even when it maps to unknown", () {
      final b = TranscriptBlock.fromJson( { "kind": "hologram", "text": "x" } );

      expect( b.kind, TranscriptBlockKind.unknown );
      expect( b.rawKind, "hologram",
          reason: "dropping it leaves the operator looking at text with no idea what the "
                  "server called it, and whoever adds the fifth kind with no way to see it "
                  "already arriving" );
    } );

    test( "`truncated` is not coerced", () {
      for ( final bad in <Object?>[ "true", 1, "1", null, <String>[] ] ) {
        expect(
          TranscriptBlock.fromJson( { "kind": "text", "truncated": bad } ).truncated,
          isFalse,
          reason: "a changed type is a changed contract; guessing would show a truncation "
                  "marker on a complete block or hide one on a cut block",
        );
      }
    } );

    test( "a missing text becomes an empty string, so a renderer always has a String", () {
      expect( TranscriptBlock.fromJson( { "kind": "text" } ).text, "" );
      expect( TranscriptBlock.fromJson( null ).text, "" );
      expect( TranscriptBlock.fromJson( "junk" ).kind, TranscriptBlockKind.unknown );
    } );

    // A tool call's arguments arrive as structure, not a string. `Instance of '_Map'` on
    // screen is the failure this avoids.
    test( "structured text is rendered as pretty JSON, not as toString", () {
      final b = TranscriptBlock.fromJson( {
        "kind" : "tool_call",
        "text" : { "command": "ls -la", "cwd": "/tmp" },
      } );

      expect( b.text, contains( '"command": "ls -la"' ) );
      expect( b.text, isNot( contains( "Instance of" ) ) );
      expect( b.text, contains( "\n" ), reason: "indented, so it is readable" );
    } );

    group( "sizeBytes is UTF-8 bytes (C8, paired with A-T7)", () {
      test( "ASCII, accented and emoji all count in bytes", () {
        expect( TranscriptBlock.fromJson( { "text": "abc" } ).sizeBytes, 3 );
        expect( TranscriptBlock.fromJson( { "text": "é" } ).sizeBytes, 2 );
        expect( TranscriptBlock.fromJson( { "text": "🌻" } ).sizeBytes, 4 );
      } );

      test( "a Dart code-unit count would disagree, which is the point", () {
        const emoji = "🌻🌻🌻";
        expect( emoji.length, 6, reason: "code units" );
        expect( TranscriptBlock.fromJson( { "text": emoji } ).sizeBytes, 12,
            reason: "the server caps in bytes. A ring that counted code units would hold "
                    "twice what it believed and 'never exceeds its cap' would mean two "
                    "different things on the two ends" );
      } );
    } );

    test( "withText preserves everything else", () {
      final b = TranscriptBlock.fromJson( {
        "kind": "tool_result", "text": "cut", "truncated": true,
        "name": "Bash", "offset": 9,
      } ).withText( "the whole thing", truncated: false );

      expect( b.text, "the whole thing" );
      expect( b.truncated, isFalse );
      expect( b.kind, TranscriptBlockKind.toolResult );
      expect( b.name, "Bash" );
      expect( b.offset, 9 );
    } );
  } );

  group( "TranscriptAppend.fromJson", () {
    test( "a full frame parses", () {
      final f = TranscriptAppend.fromJson( {
        "cc_session_id" : "6bf7cfa9-964e-4cef-a5d9-a804a4d75874",
        "file_epoch"    : "epoch-1",
        "offset"        : 100,
        "next_offset"   : 200,
        "ts"            : "2026-09-27T22:00:00Z",
        "blocks"        : [
          { "kind": "text", "text": "hello" },
          { "kind": "tool_call", "text": "ls" },
        ],
      } );

      expect( f.ccSessionId, "6bf7cfa9-964e-4cef-a5d9-a804a4d75874" );
      expect( f.fileEpoch, "epoch-1" );
      expect( f.offset, 100 );
      expect( f.nextOffset, 200 );
      expect( f.blocks, hasLength( 2 ) );
      expect( f.blocks.first.kind, TranscriptBlockKind.text );
      expect( f.blocks.last.kind, TranscriptBlockKind.toolCall );
    } );

    test( "there is no separate `seq` — `offset` IS the sequence number (§3)", () {
      // A frame carrying a `seq` the client reads instead of `offset` would sequence on a
      // field §3 says does not exist. Asserted by showing `offset` is what is read.
      final f = TranscriptAppend.fromJson( {
        "offset": 512, "seq": 7, "next_offset": 600,
      } );
      expect( f.offset, 512 );
      expect( f.nextOffset, 600 );
    } );

    test( "junk yields an empty frame rather than throwing", () {
      for ( final junk in <Object?>[ null, "a string", 7, <String>[] ] ) {
        final f = TranscriptAppend.fromJson( junk );
        expect( f.ccSessionId, isNull );
        expect( f.blocks, isEmpty );
      }
      // A `blocks` that is not a list, and a non-numeric offset.
      final f = TranscriptAppend.fromJson( { "blocks": "nope", "offset": "100" } );
      expect( f.blocks, isEmpty );
      expect( f.offset, isNull, reason: "a non-numeric offset is dropped, never coerced — a "
                                       "parsed '100' would sequence on a guess" );
    } );
  } );

  group( "TranscriptStateFrame.fromJson", () {
    test( "the five known states map", () {
      expect( TranscriptStreamState.fromWire( "live" ), TranscriptStreamState.live );
      expect( TranscriptStreamState.fromWire( "ended" ), TranscriptStreamState.ended );
      expect( TranscriptStreamState.fromWire( "rotated" ), TranscriptStreamState.rotated );
      expect( TranscriptStreamState.fromWire( "epoch_mismatch" ),
          TranscriptStreamState.epochMismatch );
      expect( TranscriptStreamState.fromWire( "refused" ),
          TranscriptStreamState.refused );
    } );

    test( "an unknown state is `unknown`, and its raw name is kept", () {
      final f = TranscriptStateFrame.fromJson( {
        "cc_session_id": "s", "state": "hibernating",
      } );
      expect( f.state, TranscriptStreamState.unknown );
      expect( f.rawState, "hibernating" );
    } );

    test( "a reason is read from `reason` or `detail`", () {
      expect(
        TranscriptStateFrame.fromJson( { "state": "refused", "reason": "admin only" } ).reason,
        "admin only",
      );
      expect(
        TranscriptStateFrame.fromJson( { "state": "refused", "detail": "not permitted" } ).reason,
        "not permitted",
        reason: "FastAPI's own refusal shape is `detail`, so both are read rather than one "
                "guessed",
      );
    } );
  } );

  group( "TranscriptBacklog.fromJson", () {
    test( "a full body parses", () {
      final b = TranscriptBacklog.fromJson( {
        "file_epoch"  : "epoch-2",
        "offset"      : 1000,
        "next_offset" : 2000,
        "at_start"    : true,
        "blocks"      : [ { "kind": "text", "text": "x" } ],
      } );

      expect( b.fileEpoch, "epoch-2" );
      expect( b.offset, 1000 );
      expect( b.nextOffset, 2000 );
      expect( b.atStart, isTrue );
      expect( b.blocks, hasLength( 1 ) );
    } );

    // 🔴 A MISSING `at_start` IS FALSE, WHICH KEEPS "LOAD EARLIER" VISIBLE. The other
    // default hides the control against a server that never sends the field, making the rest
    // of the transcript unreachable — and a hidden control is the failure nobody reports.
    test( "a missing at_start is false, so the pager stays reachable", () {
      expect( TranscriptBacklog.fromJson( { "offset": 1 } ).atStart, isFalse );
      expect( TranscriptBacklog.fromJson( { "at_start": "true" } ).atStart, isFalse,
          reason: "not coerced" );
    } );

    test( "at_epoch_start is read as an alias", () {
      expect( TranscriptBacklog.fromJson( { "at_epoch_start": true } ).atStart, isTrue );
    } );

    test( "junk yields an empty body", () {
      for ( final junk in <Object?>[ null, "x", 1 ] ) {
        expect( TranscriptBacklog.fromJson( junk ).blocks, isEmpty );
      }
    } );
  } );

  group( "isUnrecordedThinking", () {
    TranscriptBlock b( TranscriptBlockKind k, String t, { bool truncated = false } ) =>
        TranscriptBlock( kind: k, text: t, truncated: truncated );

    test( "an empty or whitespace-only thinking block is unrecorded", () {
      expect( b( TranscriptBlockKind.thinking, "" ).isUnrecordedThinking, isTrue );
      expect( b( TranscriptBlockKind.thinking, " \n\t" ).isUnrecordedThinking, isTrue );
    } );

    test( "a thinking block with text is recorded", () {
      expect( b( TranscriptBlockKind.thinking, "scratch" ).isUnrecordedThinking, isFalse );
    } );

    test( "an empty block of another kind is not 'unrecorded thinking'", () {
      expect( b( TranscriptBlockKind.text, "" ).isUnrecordedThinking, isFalse );
      expect( b( TranscriptBlockKind.toolResult, "" ).isUnrecordedThinking, isFalse );
    } );

    test( "a truncated empty thinking block is never called unrecorded", () {
      expect( b( TranscriptBlockKind.thinking, "", truncated: true ).isUnrecordedThinking, isFalse );
    } );
  } );
}
