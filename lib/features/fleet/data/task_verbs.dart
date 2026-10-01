/// The verb table: which verbs exist, what each asks for, and which a row may take.
///
/// This is the pure half, with no widgets and no Dio, mirroring the web's `taskVerbs.ts`.
/// [TaskVerb] in `task_write_repository.dart` carries the payloads. This file adds what a
/// verb asks for before it can be built. It also holds what it says when that is blank,
/// and whether a row in a given status may take the verb at all.
///
/// `isOpenStatus` is imported, not re-spelled. Two hand-written copies of one status
/// vocabulary drift apart, and a new verb would land on one side only.
library;

import '../../task_list/data/task_list_model.dart' show isOpenStatus;
import 'task_write_repository.dart';

/// The verbs, in the fixed order they render in, which is the shared module's order.
///
/// The order is not alphabetical: `fixed` sits between `wont_fix` and `unpark`. Re-sorting
/// it would offer the same seven verbs in a different order from every other client. To an
/// operator that reads as a different board.
const List<String> kTaskVerbs = <String>[
  'park', 'drop', 'demote', 'wont_fix', 'fixed', 'unpark', 'approve',
];

/// What one verb asks the operator for before it can be built.
///
/// The seven verbs share one sheet but not one obligation. Four require a reason and two
/// require a date. One requires a receipt and nothing else. Two require nothing.
class VerbNeeds {
  /// The verb name, which is also the `to_status` the transition endpoint is asked for.
  final String name;

  /// The human name, for a button or a sheet title.
  final String label;

  /// True when a non-blank reason is required before the verb may be submitted.
  final bool reason;

  /// True when a chase / triage date is required.
  final bool date;

  /// The label the date field announces itself with; empty when there is no date.
  ///
  /// It names the question the operator is answering, not the field the server stores:
  /// park asks "Chase me again on", not `next_chase_ts`.
  /// Design: src/docs/decisions/README.md (R-VN-date-label)
  final String dateLabel;

  /// The reason box's hint while this verb is chosen.
  final String placeholder;

  /// True when the verb closes the row for good and earns the arm-then-confirm step.
  ///
  /// This is the shared web module's `armsTwice`.
  final bool terminal;

  /// Creates one verb's obligations.
  const VerbNeeds( {
    required this.name,
    required this.label,
    required this.reason,
    required this.date,
    required this.dateLabel,
    required this.placeholder,
    required this.terminal,
  } );

  /// True when pressing the verb must open the reason sheet.
  ///
  /// That is when the operator must supply or acknowledge something first. `fixed` has
  /// `reason: false` and still opens the sheet. It closes the row on a receipt, and the
  /// sheet shows what will be recorded.
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
  // Fixed needs no reason: a fix explains itself, and a mandatory note would slow the
  // fastest path. It is terminal because `done` is append-only and cannot be undone.
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

/// Looks up one verb's obligations.
///
/// Requires:
///   - verb is a verb name, or null
///
/// Ensures:
///   - an unknown verb, including '' and null, returns null, never a partial record
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
/// The four reason-requiring verbs get separate complaints, because "A reason is
/// required" teaches none of them. Park needs a quote. Demote must say why the row goes
/// back to triage. A won't-fix reason is all that separates it from forgotten work.
///
/// Ensures: a verb-specific sentence for each verb that requires a reason.
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
/// Only park and demote reach here. They mean different things by a date, so they say
/// different things.
String verbDateComplaint( String verb ) => verb == 'park'
    ? 'A chase date is required — a park is bounded, never indefinite.'
    : 'A triage-by date is required — a held row is bounded, never indefinite. '
      'Use won\'t-fix to kill it outright.';

/// One verb's standing on one row: may it be chosen, and if not, why not.
class VerbLegality {
  /// The verb name.
  final String    verb;

  /// The human name for the control.
  final String    label;

  /// True when the verb may be chosen on this row.
  final bool      enabled;

  /// What the verb asks the operator for.
  final VerbNeeds needs;

  /// Empty when enabled; otherwise the sentence the disabled control carries.
  final String why;

  /// Creates one verb's standing on one row.
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
/// A terminal row offers nothing: the server refuses every transition out of `done`,
/// `dropped` and `wont_fix`. Approve exits the holding area and demote enters it, so only
/// one is live on a row. Offering both would give a no-op, which the store rejects.
///
/// Requires:
///   - status is the row's status string, or null
///
/// Ensures:
///   - returns exactly [kTaskVerbs].length entries, in [kTaskVerbs] order
///   - a terminal row returns every entry disabled, each with the same append-only
///     sentence naming the row's status
///   - park is enabled only from queued or in_progress
///   - approve is enabled only on a not_approved row
///   - demote is enabled on every other non-terminal row
///   - drop, won't-fix and fixed are enabled on every non-terminal row
///   - un-park is enabled only on a parked row
List<VerbLegality> verbLegality( String? status ) {
  final s          = ( status ?? '' ).toLowerCase();
  final isTerminal = !isOpenStatus( s.isEmpty ? null : s );
  final isHeld     = s == 'not_approved';
  final shown      = s.isEmpty ? 'unknown' : s;
  final dead       = 'this row is $shown; terminal rows are append-only and have no '
                     'transitions out';

  final parkLegal = !isTerminal && ( s == 'queued' || s == 'in_progress' );

  // Keyed on the stored status. The store computes park expiry at read time and never
  // rewrites the row, so an expired park still reads `parked` and is offered un-park.
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
    // Legal from every non-terminal status, as drop and won't-fix are: the shared module
    // narrows it nowhere. Marking a held row fixed is real, because work can land before
    // anyone approves its ticket.
    entry( 'fixed',    !isTerminal, dead ),
    entry( 'unpark',   isParked,    isTerminal ? dead : 'only a parked row can be un-parked' ),
    entry( 'approve',  isHeld,      isTerminal ? dead : 'only a row in the holding area can be approved' ),
  ];
}

/// What this client sends as Fixed's operator attestation.
///
/// The value is not trusted. The server refuses a `->done` with an empty receipt, then
/// replaces this string with the identity on the validated login before recording it. The
/// key must be present. The tag is `(mobile)`, not `(multiplexer)`, so a phone's writes
/// are not filed as desktop ones, as in [TaskWriteRepository.deriveActor].
const String kMobileOperatorAttestation = 'operator (mobile)';

/// Builds the [TaskVerb] payload for [verb] from what the operator supplied.
///
/// Every caller routes through here, so `park_reason` versus `reason` is decided once and
/// the explicit null on un-park cannot be simplified away.
///
/// Requires:
///   - verb is one of [kTaskVerbs]
///   - reason is the trimmed reason text, or null when the verb takes none
///   - chaseTs is the chosen instant, or null when the verb takes no date
///
/// Ensures:
///   - park's reason lands under `park_reason`; every other verb's under `reason`
///   - park and demote carry `next_chase_ts` as an ISO-8601 UTC instant
///   - fixed carries `receipt_refs.operator_attestation` and no reason
///   - un-park carries an explicit null `next_chase_ts`
///
/// Raises:
///   - ArgumentError when verb is unknown, or when a verb that requires a reason or a
///     date is given a blank one
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

  // UTC and ISO-8601, because the phone's zone is not the server's. A chase date filed in
  // local time re-chases at the wrong hour, or across a date boundary on the wrong day.
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
  // Unreachable: verbNeeds already refused anything outside kTaskVerbs.
  throw ArgumentError( 'unknown verb: $verb' );
}
