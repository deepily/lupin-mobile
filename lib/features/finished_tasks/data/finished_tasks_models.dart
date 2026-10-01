/// Finished Tasks model layer: the wire row, the pane's constants and the pure derivations.
///
/// The pane reads `/api/tasks/events`, not `/api/tasks`.
/// The task store has no terminal-timestamp column, so `updated_ts` on `/api/tasks`
/// moves on every write and an amended old row would read as freshly finished.
/// `/api/tasks` also orders by `created_ts`, so a row finished minutes ago would sort
/// below every row created today.
/// `task_events` is append-only, one row per state change, and already newest first.
/// Design: src/docs/decisions/README.md (R-FT-events-door)
///
/// The pane does not use the shared task row.
/// It builds its own four-column table because its rows are `task_events`, which carry
/// no priority, blocked state, accountable manager or actions.
/// The widget test asserts the absence of the shared row.
library;

import '../../../core/text/persona_label.dart';

/// One row of `/api/tasks/events`, as the server serializes an event.
class FinishedTaskEvent {
  /// The event's id, used as the stable tiebreak when two events share a timestamp.
  final int       id;
  /// The id of the task the event belongs to.
  final String    itemId;
  /// When the transition happened, normalised to local time.
  final DateTime  ts;
  /// Who made the transition, shaped `<persona> <8-hex session>`, or null.
  final String?   actor;
  /// The transition, shaped `queued->done`, or null.
  final String?   transition;
  /// The reason recorded with the transition, or null.
  final String?   reason;
  /// The task's title at the time of the event.
  final String    title;

  /// Creates an event from already-parsed fields.
  const FinishedTaskEvent( {
    required this.id,
    required this.itemId,
    required this.ts,
    required this.actor,
    required this.transition,
    required this.reason,
    required this.title,
  } );

  /// Parses one wire row.
  ///
  /// Requires:
  ///     - json carries `id`, `item_id`, `ts` and `title`; the server populates all four
  ///
  /// Ensures:
  ///     - `ts` is parsed as UTC-aware and normalised to local for display maths
  ///     - `actor`, `transition` and `reason` are nullable and survive as null
  ///
  /// Raises:
  ///     - FormatException if `ts` is not ISO-8601
  factory FinishedTaskEvent.fromJson( Map<String, dynamic> json ) {
    return FinishedTaskEvent(
      id         : json[ "id" ] as int,
      itemId     : json[ "item_id" ] as String,
      ts         : DateTime.parse( json[ "ts" ] as String ),
      actor      : json[ "actor" ] as String?,
      transition : json[ "transition" ] as String?,
      reason     : json[ "reason" ] as String?,
      title      : json[ "title" ] as String,
    );
  }

  /// The status this event landed on, the right-hand side of `queued->done`.
  String get status => transitionTarget( transition );
}

// ── Constants ────────────────────────────────────────────────────────────────────

/// The three terminal statuses: `done`, `dropped` and `wont_fix`.
///
/// Leaving out `wont_fix` would make every row a batch won't-fix produces unreachable.
const List<String> kFinishedStatuses = [ "done", "dropped", "wont_fix" ];

/// The statuses lit by default: only `done`, so `dropped` and `wont_fix` start off.
///
/// This matches the web client's default selection.
/// Design: src/docs/decisions/README.md (R-FT-default-shown)
const List<String> kFinishedDefaultShown = [ "done" ];

/// The smallest window the slider allows, in days.
const int kFinishedWindowMinDays     = 1;
/// The largest window the slider allows, in days.
const int kFinishedWindowMaxDays     = 14;
/// The window the pane opens with, in days.
const int kFinishedWindowDefaultDays = 1;

/// What an absent measurement renders as.
///
/// An em dash rather than an empty cell, so a row with nothing recorded is visibly
/// different from a narrow column.
const String kFinishedUnmeasured = "—";

/// The most events requested per status in one fetch.
const int kFinishedPageLimit = 500;

/// How often the pane re-reads the server.
const Duration kFinishedPollInterval = Duration( seconds: 60 );

/// How a status presents: the glyph, the pill label and the pill's explanation.
class FinishedStatusFace {
  /// The glyph shown beside the label.
  final String icon;
  /// The pill's label.
  final String label;
  /// The pill's explanation.
  final String description;

  /// Creates a face from its three parts.
  const FinishedStatusFace( {
    required this.icon,
    required this.label,
    required this.description,
  } );
}

/// The face of each terminal status, keyed by status.
const Map<String, FinishedStatusFace> kFinishedStatusFaces = {
  "done": FinishedStatusFace(
    icon        : "✅",
    label       : "Done",
    description : "Rows that reached done. The only success terminal — there is no separate 'fixed' status.",
  ),
  "dropped": FinishedStatusFace(
    icon        : "🗑️",
    label       : "Dropped",
    description : "Rows closed as dropped.",
  ),
  "wont_fix": FinishedStatusFace(
    icon        : "🚫",
    label       : "Won't-fix",
    description : "Rows closed as won't-fix. Terminal, and deliberately NOT part of the default view.",
  ),
};

// ── Pure derivations ─────────────────────────────────────────────────────────────

/// Clamps a requested window into the supported range.
///
/// Ensures:
///     - returns an integer in [kFinishedWindowMinDays, kFinishedWindowMaxDays]
///     - a non-finite or unparseable value returns the default rather than throwing
int clampWindowDays( Object? value ) {
  final num? n = value is num ? value : num.tryParse( "${value ?? ''}" );
  if ( n == null || !n.isFinite ) return kFinishedWindowDefaultDays;
  if ( n < kFinishedWindowMinDays ) return kFinishedWindowMinDays;
  if ( n > kFinishedWindowMaxDays ) return kFinishedWindowMaxDays;
  return n.floor();
}

/// The `since` instant for a window, as the API's ISO-8601 parameter.
///
/// The conversion from days lives here only. The slider speaks days and the wire takes
/// an instant, so a second conversion elsewhere could disagree with this one.
String windowSinceIso( int days, DateTime now ) {
  final clamped = clampWindowDays( days );
  return now.toUtc().subtract( Duration( days: clamped ) ).toIso8601String();
}

/// A compact age for the When column.
///
/// Ensures:
///     - under an hour renders minutes ("7m")
///     - under a day renders hours, with minutes only when non-zero ("3h", "3h20m")
///     - a day or more renders whole days ("2d")
///     - a future timestamp clamps to "0m", because clock skew between phone and
///       server is ordinary and must not print "-3m"
///     - a null instant renders the em dash
String relativeAge( DateTime? then, DateTime now ) {
  if ( then == null ) return kFinishedUnmeasured;
  final mins = ( now.difference( then ).inMinutes ).clamp( 0, 1 << 30 );
  if ( mins < 60 ) return "${mins}m";
  final hours = mins ~/ 60;
  if ( hours < 24 ) return mins % 60 == 0 ? "${hours}h" : "${hours}h${mins % 60}m";
  return "${hours ~/ 24}d";
}

/// The persona alone, from an actor field shaped `<persona> <8-hex session>`.
///
/// The rule lives in `core/text/persona_label.dart`: strip a trailing session id.
/// A persona can be two words, so keeping only the first word would be wrong.
/// The em dash is this column's fallback for nobody, and the case stays as stored.
///
/// Ensures:
///     - a two-word persona with a trailing session id keeps both words
///     - a one-word persona with a trailing session id keeps its one word
///     - no trailing session id → the whole string, untouched
///     - null or empty → the em dash
String actorPersona( String? actor ) => personaLabel( actor, kFinishedUnmeasured );

/// The status a transition landed on, the right-hand side of "queued->done".
///
/// Ensures:
///     - returns "" for an absent or malformed transition rather than throwing, so a
///       torn row renders untinted instead of taking the pane down
String transitionTarget( String? transition ) {
  if ( transition == null ) return "";
  final parts = transition.split( "->" );
  return parts.last;
}

/// Merges the lit statuses' events into one newest-first list.
///
/// Requires:
///     - shown is the currently lit status list
///
/// Ensures:
///     - only lit statuses contribute rows, while an unlit status's pill still shows
///       its own count so a pill's number never depends on whether it is lit
///     - sorted by ts descending, with the event id as a stable tiebreak so two events
///       sharing a timestamp do not swap places between repaints
///     - never mutates its input
List<FinishedTaskEvent> mergeShownEvents(
  Map<String, List<FinishedTaskEvent>> eventsByStatus,
  List<String> shown,
) {
  final merged = <FinishedTaskEvent>[];
  for ( final status in kFinishedStatuses ) {
    if ( !shown.contains( status ) ) continue;
    merged.addAll( eventsByStatus[ status ] ?? const [] );
  }
  merged.sort( ( a, b ) {
    final byTs = b.ts.compareTo( a.ts );
    return byTs != 0 ? byTs : b.id.compareTo( a.id );
  } );
  return merged;
}

/// Keeps a toggled selection in [kFinishedStatuses] order and never lets it empty.
///
/// Ensures:
///     - the returned order follows kFinishedStatuses, so the set round-trips
///     - turning off the last lit status is a no-op, because an empty selection reads
///       as a broken pane
List<String> toggleShownStatus( List<String> shown, String status ) {
  final next = shown.contains( status )
      ? shown.where( ( s ) => s != status ).toList()
      : [ ...shown, status ];
  if ( next.isEmpty ) return List.unmodifiable( shown );
  return List.unmodifiable(
    kFinishedStatuses.where( ( s ) => next.contains( s ) ).toList(),
  );
}
