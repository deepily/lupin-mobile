/// The Live Console's wire contract, as Dart.
///
/// It is one file because the contract is one thing, and a reader checking the client
/// against the plan should not assemble it from four. Every parse here is total: a
/// malformed frame yields a frame with nulls, never an exception. A socket frame arrives
/// on a stream with no caller to catch for it. A throw in a parser would kill the stream,
/// and the surface would silently show nothing. The fleet models follow the same rule.
library;

import 'dart:convert';

/// What a block is, which decides how it renders.
///
/// The server's kind mapper is open-ended, and a fourth kind was added after the first
/// three were written. So [unknown] is a real member, not an error state. A kind the
/// client does not recognise renders as plain text, never dropped and never thrown on. A
/// three-literal switch with no fallback would render nothing on the one surface whose
/// job is to show everything.
enum TranscriptBlockKind {
  /// Assistant prose; the only kind that renders as markdown.
  text,

  /// A tool invocation, rendered as a one-line collapsed chip.
  toolCall,

  /// A tool's output; collapsed and truncated, and expandable.
  toolResult,

  /// Model scratch text; folded, expandable and monospace, never markdown.
  ///
  /// It is the fourth known kind, not the default arm. A build that routed it through the
  /// default would show it unfolded.
  /// Design: src/docs/decisions/README.md (R-TR-thinking-kind)
  thinking,

  /// Anything else the server sends; plain text, always rendered.
  unknown;

  /// Maps a wire kind to its enum member; anything unrecognised is [unknown].
  ///
  /// The wire names are not the Dart names: `tool_call` and `tool_result` are snake_case on
  /// the wire and camelCase here. The mapping is explicit, because a `.name` comparison
  /// would silently stop matching.
  static TranscriptBlockKind fromWire( Object? raw ) => switch ( raw ) {
        "text"        => TranscriptBlockKind.text,
        "tool_call"   => TranscriptBlockKind.toolCall,
        "tool_result" => TranscriptBlockKind.toolResult,
        "thinking"    => TranscriptBlockKind.thinking,
        _             => TranscriptBlockKind.unknown,
      };

  /// True for the kinds that must never go through a markdown renderer.
  ///
  /// The concern is mangling, not injection. A markdown renderer turns a raw file dump into
  /// markup. A `#` becomes a heading, `*` a list and indentation a code block, so a diff or
  /// a config file renders wrong. Plain text cannot mangle and cannot execute.
  bool get isPlainText => this != TranscriptBlockKind.text;

  /// True for the kinds that arrive collapsed: tool calls, tool results and thinking.
  bool get startsCollapsed =>
      this == TranscriptBlockKind.toolCall ||
      this == TranscriptBlockKind.toolResult ||
      this == TranscriptBlockKind.thinking;
}

/// One renderable unit of transcript.
class TranscriptBlock {
  /// How the block renders.
  final TranscriptBlockKind kind;

  /// The raw wire `kind`, kept even when it mapped to [TranscriptBlockKind.unknown].
  ///
  /// It is kept so an unknown kind can be named on screen and in a bug report. Dropping it
  /// would leave the operator with text and no idea what the server called it. It would
  /// also give whoever adds the fifth kind no way to see it already arriving.
  final String? rawKind;

  /// The block text; empty when the server sent none.
  final String text;

  /// True when the server already cut this block at its budget.
  ///
  /// The full text is then available only over REST, not in memory. Expanding a truncated
  /// block issues exactly one REST fetch and renders that response.
  final bool truncated;

  /// A tool block's name, when the server sent one; it is what the chip says.
  final String? name;

  /// This block's own byte offset in the source file, when the server supplies it.
  ///
  /// It is used only to fetch a truncated block's full text; the frame's offsets drive
  /// sequencing.
  final int? offset;

  /// True for a `thinking` block the server sent with no text at all.
  ///
  /// Claude Code records most thinking as a signature with an EMPTY text, so there is
  /// nothing to fold or expand; the console says so instead of offering a chip that opens
  /// onto a blank body. A truncated block is never unrecorded: truncation means text exists.
  bool get isUnrecordedThinking =>
      kind == TranscriptBlockKind.thinking && !truncated && text.trim().isEmpty;

  /// Creates a block.
  const TranscriptBlock( {
    required this.kind,
    required this.text,
    this.rawKind,
    this.truncated = false,
    this.name,
    this.offset,
  } );

  /// Parses one block.
  ///
  /// Ensures:
  ///     - never throws; a non-Map yields an empty [TranscriptBlockKind.unknown] block
  ///     - an absent `text` becomes "", and structured `text` is rendered as JSON, so a
  ///       renderer always has a String
  ///     - `truncated` is true only for a literal `true`, with no coercion: a changed type
  ///       is a changed contract
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

  // A block whose text the server sent as structure, most likely a tool call's arguments,
  // is rendered as pretty JSON and not as `Instance of '_Map'`.
  static String _stringify( Object? raw ) {
    if ( raw == null ) return "";
    try {
      return const JsonEncoder.withIndent( "  " ).convert( raw );
    } on Object {
      // A cyclic or non-encodable value. `toString()` is worse than JSON and better than
      // nothing, and everything on this surface renders.
      return raw.toString();
    }
  }

  /// The block's size in bytes, for the ring buffer.
  ///
  /// It is the UTF-8 byte length of the text after server truncation, the server's own
  /// definition. The server's cap and both clients' rings then mean the same thing by
  /// "never exceeds its cap". Counting Dart string length would under-count every non-ASCII
  /// byte and let the ring exceed a cap it believed it was honouring.
  int get sizeBytes => utf8.encode( text ).length;

  /// Copies the block with new text and, optionally, a new truncated flag.
  TranscriptBlock withText( String newText, { bool? truncated } ) => TranscriptBlock(
    kind      : kind,
    text      : newText,
    rawKind   : rawKind,
    truncated : truncated ?? this.truncated,
    name      : name,
    offset    : offset,
  );
}

/// The `cc_transcript_append` frame: one streamed chunk of blocks.
class TranscriptAppend {
  /// The full id of the session the chunk belongs to.
  final String? ccSessionId;

  /// Identifies the current incarnation of the source file.
  final String? fileEpoch;

  /// The chunk's start offset, which is its sequence number; there is no separate `seq`.
  ///
  /// It is the byte offset in the source file, and [nextOffset] always lands at the end of a
  /// complete line.
  final int? offset;

  /// The offset where the next chunk should start.
  final int? nextOffset;

  /// The chunk's blocks, in file order.
  final List<TranscriptBlock> blocks;

  /// The server's timestamp for the chunk.
  final String? ts;

  /// Creates a chunk.
  const TranscriptAppend( {
    this.ccSessionId,
    this.fileEpoch,
    this.offset,
    this.nextOffset,
    this.blocks = const [],
    this.ts,
  } );

  /// Parses one frame; a non-Map yields an empty chunk.
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

/// The `state` values `cc_transcript_state` can carry, plus `refused`.
enum TranscriptStreamState {
  /// The session is streaming.
  live,

  /// The session has ended.
  ended,

  /// The source file rotated.
  rotated,

  /// The watch named an epoch that is no longer current.
  ///
  /// The server never silently rebases. It does not start from 0 and does not honour the
  /// offset. A rebase would hand the client the whole new file labelled as its own
  /// continuation. The client clears and re-fetches.
  epochMismatch,

  /// The server refused the watch.
  ///
  /// Refusal is expected, not exceptional: the button only hides a refusal and the server is
  /// the gate. A stale roster, a role revoked between the poll and the tap, or a deep link
  /// all reach here. The wire shape is proposed, so a server that has not adopted it never
  /// sends this, and the REST 403 path covers the same ground.
  refused,

  /// A state this client does not know.
  ///
  /// It is terminal but quiet: no retry, because retrying against an unrecognised state is
  /// guessing.
  unknown;

  /// Maps a wire state to its enum member; anything unrecognised is [unknown].
  static TranscriptStreamState fromWire( Object? raw ) => switch ( raw ) {
        "live"           => TranscriptStreamState.live,
        "ended"          => TranscriptStreamState.ended,
        "rotated"        => TranscriptStreamState.rotated,
        "epoch_mismatch" => TranscriptStreamState.epochMismatch,
        "refused"        => TranscriptStreamState.refused,
        _                => TranscriptStreamState.unknown,
      };
}

/// The `cc_transcript_state` frame.
class TranscriptStateFrame {
  /// The full id of the session the state is about.
  final String?               ccSessionId;

  /// Identifies the current incarnation of the source file.
  final String?               fileEpoch;

  /// The parsed state.
  final TranscriptStreamState state;

  /// The raw wire state, kept even when it parsed to [TranscriptStreamState.unknown].
  final String?               rawState;

  /// The server's own words, when it gave a reason; shown on the refusal screen.
  final String? reason;

  /// Creates a state frame.
  const TranscriptStateFrame( {
    this.ccSessionId,
    this.fileEpoch,
    this.state = TranscriptStreamState.unknown,
    this.rawState,
    this.reason,
  } );

  /// Parses one frame; a non-Map yields an unknown state.
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

/// A REST read's body: the backlog, a gap repair, a backwards page or one block's full text.
///
/// The four reads share one shape, so they share one class.
class TranscriptBacklog {
  /// Identifies the current incarnation of the source file.
  final String? fileEpoch;

  /// The offset where the returned blocks start.
  final int?    offset;

  /// The offset where the next read should start.
  final int?    nextOffset;

  /// The returned blocks, in file order.
  final List<TranscriptBlock> blocks;

  /// True when the response reached the start of the current epoch.
  ///
  /// "Load earlier" then has nothing left to fetch and hides itself. A missing field is
  /// false, which keeps the control visible. The opposite default would hide it against a
  /// server that never sends the field. The rest of the transcript would become
  /// unreachable, and nobody reports a hidden control.
  final bool atStart;

  /// Creates a backlog.
  const TranscriptBacklog( {
    this.fileEpoch,
    this.offset,
    this.nextOffset,
    this.blocks = const [],
    this.atStart = false,
  } );

  /// Parses one response body; a non-Map yields an empty backlog.
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
