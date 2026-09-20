import 'package:dio/dio.dart';

/// The shared write surface for the task panes. BOTH doors live here, once.
///
/// 🔴 THERE ARE TWO WRITE DOORS AND THEY ARE NOT INTERCHANGEABLE. Which door a control
/// needs is decided by WHAT IT CHANGES, never by which pane it sits in.
///
///   Field door   PATCH /api/tasks/{id}              priority, owner_persona — NEVER status
///   Status door  POST  /api/tasks/{id}/transition   every status verb an operator presses
///
/// Receipts: `tasks.py:2742` (field) · `tasks.py:1346` (transition) ·
/// `TaskListStore.ts:76-79`, `:282`, `:301` · `HoldingAreaStore.ts:313`, `:335`.
///
/// ⇒ APPROVE IS A STATUS CHANGE. A builder implementing approve as
/// `PATCH {status: "queued"}` gets a field door that silently ignores an unknown key —
/// a Holding Area that looks wired and changes nothing. The field door here physically
/// cannot send `status`: [patchFields] takes two named parameters and no map.
///
/// ⚠️ 401 IS NOT HANDLED HERE, DELIBERATELY. The shared Dio already carries a global
/// auth interceptor that refreshes on 401 (`auth_interceptor.dart:42`, registered at
/// `service_locator.dart:243`). A repository that also handled it would give the app two
/// refresh paths on one response — dead code at best, two racing refreshes on a flaky
/// connection at worst.
class TaskWriteRepository {
  final Dio _dio;

  const TaskWriteRepository( this._dio );

  /// The server's marker for "Rick has not been asked yet".
  ///
  /// Pinned browser-side and server-side together (`HoldingAreaStore.ts:65`,
  /// `task_store_tools.py:173`, `test_the_browser_202_marker_matches_the_server.py`).
  static const awaitingHumanApproval = 'awaiting_human_approval';

  /// 🔴 URL-ENCODE THE ID ON BOTH DOORS. A raw `$id` and an encoded one are
  /// byte-identical until the id carries `/`, `?` or `#` — at which point the request
  /// silently lands on a DIFFERENT ROUTE. `TaskListStore.ts:275-280`; that store shipped
  /// without it once. The test drives this with `a/b?c#d`.
  static String encodeId( String id ) => Uri.encodeComponent( id );

  // ─── Door 1: fields ──────────────────────────────────────────────────────────
  //
  /// Change a row's FIELDS. Exactly two keys are addressable, and `status` is not one
  /// of them — pass a status change to [transition] instead.
  ///
  /// Omitted parameters are not sent at all, so this never clobbers a field the caller
  /// did not name.
  Future<void> patchFields( {
    required String id,
    String? priority,
    String? ownerPersona,
  } ) async {
    final body = <String, dynamic>{
      if ( priority != null )     'priority'      : priority,
      if ( ownerPersona != null ) 'owner_persona' : ownerPersona,
      ..._provenance(),
    };

    // Nothing to change is a caller bug, not a request. Sending it would burn a
    // round-trip to assert nothing.
    if ( priority == null && ownerPersona == null ) {
      throw ArgumentError( 'patchFields called with no field to change (id=$id)' );
    }

    try {
      await _dio.patch<Map<String, dynamic>>( '/api/tasks/${encodeId( id )}', data: body );
    } on DioException catch ( e ) {
      throw TaskWriteException( 'field update failed for $id', cause: e );
    }
  }

  // ─── Door 2: status ──────────────────────────────────────────────────────────
  //
  /// Apply one status verb.
  ///
  /// Build the argument with a [TaskVerb] factory rather than by hand — the per-verb
  /// extras are the part no summary carries, and four of them are invisible from the
  /// endpoint alone.
  Future<void> transition( { required String id, required TaskVerb verb } ) async {
    final Response<Map<String, dynamic>> res;
    try {
      res = await _dio.post<Map<String, dynamic>>(
        '/api/tasks/${encodeId( id )}/transition',
        data : <String, dynamic>{ ...verb.payload, ..._provenance() },
      );
    } on DioException catch ( e ) {
      throw TaskWriteException( '${verb.name} failed for $id', cause: e );
    }

    _rejectPendingApproval( res, id: id, verb: verb.name );
  }

  /// 🔴 THE 202 TRAP — the one failure in this file that is completely silent.
  ///
  /// `POST …/transition` can answer **202** with
  /// `{"status": "awaiting_human_approval", "ticket_id": …}`. That is a 2xx, and Dio
  /// only throws on a non-2xx, so without this branch the answer arrives
  /// indistinguishable from a real approval and the pane paints the row approved.
  /// `HoldingAreaStore.ts:316-319` names it exactly: **a false FACT, not a false red.**
  ///
  /// ⚠️ TEST THE `status` FIELD, NEVER A SUBSTRING. A row whose own reason text happens
  /// to mention the marker is an ordinary success; a payload-wide match would call it
  /// pending (`HoldingAreaStore.ts:75-78`).
  ///
  /// Throwing is also what routes this into the optimistic-write rollback path, so the
  /// pane un-paints the row it had already repainted (§4.6).
  void _rejectPendingApproval(
    Response<Map<String, dynamic>> res, {
    required String id,
    required String verb,
  } ) {
    final status = res.data?[ 'status' ];
    if ( status == awaitingHumanApproval ) {
      throw TaskAwaitingApprovalException(
        taskId   : id,
        verb     : verb,
        ticketId : res.data?[ 'ticket_id' ]?.toString(),
      );
    }
  }

  /// Provenance both doors carry.
  ///
  /// `authority: "user_direct"` IS NOT DECORATION — the store's audit trail keys
  /// provenance off it, and recording it as anything weaker would make an operator's
  /// decision read as automation (`HoldingAreaStore.ts:302-305`). Every write this
  /// repository makes is a control an operator pressed, so the value is constant here;
  /// the day something automated writes through this class, it needs its own value and
  /// not a default.
  Map<String, dynamic> _provenance() => const <String, dynamic>{
        'authority' : 'user_direct',
      };
}

/// The seven status verbs and the extras each MUST send.
///
/// Source: `taskVerbs.ts:97-129` and `:292-320`. Four of these are invisible from any
/// summary of the endpoint, and each has drawn blood:
///
///  1. `park` sends **`park_reason`**, not `reason` — one verb out of five uses a
///     different key for the same text box (`taskVerbs.ts:301`).
///  2. `unpark` sends an **explicit null** `next_chase_ts`. Omitting the key is a
///     DIFFERENT REQUEST and only one of them clears (`taskVerbs.ts:304-313`). Rick
///     ruled this (row `03d3bf78`): a surviving chase date re-chases him about a row
///     already back on his board.
///  3. `fixed` is **refused without a receipt** (`taskVerbs.ts:315-319`). The multiplexer
///     shipped this exact bug once — picked the verb up in `709128d4` without the
///     receipt and every press was refused. The value is not trusted; the server
///     replaces it with the validated login identity. What matters is that the key is
///     present.
///  4. Five verbs share one reason box and **must not share one complaint** —
///     *"'A reason is required' is true of four of them and teaches none of them"*
///     (`taskVerbs.ts:160-165`). See [reasonPrompt].
class TaskVerb {
  final String name;
  final Map<String, dynamic> payload;

  /// True for verbs a mis-tap cannot undo. The row arms these before firing (§7.4).
  final bool terminal;

  const TaskVerb._( this.name, this.payload, { this.terminal = false } );

  factory TaskVerb.approve() =>
      const TaskVerb._( 'approve', <String, dynamic>{ 'to_status' : 'queued' } );

  /// Sends `next_chase_ts: null` EXPLICITLY. Do not "simplify" this to an omitted key.
  factory TaskVerb.unpark() => const TaskVerb._( 'unpark', <String, dynamic>{
        'to_status'     : 'queued',
        'next_chase_ts' : null,
      } );

  factory TaskVerb.park( { required String parkReason, String? nextChaseTs } ) =>
      TaskVerb._( 'park', <String, dynamic>{
        'to_status'     : 'parked',
        'park_reason'   : parkReason,     // NOT `reason` — see note 1
        'next_chase_ts' : nextChaseTs,
      } );

  factory TaskVerb.demote( { required String reason, String? nextChaseTs } ) =>
      TaskVerb._( 'demote', <String, dynamic>{
        'to_status'     : 'not_approved',
        'reason'        : reason,
        'next_chase_ts' : nextChaseTs,
      } );

  factory TaskVerb.drop( { required String reason } ) =>
      TaskVerb._( 'drop', <String, dynamic>{
        'to_status' : 'dropped',
        'reason'    : reason,
      } );

  factory TaskVerb.wontFix( { required String reason } ) =>
      TaskVerb._( 'wont_fix', <String, dynamic>{
        'to_status' : 'wont_fix',
        'reason'    : reason,
      }, terminal: true );

  /// Requires a receipt and sends NO reason.
  factory TaskVerb.fixed( { required String operatorAttestation } ) =>
      TaskVerb._( 'fixed', <String, dynamic>{
        'to_status'    : 'done',
        'receipt_refs' : <String, dynamic>{ 'operator_attestation' : operatorAttestation },
      }, terminal: true );

  /// The prompt for the shared reason box, per verb.
  ///
  /// 🔴 ONE STRING FOR ALL OF THEM TEACHES NONE OF THEM. Four verbs require a reason and
  /// a single "A reason is required" tells an operator which box to fill and nothing
  /// about what belongs in it.
  static String reasonPrompt( String verb ) {
    switch ( verb ) {
      case 'park'     : return 'Why is this not-now? The reason is kept with the row.';
      case 'demote'   : return 'Why is this going back for approval?';
      case 'drop'     : return 'Why is this being dropped without being done?';
      case 'wont_fix' : return "Why won't this be fixed? This closes the row for good.";
      default         : return 'Reason';
    }
  }
}

/// A write that did not land.
class TaskWriteException implements Exception {
  final String message;
  final Object? cause;

  const TaskWriteException( this.message, { this.cause } );

  @override
  String toString() => 'TaskWriteException: $message'
      '${cause == null ? '' : ' (caused by $cause)'}';
}

/// The 202 answer: accepted for review, NOT applied.
///
/// A distinct type rather than a flag, so a caller cannot treat it as an ordinary
/// failure and retry it — the request succeeded, the change did not happen, and pressing
/// again just files a second ticket.
class TaskAwaitingApprovalException implements Exception {
  final String  taskId;
  final String  verb;
  final String? ticketId;

  const TaskAwaitingApprovalException( {
    required this.taskId,
    required this.verb,
    this.ticketId,
  } );

  @override
  String toString() =>
      'TaskAwaitingApprovalException: $verb on $taskId is awaiting human approval'
      '${ticketId == null ? '' : ' (ticket $ticketId)'}';
}
