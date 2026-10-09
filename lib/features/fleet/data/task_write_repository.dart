import 'package:dio/dio.dart';

/// The shared write surface for the task panes; both write doors live here.
///
/// Which door a control uses depends on what it changes, not which pane it is in.
///
///   Field door   PATCH /api/tasks/{id}              priority, owner_persona; never status
///   Status door  POST  /api/tasks/{id}/transition   every status verb an operator presses
///
/// Approve is a status change. The field door refuses `PATCH {status: "queued"}` with a 422,
/// because its body forbids keys it does not declare and `status` is not declared.
/// [patchFields] takes two named parameters and no map, so it cannot send `status`.
///
/// A 401 is not handled here. The shared Dio has a global auth interceptor that refreshes
/// on 401 (`lib/services/auth/auth_interceptor.dart`), and a second refresh path would
/// race it on a flaky connection.
class TaskWriteRepository {
  final Dio _dio;

  // The authenticated user's email, resolved at call time, not captured at construction:
  // a repository built before login, or kept across a re-login, would stamp writes with a
  // stale identity or none. It is injected so this layer stays testable and does not read
  // `AuthBloc` state.
  final String? Function() _actorEmail;

  /// Creates the repository over [_dio]; [actorEmail] supplies the signed-in email.
  const TaskWriteRepository( this._dio, { String? Function()? actorEmail } )
      : _actorEmail = actorEmail ?? _noActor;

  static String? _noActor() => null;

  /// The audit `actor` for a UI-originated edit: the signed-in email plus `(mobile)`.
  ///
  /// It is derived from the authenticated user, never a fixed literal. The `(mobile)`
  /// tag records which client made the edit. The audit trail can then tell two edits by
  /// one person apart, and the web's `(multiplexer)` would file phone writes as desktop
  /// ones. A blank email gives `anonymous (mobile)`, a safety net for a malformed token.
  /// Design: src/docs/decisions/README.md (R-TW-actor-derived)
  static String deriveActor( String? email ) {
    final id = ( email ?? '' ).trim();
    return id.isEmpty ? 'anonymous (mobile)' : '$id (mobile)';
  }

  /// The `status` value the server returns when the human has not yet approved a write.
  ///
  /// The browser client and the server pin the same string.
  static const awaitingHumanApproval = 'awaiting_human_approval';

  /// URL-encodes a task id; both doors use it.
  ///
  /// A raw and an encoded id are identical until the id contains `/`, `?` or `#`, and
  /// then the request lands on a different route. The test drives this with `a/b?c#d`.
  static String encodeId( String id ) => Uri.encodeComponent( id );

  // ─── Door 1: fields ──────────────────────────────────────────────────────────
  //
  /// Changes a row's priority or owner; `status` is not addressable here.
  ///
  /// Omitted parameters are not sent, so a field the caller did not name is never
  /// clobbered. Pass status changes to [transition].
  ///
  /// Requires:
  ///   - at least one of [priority] or [ownerPersona] is non-null
  ///
  /// Raises:
  ///   - ArgumentError when nothing is to be changed, before any request is made
  ///   - TaskWriteException when the request fails
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

    // Nothing to change is a caller bug, not a request.
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
  /// Applies one status verb.
  ///
  /// Build [verb] with a [TaskVerb] factory, which carries the per-verb extras.
  ///
  /// Raises:
  ///   - TaskWriteException when the request fails
  ///   - TaskAwaitingApprovalException when the server accepts for review (202) without
  ///     applying the change
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

  // Throws when a 2xx answer says the write is awaiting approval. `POST .../transition`
  // can answer 202 with `{"status": "awaiting_human_approval", "ticket_id": ...}`. Dio
  // throws only on non-2xx, so without this check the answer looks like a real approval
  // and the pane paints the row approved. Only the `status` field is tested, not a
  // substring: a row whose reason text mentions the marker is an ordinary success.
  // Throwing also routes into the optimistic-write rollback, which un-paints the row.
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

  // Provenance both doors carry: `authority` says a human decided and `actor` says which
  // human and from where. `authority: "user_direct"` is constant here, because every
  // write this class makes is a control an operator pressed; the store's audit trail keys
  // provenance off it, so a weaker value would make a decision read as automation.
  // Something automated writing through this class needs its own value. Sending only one
  // key gives an audit row that knows a person acted and cannot say who.
  Map<String, dynamic> _provenance() => <String, dynamic>{
        'authority' : 'user_direct',
        'actor'     : deriveActor( _actorEmail() ),
      };
}

/// The seven status verbs and the extras each must send.
///
/// Four are invisible from the endpoint summary:
///  - `park` sends `park_reason`, not `reason`; the other verbs use `reason`.
///  - `unpark` sends an explicit null `next_chase_ts`. Omitting the key is a different
///    request and only the explicit null clears it. A surviving chase date would
///    re-chase the operator about a row already back on their board.
///  - `fixed` is refused without a receipt. The server replaces the value with the
///    validated login identity, but the key must be present.
///  - The verbs that need a reason share one box and must not share one complaint; see [reasonPrompt].
class TaskVerb {
  /// The verb name, as listed in `kTaskVerbs`.
  final String name;

  /// The request body to send, before provenance is added.
  final Map<String, dynamic> payload;

  /// True for verbs a mis-tap cannot undo; the row arms these before firing.
  final bool terminal;

  const TaskVerb._( this.name, this.payload, { this.terminal = false } );

  /// Moves a held row to `queued`.
  factory TaskVerb.approve() =>
      const TaskVerb._( 'approve', <String, dynamic>{ 'to_status' : 'queued' } );

  /// Moves a parked row to `queued`, sending `next_chase_ts: null` explicitly.
  ///
  /// An omitted key would not clear the chase date.
  factory TaskVerb.unpark() => const TaskVerb._( 'unpark', <String, dynamic>{
        'to_status'     : 'queued',
        'next_chase_ts' : null,
      } );

  /// Parks a row until [nextChaseTs], with the reason under `park_reason`.
  factory TaskVerb.park( { required String parkReason, String? nextChaseTs } ) =>
      TaskVerb._( 'park', <String, dynamic>{
        'to_status'     : 'parked',
        'park_reason'   : parkReason,     // not `reason`: park uses its own key
        'next_chase_ts' : nextChaseTs,
      } );

  /// Sends a row back to `not_approved` until [nextChaseTs].
  factory TaskVerb.demote( { required String reason, String? nextChaseTs } ) =>
      TaskVerb._( 'demote', <String, dynamic>{
        'to_status'     : 'not_approved',
        'reason'        : reason,
        'next_chase_ts' : nextChaseTs,
      } );

  /// Drops a row with a reason.
  factory TaskVerb.drop( { required String reason } ) =>
      TaskVerb._( 'drop', <String, dynamic>{
        'to_status' : 'dropped',
        'reason'    : reason,
      } );

  /// Closes a row as `wont_fix` with a reason; terminal.
  factory TaskVerb.wontFix( { required String reason } ) =>
      TaskVerb._( 'wont_fix', <String, dynamic>{
        'to_status' : 'wont_fix',
        'reason'    : reason,
      }, terminal: true );

  /// Closes a row as `done` with an operator receipt and no reason; terminal.
  factory TaskVerb.fixed( { required String operatorAttestation } ) =>
      TaskVerb._( 'fixed', <String, dynamic>{
        'to_status'    : 'done',
        'receipt_refs' : <String, dynamic>{ 'operator_attestation' : operatorAttestation },
      }, terminal: true );

  /// The prompt for the shared reason box, per verb.
  ///
  /// Each reason-requiring verb gets its own wording. A generic "A reason is required"
  /// says which box to fill and nothing about what belongs in it.
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
  /// A short description naming the operation and the row.
  final String message;

  /// The underlying error, usually a `DioException`.
  final Object? cause;

  /// Creates the exception.
  const TaskWriteException( this.message, { this.cause } );

  @override
  String toString() => 'TaskWriteException: $message'
      '${cause == null ? '' : ' (caused by $cause)'}';
}

/// The 202 answer: accepted for review, not applied.
///
/// It is its own type so a caller cannot treat it as an ordinary failure and retry it.
/// The request succeeded and the change did not happen; pressing again files a second
/// ticket.
class TaskAwaitingApprovalException implements Exception {
  /// The row the write was made against.
  final String  taskId;

  /// The verb that was held for approval.
  final String  verb;

  /// The ticket the server filed for the approval, when it returned one.
  final String? ticketId;

  /// Creates the exception.
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
