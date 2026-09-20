/// The seven status verbs, and exactly what each one must send.
///
/// Source: `taskVerbs.ts:97-129` and `:292-320`, carried across rather than
/// re-derived. Four things in this table are invisible from any summary of it, and
/// each one has already cost someone a shipped bug:
///
///   1. `park` sends `park_reason`, NOT `reason` — one verb out of five uses a
///      different key for the same box (`taskVerbs.ts:301`).
///   2. `unpark` sends an EXPLICIT NULL. "Send nothing" and "send null" are different
///      requests and only one of them clears (`taskVerbs.ts:304-313`). Rick ruled it,
///      row 03d3bf78: a surviving chase date re-chases him about a row already back
///      on his board.
///   3. `fixed` is REFUSED without a receipt (`taskVerbs.ts:315-319`). The multiplexer
///      shipped this exact bug once — it picked the verb up in `709128d4` without the
///      receipt and every Fixed press was refused by the server. The value is not
///      trusted; the server replaces it with the validated login identity. What
///      matters is that the key is PRESENT.
///   4. Five verbs share one reason box and MUST NOT share one complaint — "'A reason
///      is required' is true of four of them and teaches none of them"
///      (`taskVerbs.ts:160-165`).
library;

/// What a verb needs from the operator before it can be sent.
enum VerbInput {
  /// Nothing — press and go.
  none,

  /// A free-text reason, sent as `reason`.
  reason,

  /// A free-text reason, sent as `park_reason` — `park` only.
  parkReason,

  /// An attestation string, sent as `receipt_refs.operator_attestation`.
  attestation,
}

class TaskVerb {
  /// The verb's id, as the operator's control names it.
  final String id;

  /// The button label.
  final String label;

  /// `to_status` on the transition door.
  final String toStatus;

  /// What the operator must supply first.
  final VerbInput input;

  /// True when the verb cannot be undone. A terminal verb ARMS before it fires.
  final bool terminal;

  /// The complaint shown when [input] is missing. Deliberately per-verb: five verbs
  /// share one box and "A reason is required" teaches none of them which.
  final String missingInputMessage;

  const TaskVerb( {
    required this.id,
    required this.label,
    required this.toStatus,
    required this.input,
    required this.terminal,
    required this.missingInputMessage,
  } );

  /// Whether this verb also sends an explicit `next_chase_ts`.
  bool get sendsChaseDate => id == "unpark" || id == "park" || id == "demote";
}

const List<TaskVerb> kTaskVerbs = [
  TaskVerb(
    id                  : "approve",
    label               : "Approve",
    toStatus            : "queued",
    input               : VerbInput.none,
    terminal            : false,
    missingInputMessage : "",
  ),
  TaskVerb(
    id                  : "unpark",
    label               : "Unpark",
    toStatus            : "queued",
    input               : VerbInput.none,
    terminal            : false,
    missingInputMessage : "",
  ),
  TaskVerb(
    id                  : "park",
    label               : "Park",
    toStatus            : "parked",
    input               : VerbInput.parkReason,
    terminal            : false,
    missingInputMessage : "Park needs a reason — say what this is waiting on.",
  ),
  TaskVerb(
    id                  : "demote",
    label               : "Demote",
    toStatus            : "not_approved",
    input               : VerbInput.reason,
    terminal            : false,
    missingInputMessage : "Demote needs a reason — say what sends it back.",
  ),
  TaskVerb(
    id                  : "drop",
    label               : "Drop",
    toStatus            : "dropped",
    input               : VerbInput.reason,
    terminal            : false,
    missingInputMessage : "Drop needs a reason — say why it is not being done.",
  ),
  TaskVerb(
    id                  : "wont_fix",
    label               : "Won't fix",
    toStatus            : "wont_fix",
    input               : VerbInput.reason,
    terminal            : true,
    missingInputMessage : "Won't-fix needs a reason — it is terminal and the reason is the record.",
  ),
  TaskVerb(
    id                  : "fixed",
    label               : "Fixed",
    toStatus            : "done",
    input               : VerbInput.attestation,
    terminal            : true,
    missingInputMessage : "Fixed needs your attestation — the server will not accept it without one.",
  ),
];

TaskVerb verbById( String id ) =>
    kTaskVerbs.firstWhere( ( v ) => v.id == id, orElse: () => throw ArgumentError.value( id, "id", "no such verb" ) );

/// Build the transition body for [verb].
///
/// Requires:
///     - input is the operator's text when the verb needs one
///     - nextChaseTs is supplied for the verbs that carry a chase date
///
/// Ensures:
///     - `to_status` is always present
///     - `park` carries `park_reason`; the other reason-taking verbs carry `reason`
///     - `unpark` carries `next_chase_ts: null` EXPLICITLY — the key is present with
///       a null value, because omitting it is a different request and does not clear
///     - `fixed` carries `receipt_refs.operator_attestation` and NO reason
///     - `actor` and `authority` are added by the repository, not here
///
/// Raises:
///     - ArgumentError when a required input is missing, so a blank never reaches the
///       wire to come back as a 422
Map<String, dynamic> buildTransitionBody( {
  required TaskVerb verb,
  String? input,
  String? nextChaseTs,
} ) {
  final trimmed = input?.trim() ?? "";
  if ( verb.input != VerbInput.none && trimmed.isEmpty ) {
    throw ArgumentError( verb.missingInputMessage );
  }

  final body = <String, dynamic>{ "to_status": verb.toStatus };

  switch ( verb.input ) {
    case VerbInput.none:
      break;
    case VerbInput.reason:
      body[ "reason" ] = trimmed;
    case VerbInput.parkReason:
      // 🔴 `park_reason`, not `reason`. One verb out of five uses a different key for
      // the same box, and sending `reason` here is accepted-and-ignored.
      body[ "park_reason" ] = trimmed;
    case VerbInput.attestation:
      // 🔴 The KEY must be present; the VALUE is not trusted — the server replaces it
      // with the validated login identity. Omitting it is a refusal, and that refusal
      // shipped once already.
      body[ "receipt_refs" ] = { "operator_attestation": trimmed };
  }

  if ( verb.id == "unpark" ) {
    // 🔴 AN EXPLICIT NULL, NOT AN OMISSION. "Send nothing" and "send null" are
    // different requests and only one of them clears the chase date. A surviving one
    // re-chases Rick about a row already back on his board.
    body[ "next_chase_ts" ] = null;
  } else if ( verb.sendsChaseDate && nextChaseTs != null ) {
    body[ "next_chase_ts" ] = nextChaseTs;
  }

  return body;
}
