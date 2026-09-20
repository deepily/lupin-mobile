import 'package:dio/dio.dart';

import 'task_verbs.dart';

/// The Holding Area's two write doors, and the read that fills the pane.
///
/// 🔴 THERE ARE TWO WRITE DOORS AND THEY ARE NOT INTERCHANGEABLE. Which door a
/// control needs is decided by WHAT IT CHANGES, not by which pane it sits in:
///
///   · FIELD  — `PATCH /api/tasks/{id}` — `priority` and `owner_persona`, exactly
///              those two keys, and NEVER status.
///   · STATUS — `POST /api/tasks/{id}/transition` — every status verb.
///
/// ⇒ APPROVE IS A STATUS CHANGE. A builder implementing approve as
/// `PATCH {status: "queued"}` gets a field door SILENTLY IGNORING an unknown key —
/// a Holding Area that looks wired and changes nothing.
class HoldingAreaRepository {
  final Dio _dio;

  /// The persona this seat writes as. Derived once by the caller, not free text.
  final String Function() _actor;

  const HoldingAreaRepository( this._dio, this._actor );

  static const String tasksPath = "/api/tasks";

  /// The marker a 202 carries. Pinned to the server's own literal
  /// (`task_store_tools.py:173`), not spelled twice.
  static const String awaitingHumanApproval = "awaiting_human_approval";

  /// Read the held rows.
  ///
  /// ⚠️ `status=not_approved` IS THE WHOLE PANE. The store excludes those rows from
  /// an ordinary query by default, which is exactly why this pane exists. Dropping
  /// the parameter to "simplify" gives a pane that renders an empty list and looks
  /// like it works.
  Future<HoldingAreaPage> fetchHeld( { int limit = 500 } ) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        tasksPath,
        queryParameters: {
          "limit"          : limit,
          "unscoped_audit" : true,
          "status"         : "not_approved",
          // `terse=true` rather than `char_budget=0`: smaller ROWS, not fewer rows.
          // The pre-cascade recommendation to drop the budget returned ~24 of 500
          // silently, which contradicted the pane's own lazy list.
          "terse"          : true,
        },
      );
      final body = res.data ?? const {};
      final rows = ( body[ "tasks" ] as List? ) ?? const [];
      return HoldingAreaPage(
        rows      : rows.cast<Map<String, dynamic>>(),
        total     : body[ "total" ] as int?,
        truncated : body[ "truncated" ] as bool? ?? false,
        hasMore   : body[ "has_more" ] as bool? ?? false,
      );
    } on DioException catch ( e ) {
      throw HoldingAreaException( _refusal( e, "loading the holding area" ) );
    }
  }

  /// THE STATUS DOOR. Every verb the operator presses comes through here.
  ///
  /// Requires:
  ///     - verb is one of kTaskVerbs
  ///     - input carries the operator's text when the verb needs one
  ///
  /// Ensures:
  ///     - the id is URL-ENCODED. A raw and an encoded id are byte-identical until
  ///       the id carries `/`, `?` or `#`, at which point the request silently lands
  ///       on a DIFFERENT ROUTE. The web store shipped without it once.
  ///     - `actor` and `authority: "user_direct"` ride every write — the audit trail
  ///       keys provenance off authority, and anything weaker makes an operator's
  ///       decision read as automation
  ///     - a 202 is reported as PENDING, never as success (see below)
  ///
  /// Raises:
  ///     - ArgumentError before any request when a required input is blank, so a
  ///       blank never reaches the wire to come back as a 422
  Future<WriteOutcome> transition( {
    required String id,
    required TaskVerb verb,
    String? input,
    String? nextChaseTs,
  } ) async {
    final body = buildTransitionBody(
      verb        : verb,
      input       : input,
      nextChaseTs : nextChaseTs,
    )
      ..[ "actor" ]     = _actor()
      ..[ "authority" ] = "user_direct";

    try {
      final res = await _dio.post<dynamic>(
        "$tasksPath/${Uri.encodeComponent( id )}/transition",
        data: body,
      );
      final pending = _isAwaitingApproval( res.data );
      if ( pending != null ) return pending;
      return const WriteOutcome.ok();
    } on DioException catch ( e ) {
      return WriteOutcome.failed( _refusal( e, "the ${verb.label} verb" ) );
    }
  }

  /// THE FIELD DOOR. Exactly two keys, and never status.
  ///
  /// The Holding Area paints the shared row, so its priority Update and owner select
  /// reach a store here for the first time — they are not Task-List-only controls.
  ///
  /// Requires:
  ///     - at least one of priority or ownerPersona is supplied
  ///     - neither is a status; this door ignores an unknown key silently
  Future<WriteOutcome> patchFields( {
    required String id,
    String? priority,
    String? ownerPersona,
  } ) async {
    if ( priority == null && ownerPersona == null ) {
      throw ArgumentError( "patchFields needs priority or owner_persona" );
    }
    final body = <String, dynamic>{
      if ( priority != null )     "priority"       : priority,
      if ( ownerPersona != null ) "owner_persona"  : ownerPersona,
      "actor"     : _actor(),
      "authority" : "user_direct",
    };
    try {
      await _dio.patch<dynamic>( "$tasksPath/${Uri.encodeComponent( id )}", data: body );
      return const WriteOutcome.ok();
    } on DioException catch ( e ) {
      return WriteOutcome.failed( _refusal( e, "the field update" ) );
    }
  }

  /// 🔴 A 202 IS NOT AN APPROVAL.
  ///
  /// The asynchronous promotion path answers *"Rick has not been asked yet, here is a
  /// ticket"* — and that is a 2xx, so Dio does not throw. Without this branch the
  /// answer arrives indistinguishable from a real approval and the pane paints the
  /// row approved. **A false FACT, not a false red.**
  ///
  /// ⚠️ TEST THE `status` FIELD, NEVER A SUBSTRING. A row whose own reason text
  /// happens to mention the marker is an ordinary success; a payload-wide match would
  /// call it pending.
  WriteOutcome? _isAwaitingApproval( dynamic data ) {
    if ( data is! Map ) return null;
    if ( data[ "status" ] != awaitingHumanApproval ) return null;
    return WriteOutcome.pending(
      ticketId : "${data[ "ticket_id" ] ?? ""}",
      message  : "Waiting on Rick — he has not been asked yet.",
    );
  }

  String _refusal( DioException e, String what ) {
    final data = e.response?.data;
    if ( data is Map && data[ "detail" ] != null ) return "${data[ "detail" ]}";
    return "$what failed: ${e.message ?? e.type.name}";
  }
}

/// One page of held rows, carrying the truncation signals the plan requires be
/// SURFACED rather than swallowed.
class HoldingAreaPage {
  final List<Map<String, dynamic>> rows;
  final int?  total;
  final bool  truncated;
  final bool  hasMore;

  const HoldingAreaPage( {
    required this.rows,
    required this.total,
    required this.truncated,
    required this.hasMore,
  } );
}

/// The result of one write. PENDING is a first-class outcome, not a flavour of
/// success and not a flavour of failure.
class WriteOutcome {
  final bool    ok;
  final bool    pending;
  final String? ticketId;
  final String? message;

  const WriteOutcome.ok()
      : ok = true, pending = false, ticketId = null, message = null;

  const WriteOutcome.pending( { required this.ticketId, required this.message } )
      : ok = false, pending = true;

  const WriteOutcome.failed( this.message )
      : ok = false, pending = false, ticketId = null;
}

class HoldingAreaException implements Exception {
  final String message;
  const HoldingAreaException( this.message );
  @override
  String toString() => "HoldingAreaException: $message";
}
