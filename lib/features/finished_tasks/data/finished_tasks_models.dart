/// Finished Tasks — the model layer: the wire row, the pane's constants, and the
/// pure derivations the four columns are built from.
///
/// 🔴 THE DOOR IS `/api/tasks/events`, AND THAT IS RULING R5 RATHER THAN A
/// PREFERENCE. There is no terminal-timestamp column in the task store, so
/// `/api/tasks`'s `updated_ts` moves on EVERY write and an amended three-day-old row
/// reads as freshly finished; `/api/tasks` also orders by `created_ts`, so a row
/// finished ten minutes ago sorts below every row created today. `task_events` is
/// append-only, one row per state change, already `ts DESC`.
///
/// 🔴 THIS PANE DOES NOT USE THE SHARED ROW. It builds its own four-column table and
/// that is deliberate: its rows are `task_events`, which carry no `priority`, no
/// `blocked`, no `accountable` and no `actions`. The web source is structural about
/// it — `finishedTasksTable.ts` imports neither `rowSchema` nor `rowDisclosure`. The
/// widget test asserts this NEGATIVELY; see the note there for why.
library;

import '../../../core/text/persona_label.dart';

/// One row of `/api/tasks/events`, per the server's `_serialize_event`.
class FinishedTaskEvent {
  final int       id;
  final String    itemId;
  final DateTime  ts;
  final String?   actor;
  final String?   transition;
  final String?   reason;
  final String    title;

  const FinishedTaskEvent( {
    required this.id,
    required this.itemId,
    required this.ts,
    required this.actor,
    required this.transition,
    required this.reason,
    required this.title,
  } );

  /// Parse one wire row.
  ///
  /// Requires:
  ///     - json carries `id`, `item_id`, `ts` and `title`; the server's serializer
  ///       populates all four unconditionally
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

  /// The status this event landed on — the right-hand side of `queued->done`.
  String get status => transitionTarget( transition );
}

// ── Constants, carried from the web source rather than re-decided ────────────────

/// The three terminal statuses. **Three, not two** — the pre-cascade draft named
/// `done` and `dropped` and omitted `wont_fix`, which would make every row §8.4's
/// batch won't-fix produces unreachable: the operator closes a filer's group and then
/// cannot find what he closed.
const List<String> kFinishedStatuses = [ "done", "dropped", "wont_fix" ];

/// 🔴 ONLY `done` IS LIT BY DEFAULT — `dropped` is off too.
///
/// The work item's wording called out won't-fix as "the off-by-default pill", which
/// reads as done+dropped lit. The source disagrees (`finishedTasksModel.ts:67`,
/// `FINISHED_DEFAULT_SHOWN = [ "done" ]`) and the plan's §2 says the source wins where
/// the two differ. Confirmed with Tiffany before building rather than diverging
/// silently, because a silent divergence here reads as a bug later.
const List<String> kFinishedDefaultShown = [ "done" ];

const int kFinishedWindowMinDays     = 1;
const int kFinishedWindowMaxDays     = 14;
const int kFinishedWindowDefaultDays = 1;

/// What an absent measurement renders as. An em dash rather than an empty cell, so a
/// row with nothing recorded is visibly different from a narrow column.
const String kFinishedUnmeasured = "—";

const int kFinishedPageLimit = 500;

const Duration kFinishedPollInterval = Duration( seconds: 60 );

/// How a status presents: the glyph, the pill label, and the pill's explanation.
class FinishedStatusFace {
  final String icon;
  final String label;
  final String description;

  const FinishedStatusFace( {
    required this.icon,
    required this.label,
    required this.description,
  } );
}

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

/// Clamp a requested window into the supported range.
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
/// 🔴 THE ×24 LIVES HERE AND NOWHERE ELSE. The slider is the only thing in this
/// feature that speaks days; the wire keeps taking the instant it always took. Two
/// places doing this conversion is how a 14-day window becomes a 14-hour one in
/// exactly one of them.
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
///     - a FUTURE timestamp clamps to "0m" rather than going negative — clock skew
///       between the phone and the server is ordinary and must not print "-3m"
///     - a null or unparseable instant renders the em dash
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
/// 🔴 THE RULE ITSELF NOW LIVES IN `core/text/persona_label.dart`, AND THE MOVE IS THE
/// POINT RATHER THAN A TIDY-UP. Strip a TRAILING session id; never keep a leading word.
/// A persona can be TWO WORDS, so the obvious `split(" ").first` renders
/// "mr radio 8353ea70" as "mr" — measured wrong on 6 of 13 live rows, and those six are
/// exactly the ones this column is for. That naive form has already been written twice
/// in the web client and shipped to THIS VERY COLUMN once (row 4a06ded1). The Holding
/// Area's persona grouping needed the same rule a third time, which is the moment
/// María's 2026-09-07 ruling applies: extract it rather than re-derive it. The
/// measurement is kept here because it is what justifies the rule; the rule is kept
/// there because it is what a fourth caller will find.
///
/// ⚠️ THE EM DASH IS THIS COLUMN'S FALLBACK, NOT THE SHARED HELPER'S. `personaLabel`
/// takes the caller's own word for "nobody" — the Holding Area's is "Unattributed" —
/// so nothing about this column's spelling of it moved.
///
/// ⚠️ AND THE CASE STAYS THE STORE'S. This column reads the stored spelling; the
/// Holding Area's group headers display-case theirs. That split is deliberate and is
/// why `personaLabel` and `personaDisplayLabel` are two functions.
///
/// Ensures:
///     - "mr radio 8353ea70" → "mr radio"
///     - "krishna 420f5ec9"  → "krishna"
///     - no trailing session id → the whole string, untouched
///     - null or empty → the em dash
String actorPersona( String? actor ) => personaLabel( actor, kFinishedUnmeasured );

/// The status a transition landed on — the right-hand side of "queued->done".
///
/// Ensures:
///     - returns "" for an absent or malformed transition rather than throwing, so a
///       torn row renders untinted instead of taking the pane down
String transitionTarget( String? transition ) {
  if ( transition == null ) return "";
  final parts = transition.split( "->" );
  return parts.last;
}

/// Merge the LIT statuses' events into one newest-first list.
///
/// Requires:
///     - shown is the currently-lit status list
///
/// Ensures:
///     - only lit statuses contribute rows — an unlit status's rows are withheld
///       while its pill still shows its own count, because a pill's number must not
///       depend on whether it happens to be lit
///     - sorted by ts DESCENDING, with the event id as a stable tiebreak so two
///       events sharing a timestamp do not swap places between repaints
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

/// Keep a toggled selection in [kFinishedStatuses] order, and never let it empty.
///
/// Ensures:
///     - the returned order follows kFinishedStatuses, so the set round-trips
///     - turning off the last lit status is a no-op — an empty selection is a pane
///       deliberately showing nothing, which reads as a broken pane
List<String> toggleShownStatus( List<String> shown, String status ) {
  final next = shown.contains( status )
      ? shown.where( ( s ) => s != status ).toList()
      : [ ...shown, status ];
  if ( next.isEmpty ) return List.unmodifiable( shown );
  return List.unmodifiable(
    kFinishedStatuses.where( ( s ) => next.contains( s ) ).toList(),
  );
}
