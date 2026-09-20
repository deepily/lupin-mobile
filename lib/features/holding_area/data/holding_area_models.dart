/// Filer grouping and the batch controls' words.
///
/// ⚠️ THIS PANE IS DELIBERATELY NOT AN ACCORDION. The web source says so in as many
/// words — `notifications.js:14085`, *"IT IS NOT AN ACCORDION LISTENER"*. Each filer
/// group is its own block, not a collapsible section. Normalising it to the Task
/// List's shape would invent a collapse the pane does not have.
library;

import '../../fleet/data/task_row_model.dart';

/// One filer's held rows.
class FilerGroup {
  /// The filer, EXACTLY as the store holds it — `created_by`, which is persona plus
  /// session hash ("mr radio 078b97cb").
  final String filer;

  /// The rows this filer filed, in the order the server returned them.
  final List<TaskRowModel> rows;

  const FilerGroup( { required this.filer, required this.rows } );

  int get count => rows.length;

  /// The ids this group's batch controls would act on. The blast radius as a value, so
  /// a caller cannot press approve-all and send a different set than the label counted.
  List<String> get ids => rows.map( ( r ) => r.id ).toList( growable: false );
}

/// Group held rows by filer.
///
/// 🔴 THE GROUPING KEY IS THE WHOLE `created_by` STRING, SESSION HASH INCLUDED, AND THAT
/// IS THE CONSERVATIVE READING RATHER THAN THE OBVIOUS ONE. Stripping the hash to group
/// by bare persona would merge one persona's sessions into a single group — fewer,
/// larger groups, and an approve-all whose blast radius is WIDER than the name on the
/// button suggests. Grouping by the stored string keeps what the batch acts on identical
/// to what the header displays. If the fleet wants per-persona grouping it is a ruling,
/// not a tidy-up, because it changes what one press does.
///
/// Requires:
///     - nothing; an empty list yields an empty list
///
/// Ensures:
///     - groups are ordered by filer name, case-insensitively, so the pane does not
///       reshuffle between repaints
///     - a row with no filer lands in a single trailing "Unattributed" group rather
///       than being dropped — a held row nobody can see is worse than an odd label
///     - row order WITHIN a group is the server's, untouched
List<FilerGroup> groupByFiler( List<TaskRowModel> rows ) {
  final byFiler = <String, List<TaskRowModel>>{};

  for ( final row in rows ) {
    final raw = row.createdBy;
    final key = ( raw != null && raw.trim().isNotEmpty ) ? raw.trim() : kUnattributedFiler;
    byFiler.putIfAbsent( key, () => [] ).add( row );
  }

  final named = byFiler.keys.where( ( k ) => k != kUnattributedFiler ).toList()
    ..sort( ( a, b ) => a.toLowerCase().compareTo( b.toLowerCase() ) );

  return [
    for ( final f in named ) FilerGroup( filer: f, rows: byFiler[ f ]! ),
    if ( byFiler.containsKey( kUnattributedFiler ) )
      FilerGroup( filer: kUnattributedFiler, rows: byFiler[ kUnattributedFiler ]! ),
  ];
}

/// Where a row with no filer goes. Named rather than inlined because both the grouper
/// and the tests have to agree on it.
const String kUnattributedFiler = "Unattributed";

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

// ── The approve-all confirm ──────────────────────────────────────────────────────
//
// 🔴 THE CONFIRM IS ON APPROVE-ALL, NOT ON WON'T-FIX-ALL, AND THAT INVERSION IS RICK'S
// RULING RATHER THAN AN OVERSIGHT. Won't-fix-all is gated by its REQUIRED REASON BOX —
// the operator has already had to type a justification, which is a slower and more
// deliberate act than dismissing a dialog. Approve-all had no gate at all, and its
// blast radius is every held row in the group at once.
//
// ⚠️ THE REASON BOX IS NOT A DIALOG, AND THE CONFIRM IS. They are different mechanisms
// for different jobs and swapping either one loses its point: the box has to be visible
// and fillable BEFORE the press, and the confirm has to interrupt a press that needs no
// typing at all.

/// The approve-all confirm's title.
const String kHoldingApproveAllConfirmTitle = "Approve every held row?";

/// The approve-all confirm's body. The count and the filer are the two facts that decide
/// the answer, so both are in the sentence rather than inferred from the pane behind it.
String holdingApproveAllConfirmBody( String filer, int count ) =>
    "$count row${count == 1 ? '' : 's'} filed by $filer move to queued. This is "
    "reversible — a row approved by mistake can be demoted straight back.";

/// The confirm's accept label. Repeats the verb rather than saying "OK", so the button
/// still reads correctly when it is the only thing focus lands on.
String holdingApproveAllConfirmAccept( int count ) => batchLabel( "Approve", count );

/// The confirm's dismiss label.
const String kHoldingApproveAllConfirmCancel = "Cancel";
