/// Persona grouping and the batch controls' words.
///
/// 🔴 THIS PANE *WAS* DELIBERATELY NOT AN ACCORDION, AND RICK OVERRULED THAT ON
/// 2026-09-22 AFTER WALKING IT ON HARDWARE. The old note cited the web source —
/// `notifications.js:14085`, *"IT IS NOT AN ACCORDION LISTENER"* — and concluded that
/// each filer block renders open, always. His words, on seeing the result:
///
/// > *"I want to be able to toggle or collapse each individual persona's items… and I
/// > want them displayed folded by default so that we can do progressive disclosure.
/// > Otherwise it's just an enormous amount of text to scroll through to get to the one
/// > persona you're interested in."*
///
/// ⚠️ THE OLD NOTE WAS NOT WRONG ABOUT THE WEB; IT WAS WRONG ABOUT WHOSE QUESTION IT
/// WAS ANSWERING. "The multiplexer does not collapse here" is a fact about the
/// multiplexer, and Rick noted himself that NEITHER existing client has this. Parity
/// with a surface is the floor, not the ceiling.
///
/// ⇒ Groups collapse, and collapsed is the DEFAULT. The collapse state is the pane's,
/// not this file's — see `HoldingAreaState.expanded`.
library;

import '../../../core/text/persona_label.dart';
import '../../fleet/data/task_row_model.dart';

/// One filer's held rows.
class FilerGroup {
  /// The PERSONA who filed these rows, display-cased — "Mr Radio", never
  /// "mr radio 078b97cb".
  ///
  /// 🔴 THE SESSION HASH IS GONE FROM THIS VALUE ENTIRELY, WHICH IS RICK'S RULING R1=B
  /// AND NOT A TRUNCATION FOR LOOKS. *"I want you to group all sessions without any
  /// explicit labeling under each persona… I don't give a shit about your notion of
  /// session, it's irrelevant to me."* The session is not a user-facing concept on this
  /// surface, so it is not in the label, not in a subtitle, and not in a count.
  ///
  /// ⚠️ THIS DOUBLES AS THE STATE KEY — the batch reason, the complaint and the busy
  /// flag are all keyed on it — so it has to be stable across a poll. It is: it is a
  /// pure function of `created_by`.
  final String filer;

  /// The rows this filer filed, in the order the server returned them.
  final List<TaskRowModel> rows;

  const FilerGroup( { required this.filer, required this.rows } );

  int get count => rows.length;

  /// The ids this group's batch controls would act on. The blast radius as a value, so
  /// a caller cannot press approve-all and send a different set than the label counted.
  ///
  /// 🔴 UNDER R1=B THIS SPANS EVERY SESSION THAT PERSONA FILED FROM, AND THAT IS WHY THE
  /// COUNT HAS TO COME FROM HERE. Approve-all on "Mr Radio" now moves rows he filed from
  /// three different seats. That wider number is the correct one, and the walkthrough
  /// plan is explicit that it must be the number on the button and in the confirm:
  /// *"A batch control whose label undercounts what it does is a defect under any
  /// grouping scheme."* [count] and this list are the same rows by construction, so the
  /// label cannot drift from the send.
  List<String> get ids => rows.map( ( r ) => r.id ).toList( growable: false );
}

/// Group held rows by the PERSONA who filed them.
///
/// 🔴 THE GROUPING KEY IS THE PERSONA, SESSION HASH STRIPPED — RICK'S RULING R1=B,
/// 2026-09-22, AND IT REVERSES WHAT THIS FUNCTION USED TO DO. The old key was the whole
/// `created_by` string, and the reasoning behind it is worth keeping because it names
/// the hazard this version has to handle rather than one it gets to ignore:
///
/// > *"Stripping the hash to group by bare persona would merge one persona's sessions
/// > into a single group — fewer, larger groups, and an approve-all whose blast radius
/// > is WIDER than the name on the button suggests."*
///
/// ⚠️ EVERY WORD OF THAT IS STILL TRUE. What changed is that it is now the REQUESTED
/// behaviour, not an accident to be prevented: *"I want you to group all sessions
/// without any explicit labeling under each persona."* He also rejected the framing —
/// *"It's a bug because it does not mirror the behavior or the layout of the
/// multiplexer or the legacy notification client."*
///
/// ⇒ SO THE WIDER BLAST RADIUS IS HANDLED RATHER THAN AVOIDED, AND IT IS HANDLED
/// SOMEWHERE THIS FUNCTION CAN GUARANTEE: [FilerGroup.ids] and [FilerGroup.count] are
/// the same rows by construction, and every label the pane prints reads the count off
/// the group. A caller cannot show one number and send another.
///
/// 🔴 DO NOT REACH FOR `created_by.split( " " ).first`. A persona can be TWO WORDS, so
/// that renders "mr radio 8fa24215" as "mr" — measured wrong on 6 of 13 live rows in the
/// web client, and those six are exactly the ones this pane is for. The rule lives in
/// `core/text/persona_label.dart` precisely so it is not re-derived here.
///
/// ⚠️ THE KEY IS DISPLAY-CASED, AND THAT IS LOAD-BEARING RATHER THAN COSMETIC. The live
/// board holds "Krishna" and "maria" side by side — one store, two casing conventions.
/// Grouping on the raw persona would put "Krishna" and "krishna" in two groups, which is
/// the exact defect R1=B exists to remove, one level down.
///
/// Requires:
///     - nothing; an empty list yields an empty list
///
/// Ensures:
///     - every session of one persona lands in ONE group, and no session appears in the
///       label, a subtitle or a count
///     - groups are ordered by persona name, case-insensitively, so the pane does not
///       reshuffle between repaints
///     - a row with no filer lands in a single trailing "Unattributed" group rather
///       than being dropped — a held row nobody can see is worse than an odd label
///     - row order WITHIN a group is the server's, untouched. Rows from two sessions
///       therefore interleave exactly as the server returned them, which is the only
///       order this function is entitled to claim
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
