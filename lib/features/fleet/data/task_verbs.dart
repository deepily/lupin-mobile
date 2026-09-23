/// The verb table — which verbs exist, what each asks the operator for, and which of
/// them a row in a given status may legally take.
///
/// 🔴 PORTED FROM `taskVerbs.ts`, NOT RE-DERIVED. The payload shapes are SETTLED and a
/// second derivation is a second chance to get `park_reason` wrong. This file is the
/// pure half — no widgets, no Dio — exactly as its web twin is (no DOM, no store, no
/// fetch). [TaskVerb] in `task_write_repository.dart` already carries the payloads; this
/// adds the three things the panes need and the payload factories cannot answer:
/// what a verb ASKS FOR before it can be built, what it says when the operator leaves
/// that blank, and whether a row in a given status may take it at all.
///
/// ⚠️ `isOpenStatus` IS IMPORTED, NOT RE-SPELLED. The web file's own header says it in
/// as many words — *"DO NOT HAND-MAINTAIN THIS AGAINST THE MODULE. Two hand-written
/// copies of one vocabulary is what produced this row AND the un-park row … the same
/// defect in both directions inside one week."* A local `{ 'done', 'dropped',
/// 'wont_fix' }` here would be that second copy, and verb number eight would land on one
/// side only.
library;

import '../../task_list/data/task_list_model.dart' show isOpenStatus;
import 'task_write_repository.dart';

/// The verbs, in the fixed order they render in — the SHARED MODULE's order
/// (`taskVerbs.ts:97`).
///
/// ⚠️ THE ORDER IS NOT ALPHABETICAL AND NOT ARBITRARY. `fixed` sits between `wont_fix`
/// and `unpark` because that is where the shared module puts it; re-sorting this list
/// would make the mobile row offer the same seven verbs in a different order from every
/// other client, which reads to an operator as a different board.
const List<String> kTaskVerbs = <String>[
  'park', 'drop', 'demote', 'wont_fix', 'fixed', 'unpark', 'approve',
];

/// What one verb asks the operator for before it can be built.
///
/// 🔴 THIS TABLE IS THE POINT. Seven verbs share one sheet and they do NOT share one
/// obligation: four require a reason, two require a date, one requires a receipt and
/// nothing else, and two require nothing at all. A sheet that asked every verb for the
/// same thing would be a sheet that is wrong for six of them.
class VerbNeeds {
  /// The `to_status` the transition endpoint is asked for.
  final String name;

  /// The human name, for a button or a sheet title.
  final String label;

  /// True when a non-blank reason is required before the verb may be submitted.
  final bool reason;

  /// True when a chase / triage date is required.
  final bool date;

  /// The label the date field announces itself with; '' when there is no date.
  ///
  /// ⚠️ IT NAMES THE QUESTION, NOT THE FIELD THE SERVER STORES IT IN. Rick, on the web
  /// control: *"I really have no idea what the date chooser is for."* A control whose
  /// purpose the operator cannot infer is a defect in the control, so park asks
  /// "Chase me again on" rather than announcing itself as `next_chase_ts`.
  final String dateLabel;

  /// The reason box's hint while this verb is chosen.
  final String placeholder;

  /// True when the verb closes the row for good and earns the arm-then-confirm step
  /// (`taskVerbs.ts:116-117` — `terminal: true` is the shared module's `armsTwice`).
  final bool terminal;

  const VerbNeeds( {
    required this.name,
    required this.label,
    required this.reason,
    required this.date,
    required this.dateLabel,
    required this.placeholder,
    required this.terminal,
  } );

  /// True when this verb needs the operator to supply or acknowledge something before
  /// it can be sent — i.e. when pressing it must open the reason sheet.
  ///
  /// ⚠️ `fixed` REACHES HERE WITH `reason: false` AND STILL OPENS THE SHEET. It carries
  /// a receipt the operator is closing a row on, and a terminal write whose only visible
  /// step is a button is a terminal write nobody read. The sheet is where it says what
  /// will be recorded.
  bool get needsSheet => reason || date || terminal;
}

const Map<String, VerbNeeds> _needs = <String, VerbNeeds>{
  'park' : VerbNeeds(
    name        : 'park',
    label       : 'Park',
    reason      : true,
    date        : true,
    dateLabel   : 'Chase me again on',
    placeholder : 'quote the sentence that decided this…',
    terminal    : false,
  ),
  'drop' : VerbNeeds(
    name        : 'drop',
    label       : 'Drop',
    reason      : true,
    date        : false,
    dateLabel   : '',
    placeholder : 'why this is being dropped…',
    terminal    : false,
  ),
  'demote' : VerbNeeds(
    name        : 'demote',
    label       : 'Demote',
    reason      : true,
    date        : true,
    dateLabel   : 'Triage this by',
    placeholder : 'why this goes back to triage…',
    terminal    : false,
  ),
  'wont_fix' : VerbNeeds(
    name        : 'wont_fix',
    label       : "Won't fix",
    reason      : true,
    date        : false,
    dateLabel   : '',
    placeholder : 'why this will not be done…',
    terminal    : true,
  ),
  // FIXED. `reason: false` — a fix explains itself, and the shared module rejected a
  // mandatory note here as friction on the exact path Rick called too slow.
  // `terminal: true` because `done` is append-only and a misclick cannot be undone.
  'fixed' : VerbNeeds(
    name        : 'fixed',
    label       : 'Fixed',
    reason      : false,
    date        : false,
    dateLabel   : '',
    placeholder : 'Marking fixed needs no reason',
    terminal    : true,
  ),
  'unpark' : VerbNeeds(
    name        : 'unpark',
    label       : 'Un-park',
    reason      : false,
    date        : false,
    dateLabel   : '',
    placeholder : 'Un-parking needs no reason',
    terminal    : false,
  ),
  'approve' : VerbNeeds(
    name        : 'approve',
    label       : 'Approve',
    reason      : false,
    date        : false,
    dateLabel   : '',
    placeholder : 'Approve needs no reason',
    terminal    : false,
  ),
};

/// Look up one verb's obligations.
///
/// Requires:
///   - verb is a verb name, or null
///
/// Ensures:
///   - an unknown verb (including '' and null) returns null — never a partially
///     populated record, and never a throw
///   - a known verb returns its full obligation record
VerbNeeds? verbNeeds( String? verb ) {
  if ( verb == null || verb.isEmpty ) return null;
  return _needs[ verb ];
}

/// The human name of a verb.
///
/// Ensures: returns the verb itself when unknown, never null.
String verbLabel( String verb ) => _needs[ verb ]?.label ?? verb;

/// The refusal each verb earns when its reason is blank.
///
/// 🔴 FOUR VERBS SHARE ONE BOX AND MUST NOT SHARE ONE COMPLAINT. *"'A reason is
/// required' is true of four of them and teaches none of them"* (`taskVerbs.ts:160-165`):
/// park needs a QUOTE, demote must say why a row goes back to triage, and won't-fix is a
/// refusal whose justification is the only thing distinguishing it from work that got
/// forgotten.
///
/// Ensures: a verb-specific sentence for each of the four verbs that require a reason.
String verbReasonComplaint( String verb ) {
  switch ( verb ) {
    case 'drop'     : return 'A drop reason is required.';
    case 'park'     : return 'A park reason is required — quote the row\'s own decisive sentence.';
    case 'demote'   : return 'A demote reason is required — say why this goes back to triage, '
                             'or the next reader cannot tell it from a row that was never approved.';
    case 'wont_fix' : return 'A won\'t-fix reason is required — a refusal carries its '
                             'justification, exactly as a drop does.';
    default         : return 'A reason is required.';
  }
}

/// The refusal a verb earns when its required date is blank.
///
/// Park and demote are the only two that reach here, and they mean different things by a
/// date, so they say different things (`taskVerbs.ts:170-175`).
String verbDateComplaint( String verb ) => verb == 'park'
    ? 'A chase date is required — a park is bounded, never indefinite.'
    : 'A triage-by date is required — a held row is bounded, never indefinite. '
      'Use won\'t-fix to kill it outright.';

/// One verb's standing on one row: may it be chosen, and if not, why not.
class VerbLegality {
  final String    verb;
  final String    label;
  final bool      enabled;
  final VerbNeeds needs;

  /// Empty when enabled; otherwise the sentence the disabled control carries.
  final String why;

  const VerbLegality( {
    required this.verb,
    required this.label,
    required this.enabled,
    required this.needs,
    required this.why,
  } );
}

/// Which verbs a row in [status] may legally take.
///
/// 🔴 A TERMINAL ROW OFFERS NOTHING. `done` / `dropped` / `wont_fix` are append-only —
/// the server's `validate_transition` refuses every edge out of them.
///
/// ⚠️ APPROVE AND DEMOTE ARE OPPOSITE ENDS OF ONE DOOR, so exactly one of them is ever
/// live on a row. Approve is the holding area's exit (`not_approved → queued`); demote
/// is its entrance. Offering both hands the operator a move that is a no-op in one
/// direction, which the store rejects as a FAILURE rather than as nothing happening.
///
/// Requires:
///   - status is the row's status string, or null
///
/// Ensures:
///   - returns exactly [kTaskVerbs].length entries, in [kTaskVerbs] order
///   - a terminal row returns every entry disabled, each carrying the same append-only
///     sentence naming the row's own status
///   - park is enabled ONLY from queued / in_progress
///   - approve is enabled ONLY on a not_approved row; demote on every OTHER non-terminal
///     row
///   - drop, won't-fix and fixed are enabled on every non-terminal row
///   - un-park is enabled ONLY on a parked row
List<VerbLegality> verbLegality( String? status ) {
  final s          = ( status ?? '' ).toLowerCase();
  final isTerminal = !isOpenStatus( s.isEmpty ? null : s );
  final isHeld     = s == 'not_approved';
  final shown      = s.isEmpty ? 'unknown' : s;
  final dead       = 'this row is $shown; terminal rows are append-only and have no '
                     'transitions out';

  final parkLegal = !isTerminal && ( s == 'queued' || s == 'in_progress' );

  // Keyed on the STORED status. An EXPIRED park still reads `parked` here — expiry is
  // computed at read time by the store and never rewrites the row — so an expired park
  // is offered the verb too, which is the case Rick raised (row 49b87212).
  final isParked    = s == 'parked';
  final demoteLegal = !isTerminal && !isHeld;

  VerbLegality entry( String verb, bool enabled, String why ) {
    final needs = _needs[ verb ]!;
    return VerbLegality(
      verb    : verb,
      label   : needs.label,
      enabled : enabled,
      needs   : needs,
      why     : enabled ? '' : why,
    );
  }

  return <VerbLegality>[
    entry( 'park',     parkLegal,   isTerminal ? dead : 'only from queued or in progress' ),
    entry( 'drop',     !isTerminal, dead ),
    entry( 'demote',   demoteLegal, isTerminal ? dead : 'this row is already in the holding area' ),
    entry( 'wont_fix', !isTerminal, dead ),
    // Legal from every non-terminal status, exactly as drop and won't-fix are: the
    // shared module's spec carries `legalFrom: null, illegalFrom: null`, so nothing
    // narrows it. Marking a held row fixed is a real move — work can land before anyone
    // gets round to approving the ticket for it.
    entry( 'fixed',    !isTerminal, dead ),
    entry( 'unpark',   isParked,    isTerminal ? dead : 'only a parked row can be un-parked' ),
    entry( 'approve',  isHeld,      isTerminal ? dead : 'only a row in the holding area can be approved' ),
  ];
}

/// What this client sends as Fixed's operator attestation.
///
/// 🔴 THE VALUE IS NOT TRUSTED. The server refuses a `->done` with an empty receipt, then
/// REPLACES this string with the identity on the validated login before recording it
/// (`routers/tasks.py` `_resolved_operator_attestation`). THE KEY BEING PRESENT IS WHAT
/// MATTERS — the multiplexer picked the verb up in `709128d4` without it and every Fixed
/// press was refused by the server.
///
/// ⚠️ `(mobile)`, NOT `(multiplexer)`. The tag's only job is to record WHICH CLIENT made
/// the edit; a phone stamping `(multiplexer)` would file its writes as desktop ones —
/// the same reason [TaskWriteRepository.deriveActor] carries `(mobile)`.
const String kMobileOperatorAttestation = 'operator (mobile)';

/// Build the [TaskVerb] payload for [verb] from what the operator supplied.
///
/// 🔴 THE ONE PLACE A SHEET'S TEXT BECOMES A PAYLOAD. Every caller routes through here
/// rather than reaching for a factory directly, so `park_reason` versus `reason` is
/// decided once (note 1 of §4.3) and the explicit-null on un-park cannot be "simplified"
/// away by a caller who never read note 2.
///
/// Requires:
///   - verb is one of [kTaskVerbs]
///   - reason is the TRIMMED reason text, or null when the verb takes none
///   - chaseTs is the chosen instant, or null when the verb takes no date
///
/// Ensures:
///   - park's reason lands under `park_reason`; every other verb's under `reason`
///   - park and demote carry `next_chase_ts` as an ISO-8601 UTC instant
///   - fixed carries `receipt_refs.operator_attestation` and NO reason
///   - un-park carries an EXPLICIT null `next_chase_ts`
///
/// Raises:
///   - ArgumentError when verb is unknown, or when a verb that requires a reason or a
///     date is given a blank one — a caller that reaches the wire with an empty required
///     field has already lost the operator's edit
TaskVerb buildTaskVerb( String verb, { String? reason, DateTime? chaseTs } ) {
  final needs = verbNeeds( verb );
  if ( needs == null ) throw ArgumentError( 'unknown verb: $verb' );

  final text = ( reason ?? '' ).trim();
  if ( needs.reason && text.isEmpty ) {
    throw ArgumentError( '$verb requires a reason' );
  }
  if ( needs.date && chaseTs == null ) {
    throw ArgumentError( '$verb requires a chase date' );
  }

  // ⚠️ UTC AND ISO-8601, BECAUSE THE PHONE'S ZONE IS NOT THE SERVER'S. `DateTime.now()`
  // on a handset in Madrid and one in Boston serialise the same wall-clock differently,
  // and a chase date filed in local time re-chases at the wrong hour — or, across a date
  // boundary, on the wrong day.
  final chaseIso = chaseTs?.toUtc().toIso8601String();

  switch ( verb ) {
    case 'approve'  : return TaskVerb.approve();
    case 'unpark'   : return TaskVerb.unpark();
    case 'park'     : return TaskVerb.park( parkReason: text, nextChaseTs: chaseIso );
    case 'demote'   : return TaskVerb.demote( reason: text, nextChaseTs: chaseIso );
    case 'drop'     : return TaskVerb.drop( reason: text );
    case 'wont_fix' : return TaskVerb.wontFix( reason: text );
    case 'fixed'    : return TaskVerb.fixed( operatorAttestation: kMobileOperatorAttestation );
  }
  // Unreachable: `verbNeeds` already refused anything outside kTaskVerbs.
  throw ArgumentError( 'unknown verb: $verb' );
}
