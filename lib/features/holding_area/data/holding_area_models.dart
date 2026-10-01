/// Persona grouping and the words of the batch controls.
///
/// Groups collapse and start collapsed. The collapse state belongs to the pane, see
/// `HoldingAreaState.expanded`.
/// Design: src/docs/decisions/README.md
library;

import '../../../core/text/persona_label.dart';
import '../../fleet/data/task_row_model.dart';

/// One filer's held rows.
class FilerGroup {
  /// The persona who filed these rows, in display case, such as "Mr Radio".
  ///
  /// The session hash is never shown on this surface. The batch reason, the complaint
  /// and the busy flag are keyed on this value, so it must stay stable across a poll.
  /// Design: src/docs/decisions/README.md
  final String filer;

  /// The rows this filer filed, in the order the server returned them.
  final List<TaskRowModel> rows;

  const FilerGroup( { required this.filer, required this.rows } );

  int get count => rows.length;

  /// The ids the group's batch controls act on, from the same rows as [count].
  ///
  /// Approve-all can span several sessions of one persona, so the label and the send
  /// must read the same rows. Using this list and [count] keeps them equal.
  /// Design: src/docs/decisions/README.md
  List<String> get ids => rows.map( ( r ) => r.id ).toList( growable: false );
}

/// Groups held rows by the persona that filed them, one group per persona.
///
/// The key is the persona with the hash stripped, in display case, so "Krishna" and
/// "krishna" share a group. Do not use `split( " " ).first`: a persona can have two words.
/// Design: src/docs/decisions/README.md
///
/// Ensures:
///   - groups are ordered by persona name, ignoring case
///   - a row with no filer goes in one trailing "Unattributed" group, never dropped
///   - row order within a group is the server's order
List<FilerGroup> groupByFiler( List<TaskRowModel> rows ) {
  final byFiler = <String, List<TaskRowModel>>{};

  for ( final row in rows ) {
    final key = personaDisplayLabel( row.createdBy, kUnattributedFiler );
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

/// Name of the group that holds rows with no filer; the grouper and the tests share it.
const String kUnattributedFiler = "Unattributed";

// The batch controls' words. They are the controls' accessible names, passed to
// `Semantics( label: )` and `Semantics( hint: )`, because a phone has no hover for a
// `title` attribute. They are not a long-press sheet: a long press is a discovery
// gesture, and these texts are the only place that says approve-all is reversible and
// won't-fix-all is terminal.

/// Accessibility hint for the approve-all button; says that approving can be undone.
String holdingApproveAllHint( String filer ) =>
    "Approve every row $filer filed — reversible, a row approved by mistake can be "
    "demoted straight back";

/// Accessibility hint for the won't-fix-all button of one filer's group.
///
/// One reason is applied to every row in the group, so the hint says so. It points to
/// the per-row control for rows that need different reasons.
String holdingWontFixAllHint( String filer ) =>
    "Close every row $filer filed as won't-fix. TERMINAL, and every row gets the SAME "
    "reason — use the per-row control when the reasons differ";

/// Placeholder of the batch reason box, matching the web client's constant.
const String kHoldingWontFixReasonPlaceholder = "one reason, applied to every row below…";

/// Accessible name of the batch reason box, matching the web client's constant.
const String kHoldingWontFixReasonLabel = "Batch won't-fix reason";

/// Message shown when won't-fix-all is pressed with an empty reason box.
///
/// The client checks first so the server does not return one identical 422 per row.
const String kHoldingWontFixReasonMissing =
    "Won't-fix needs a reason — it is applied to every row in this group.";

/// Button label that carries the row count, such as "Approve (3)".
String batchLabel( String verb, int count ) => "$verb ($count)";

// The approve-all confirm. Won't-fix-all has none: its required reason box is its gate.
// The box must be visible and fillable before the press; the confirm interrupts a press
// that needs no typing.
// Design: src/docs/decisions/README.md

/// Title of the approve-all confirm dialog.
const String kHoldingApproveAllConfirmTitle = "Approve every held row?";

/// Body of the approve-all confirm, naming the filer and the row count.
String holdingApproveAllConfirmBody( String filer, int count ) =>
    "$count row${count == 1 ? '' : 's'} filed by $filer move to queued. This is "
    "reversible — a row approved by mistake can be demoted straight back.";

/// Accept label of the confirm; repeats the verb instead of "OK".
String holdingApproveAllConfirmAccept( int count ) => batchLabel( "Approve", count );

/// Dismiss label of the approve-all confirm.
const String kHoldingApproveAllConfirmCancel = "Cancel";
