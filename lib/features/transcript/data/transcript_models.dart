/// §3's wire contract, as Dart. One file, because the contract is one thing and a reader
/// checking the client against the plan should not have to assemble it from four.
///
/// 🔴 EVERY PARSE HERE IS TOTAL: a malformed frame yields a frame with nulls, never an
/// exception. A socket frame arrives on a stream with no caller to catch for it, so a throw
/// in a parser is a dead stream — and the surface whose whole job is to show everything
/// would show nothing, silently. The same rule the fleet models already follow.
library;

import 'dart:convert';

/// What a block IS, which decides how it renders.
///
/// 🔴 THE MAPPER IS OPEN-ENDED BY DESIGN AND SO IS THIS ENUM'S USE. §2 item 1(a) says the
/// server's kind mapper is deliberately extensible and OSQ-7 already added a fourth kind
/// after the first three were written. So [unknown] is a real member, not an error state:
/// §3's default-arm clause says a kind the client does not recognise "renders as plain
/// text, never dropped and never thrown on", because a three-literal switch with no
/// fallback would render nothing in the one surface whose whole job is to show everything.
enum TranscriptBlockKind {
  /// Assistant prose. The ONLY kind that renders as markdown.
  text,

  /// A tool invocation. Renders as a one-line collapsed chip (ruling Q2).
  toolCall,

  /// A tool's output. Collapsed and truncated, expandable (ruling Q2).
  toolResult,

  /// Model scratch text (OSQ-7, ruled 2026-09-27). Folded, expandable, monospace — never
  /// markdown. **The fourth KNOWN kind, not the default arm**: a build that routed it
  /// through the default would show it unfolded, which C5.22 fails on.
  thinking,

  /// Anything else the server sends. Plain text, always rendered.
  unknown;

  /// 🔴 THE WIRE NAMES, AND THEY ARE NOT THE DART NAMES. `tool_call` and `tool_result` are
  /// snake_case on the wire (§3's table) and camelCase here, so the mapping is explicit
  /// rather than a `.name` comparison that would silently stop matching.
  static TranscriptBlockKind fromWire( Object? raw ) => switch ( raw ) {
        "text"        => TranscriptBlockKind.text,
        "tool_call"   => TranscriptBlockKind.toolCall,
        "tool_result" => TranscriptBlockKind.toolResult,
        "thinking"    => TranscriptBlockKind.thinking,
        _             => TranscriptBlockKind.unknown,
      };

  /// True for the kinds that must NEVER go through a markdown renderer.
  ///
  /// ⚠️ THE CONCERN IS MANGLING, NOT INJECTION (§3, C4/B6 as one rule). A markdown renderer
  /// turns a raw file dump into markup: `#` becomes a heading, `*` a list, indentation a
  /// code block — so a diff or a config file renders wrong. Plain text is the safe arm
  /// because it cannot mangle and cannot execute.
  bool get isPlainText => this != TranscriptBlockKind.text;

  /// True for the kinds that arrive COLLAPSED (ruling Q2 + OSQ-7).
  bool get startsCollapsed =>
      this == TranscriptBlockKind.toolCall ||
      this == TranscriptBlockKind.toolResult ||
      this == TranscriptBlockKind.thinking;
}

/// One renderable unit of transcript.
class TranscriptBlock {
  final TranscriptBlockKind kind;

  /// The raw wire `kind`, kept even when it mapped to [TranscriptBlockKind.unknown].
  ///
  /// ⚠️ KEPT SO AN UNKNOWN KIND CAN BE *NAMED* ON SCREEN AND IN A BUG REPORT. Dropping it
  /// would leave the operator looking at text with no idea what the server called it, and
  /// whoever adds the fifth kind with no way to see it already arriving.
  final String? rawKind;

  final String text;

  /// The server already cut this block at its budget (§2 item 7).
  ///
  /// 🔴 THE FULL TEXT IS THEN ONLY AVAILABLE OVER REST, NOT IN MEMORY. C5.19 is the row
  /// that proves the client does not pretend otherwise: expanding a truncated block issues
  /// exactly one REST fetch and renders THAT response.
  final bool truncated;

  /// A tool block's name, when the server sent one — what the chip says.
  final String? name;

  /// This block's own byte offset in the source file, when the server supplies it. Used
  /// only to fetch a truncated block's full text; the frame's offsets drive sequencing.
  final int? offset;

  const TranscriptBlock( {
    required this.kind,
    required this.text,
    this.rawKind,
    this.truncated = false,
    this.name,
    this.offset,
  } );

  /// Parse one block.
  ///
  /// Ensures:
  ///     - never throws; a non-Map yields an empty [TranscriptBlockKind.unknown] block
  ///     - an absent or non-String `text` becomes "", so a renderer always has a String
  ///     - `truncated` is true only for a literal `true` — no coercion, for the same
  ///       reason `transcript_watchable` refuses it: a changed type is a changed contract
  factory TranscriptBlock.fromJson( Object? json ) {
    if ( json is! Map ) {
      return const TranscriptBlock( kind: TranscriptBlockKind.unknown, text: "" );
    }

    final rawKind   = json[ "kind" ];
    final rawText   = json[ "text" ];
    final truncated = json[ "truncated" ];
    final name      = json[ "name" ];
    final offset    = json[ "offset" ];

    return TranscriptBlock(
      kind      : TranscriptBlockKind.fromWire( rawKind ),
      rawKind   : rawKind is String ? rawKind : null,
      text      : rawText is String ? rawText : _stringify( rawText ),
      truncated : truncated is bool && truncated,
      name      : name is String && name.isNotEmpty ? name : null,
      offset    : offset is num ? offset.toInt() : null,
    );
  }

  /// A block whose text the server sent as structure rather than a string — a tool call's
  /// arguments, most likely. Rendered as pretty JSON rather than as `Instance of '_Map'`.
  static String _stringify( Object? raw ) {
    if ( raw == null ) return "";
    try {
      return const JsonEncoder.withIndent( "  " ).convert( raw );
    } on Object {
      // A cyclic or non-encodable value. `toString()` is worse than JSON and better than
      // nothing, and this surface's rule is that everything renders.
      return raw.toString();
    }
  }

  /// The block's size, for the ring buffer.
  ///
  /// 🔴 ONE SIZE FUNCTION, SHARED WITH THE SERVER'S DEFINITION (C8, paired with A-T7): the
  /// UTF-8 byte length of the text **after** server truncation. The server's cap and both
  /// clients' rings use that same definition, so "never exceeds its cap" means the same
  /// thing on each end. Counting Dart string length instead would under-count every
  /// non-ASCII byte and let the ring exceed a cap it believed it was honouring.
  int get sizeBytes => utf8.encode( text ).length;

  TranscriptBlock withText( String newText, { bool? truncated } ) => TranscriptBlock(
    kind      : kind,
    text      : newText,
    rawKind   : rawKind,
    truncated : truncated ?? this.truncated,
    name      : name,
    offset    : offset,
  );
}

/// `cc_transcript_append` — the streamed chunk.
class TranscriptAppend {
  final String? ccSessionId;
  final String? fileEpoch;

  /// 🔴 `offset` IS THE SEQUENCE NUMBER. There is no separate `seq` (§3). It is the byte
  /// offset in the source file, and [nextOffset] always lands at the end of a complete
  /// line.
  final int? offset;
  final int? nextOffset;

  final List<TranscriptBlock> blocks;
  final String? ts;

  const TranscriptAppend( {
    this.ccSessionId,
    this.fileEpoch,
    this.offset,
    this.nextOffset,
    this.blocks = const [],
    this.ts,
  } );

  factory TranscriptAppend.fromJson( Object? json ) {
    if ( json is! Map ) return const TranscriptAppend();

    final raw = json[ "blocks" ];

    return TranscriptAppend(
      ccSessionId : _str( json[ "cc_session_id" ] ),
      fileEpoch   : _str( json[ "file_epoch" ] ),
      offset      : _int( json[ "offset" ] ),
      nextOffset  : _int( json[ "next_offset" ] ),
      blocks      : raw is List
          ? raw.map( TranscriptBlock.fromJson ).toList( growable: false )
          : const [],
      ts          : _str( json[ "ts" ] ),
    );
  }
}

/// The `state` values `cc_transcript_state` can carry (§3, plus `refused`).
enum TranscriptStreamState {
  live,
  ended,
  rotated,

  /// The watch named an epoch that is no longer current.
  ///
  /// 🔴 NEVER SILENTLY REBASED. §3 (T15): the server does not start from 0 and does not
  /// honour the offset, because a silent rebase "would hand the client the whole new file
  /// labelled as its own continuation". The client clears and re-fetches.
  epochMismatch,

  /// The server refused the watch.
  ///
  /// ⚠️ EXPECTED, NOT EXCEPTIONAL (§5, F-Clayton-C6). The button only hides a refusal; the
  /// server is the gate. A stale roster, a role revoked between the poll and the tap, or a
  /// deep link all reach here. §3 names the wire shape as proposed, so a server that has
  /// not adopted it yet simply never sends this — and the REST 403 path covers the same
  /// ground.
  refused,

  /// A state this client does not know. Treated as terminal-but-quiet: no retry, because
  /// retrying against an unrecognised state is guessing.
  unknown;

  static TranscriptStreamState fromWire( Object? raw ) => switch ( raw ) {
        "live"           => TranscriptStreamState.live,
        "ended"          => TranscriptStreamState.ended,
        "rotated"        => TranscriptStreamState.rotated,
        "epoch_mismatch" => TranscriptStreamState.epochMismatch,
        "refused"        => TranscriptStreamState.refused,
        _                => TranscriptStreamState.unknown,
      };
}

/// `cc_transcript_state`.
class TranscriptStateFrame {
  final String?               ccSessionId;
  final String?               fileEpoch;
  final TranscriptStreamState state;
  final String?               rawState;

  /// The server's own words, when it gave a reason. Shown on the refusal screen (§5: "with
  /// the server's reason if one is given").
  final String? reason;

  const TranscriptStateFrame( {
    this.ccSessionId,
    this.fileEpoch,
    this.state = TranscriptStreamState.unknown,
    this.rawState,
    this.reason,
  } );

  factory TranscriptStateFrame.fromJson( Object? json ) {
    if ( json is! Map ) return const TranscriptStateFrame();

    final raw = json[ "state" ];

    return TranscriptStateFrame(
      ccSessionId : _str( json[ "cc_session_id" ] ),
      fileEpoch   : _str( json[ "file_epoch" ] ),
      state       : TranscriptStreamState.fromWire( raw ),
      rawState    : raw is String ? raw : null,
      reason      : _str( json[ "reason" ] ) ?? _str( json[ "detail" ] ),
    );
  }
}

/// A REST read's body — the backlog, a gap repair, a backwards page, or one block's full
/// text. One shape, because §3 gives them one shape.
class TranscriptBacklog {
  final String? fileEpoch;
  final int?    offset;
  final int?    nextOffset;
  final List<TranscriptBlock> blocks;

  /// True when the response reached the start of the current epoch, so "Load earlier" has
  /// nothing left to fetch and hides itself (C-7).
  ///
  /// ⚠️ A MISSING FIELD IS FALSE, WHICH KEEPS THE CONTROL VISIBLE. The alternative default
  /// hides "Load earlier" against a server that never sends the field, making the rest of
  /// the transcript unreachable — and hiding a control is the failure nobody reports.
  final bool atStart;

  const TranscriptBacklog( {
    this.fileEpoch,
    this.offset,
    this.nextOffset,
    this.blocks = const [],
    this.atStart = false,
  } );

  factory TranscriptBacklog.fromJson( Object? json ) {
    if ( json is! Map ) return const TranscriptBacklog();

    final raw     = json[ "blocks" ];
    final atStart = json[ "at_start" ] ?? json[ "at_epoch_start" ];

    return TranscriptBacklog(
      fileEpoch  : _str( json[ "file_epoch" ] ),
      offset     : _int( json[ "offset" ] ),
      nextOffset : _int( json[ "next_offset" ] ),
      blocks     : raw is List
          ? raw.map( TranscriptBlock.fromJson ).toList( growable: false )
          : const [],
      atStart    : atStart is bool && atStart,
    );
  }
}

String? _str( Object? v ) => v is String && v.isNotEmpty ? v : null;
int?    _int( Object? v ) => v is num ? v.toInt() : null;
