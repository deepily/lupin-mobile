/// Filer grouping and the batch controls' words.
///
/// ⚠️ THIS PANE IS DELIBERATELY NOT AN ACCORDION. The web source says so in as many
/// words — `notifications.js:14085`, *"IT IS NOT AN ACCORDION LISTENER"*. Each filer
/// group is its own block, not a collapsible section. Normalising it to the Task
/// List's shape would invent a collapse the pane does not have.
library;

/// One filer's held rows.
class FilerGroup {
  /// The filer, as stored. Rendered through the persona rule at the use site.
  final String filer;

  /// The rows this filer filed, in the order the server returned them.
  final List<Map<String, dynamic>> rows;

  const FilerGroup( { required this.filer, required this.rows } );

  int get count => rows.length;
}

/// Group held rows by filer.
///
/// Requires:
///     - each row carries a `filer` or `created_by` value
///
/// Ensures:
///     - groups are ordered by filer name, case-insensitively, so the pane does not
///       reshuffle between repaints
///     - a row with no filer lands in a single trailing "Unattributed" group rather
///       than being dropped — a held row nobody can see is worse than an odd label
///     - row order WITHIN a group is the server's, untouched
List<FilerGroup> groupByFiler( List<Map<String, dynamic>> rows ) {
  const unattributed = "Unattributed";
  final byFiler = <String, List<Map<String, dynamic>>>{};

  for ( final row in rows ) {
    final raw = ( row[ "filer" ] ?? row[ "created_by" ] );
    final key = ( raw is String && raw.trim().isNotEmpty ) ? raw.trim() : unattributed;
    byFiler.putIfAbsent( key, () => [] ).add( row );
  }

  final named = byFiler.keys.where( ( k ) => k != unattributed ).toList()
    ..sort( ( a, b ) => a.toLowerCase().compareTo( b.toLowerCase() ) );

  return [
    for ( final f in named ) FilerGroup( filer: f, rows: byFiler[ f ]! ),
    if ( byFiler.containsKey( unattributed ) )
      FilerGroup( filer: unattributed, rows: byFiler[ unattributed ]! ),
  ];
}

// ── The batch controls' words ────────────────────────────────────────────────────
//
// 🔴 THESE ARE NOT TOOLTIPS. ON THE WEB THEY ARE `title` ATTRIBUTES AND A PHONE HAS
// NO HOVER, so carrying the buttons across without them silently drops the only
// place either risk is explained to the operator. They are the controls' NAMES, and
// they go into `Semantics( label: )` and `Semantics( hint: )`.
//
// ⚠️ NOT A LONG-PRESS SHEET. A long press is reachable under TalkBack, so it strands
// nobody — but it is a DISCOVERY gesture, and what it would hide is the only
// statement anywhere that approve-all is reversible and won't-fix-all is terminal.

/// Approve-all's promise. The reversibility is the justification for its lighter
/// gating, so the operator has to be able to read it.
String holdingApproveAllHint( String filer ) =>
    "Approve every row $filer filed — reversible, a row approved by mistake can be "
    "demoted straight back";

/// Won't-fix-all's warning.
///
/// 🔴 THE REASON IS PER GROUP, NOT PER ROW, AND THIS SAYS SO. Every row closed by one
/// press gets the SAME justification — honest for the case the batch exists to serve,
/// dishonest for a mixed group. The per-row control is the right tool whenever the
/// reasons differ; this one is deliberately the blunt instrument and is labelled as
/// such.
String holdingWontFixAllHint( String filer ) =>
    "Close every row $filer filed as won't-fix. TERMINAL, and every row gets the SAME "
    "reason — use the per-row control when the reasons differ";

/// The batch reason box's placeholder. Carbon copy of the web's pinned constant.
const String kHoldingWontFixReasonPlaceholder = "one reason, applied to every row below…";

/// The batch reason box's accessible name. Carbon copy.
const String kHoldingWontFixReasonLabel = "Batch won't-fix reason";

/// What the operator is told when they press won't-fix-all with an empty box.
///
/// ⚠️ THE CLIENT-SIDE CHECK EXISTS SO THE SERVER DOES NOT HAVE TO SAY IT N TIMES.
/// The web's reasoning, carried: *"the alternative is N identical 422s the operator
/// must read one at a time to learn a single fact."*
const String kHoldingWontFixReasonMissing =
    "Won't-fix needs a reason — it is applied to every row in this group.";

/// The blast radius, IN the label rather than two elements away from it.
///
/// The web prints the count in a span beside the filer name, so the operator reads
/// the number somewhere other than on the control they are about to press.
String batchLabel( String verb, int count ) => "$verb ($count)";
