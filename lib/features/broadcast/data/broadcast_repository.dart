import 'package:dio/dio.dart';

import 'broadcast_models.dart';

/// The Broadcast pane's three doors: who is listening, say it, and what came back.
///
/// ⚠️ THERE IS NO POLL HERE, AND THAT IS THE DESIGN RATHER THAN AN OMISSION. Acks ride
/// `commons_broadcast_ack` on the `notification_queue_update` socket stream this client
/// already holds open. For this one pane socket-first is not merely available — it is how
/// the feature works, and a poller would be a downgrade that also lies (see
/// [drainMissedAcks]). Any doc text saying "all panes poll" is a doc defect.
class BroadcastRepository {
  final Dio _dio;

  const BroadcastRepository( this._dio );

  static const activeSessionsPath = '/api/commons/active-sessions';
  static const broadcastPath      = '/api/commons/broadcast-to-cc-sessions';

  /// 🔴 AN EXPLICIT LIMIT, BECAUSE THE SERVER'S DEFAULT IS 200 AND THE PANE SHOWS FIVE.
  /// Taking the default pulls two hundred rows of live fleet traffic over a phone link
  /// to render a handful. The number is in the path so it is visible at the call site
  /// rather than inherited from a server default that can move underneath us.
  static const historyPath = '/api/commons/broadcast-history?limit=5';

  /// Who would receive a broadcast sent right now.
  ///
  /// Ensures:
  ///   - an empty roster returns [ActiveSessionRoster.empty], never an exception —
  ///     nobody listening is an answer, not a failure
  ///   - a cancellation propagates untranslated so the bloc can stay quiet about it
  Future<ActiveSessionRoster> fetchActiveSessions( { CancelToken? cancelToken } ) async {
    final Response<Map<String, dynamic>> res;
    try {
      res = await _dio.get<Map<String, dynamic>>( activeSessionsPath, cancelToken: cancelToken );
    } on DioException catch ( e ) {
      if ( CancelToken.isCancel( e ) ) rethrow;
      throw BroadcastException( 'could not read who is listening', cause: e );
    }

    return ActiveSessionRoster.fromJson( res.data ?? const <String, dynamic>{} );
  }

  /// Fan a message out to every live session belonging to this user.
  ///
  /// Requires:
  ///   - message is non-empty (the caller's Send button enforces this; the server
  ///     answers 400 if it slips through, which is translated below)
  ///
  /// Ensures:
  ///   - returns the server's own accounting, including [BroadcastSendResult.failedRecipients]
  ///   - a 429 becomes a [BroadcastRateLimited] carrying the server's Retry-After
  ///   - `require_ack` and `include_originator` are sent EXPLICITLY rather than left to
  ///     the server's defaults, so a default change cannot silently alter this pane
  Future<BroadcastSendResult> send( {
    required String message,
    String? broadcastId,
    bool requireAck        = true,
    bool includeOriginator = true,
    CancelToken? cancelToken,
  } ) async {
    final Response<Map<String, dynamic>> res;
    try {
      res = await _dio.post<Map<String, dynamic>>(
        broadcastPath,
        cancelToken : cancelToken,
        data : {
          'message'            : message,
          if ( broadcastId != null ) 'broadcast_id' : broadcastId,
          // 🔴 NAMED, NOT DEFAULTED. `include_originator: true` is why the sender's own
          // seat shows up in its own ack tally — surprising enough that it should be
          // readable here rather than looked up in the server's Pydantic model.
          'require_ack'        : requireAck,
          'include_originator' : includeOriginator,
        },
      );
    } on DioException catch ( e ) {
      if ( CancelToken.isCancel( e ) ) rethrow;

      final status = e.response?.statusCode;
      if ( status == 429 ) {
        throw BroadcastRateLimited( retryAfterSeconds: _retryAfter( e.response ) );
      }
      throw BroadcastException( 'the broadcast was not accepted', cause: e );
    }

    return BroadcastSendResult.fromJson( res.data ?? const <String, dynamic>{} );
  }

  /// Recent commons traffic, for the Recent Activity strip.
  ///
  /// Ensures:
  ///   - a kill-switched endpoint (`disabled: true`) returns an EMPTY list rather than
  ///     an error, because a feature the operator turned off is not a fault
  ///   - an absent `disabled` key reads as enabled, which is how the live endpoint
  ///     actually answers — the key exists only in the disabled branch
  Future<List<Map<String, dynamic>>> fetchHistory( { CancelToken? cancelToken } ) async {
    final Response<Map<String, dynamic>> res;
    try {
      res = await _dio.get<Map<String, dynamic>>( historyPath, cancelToken: cancelToken );
    } on DioException catch ( e ) {
      if ( CancelToken.isCancel( e ) ) rethrow;
      throw BroadcastException( 'could not read recent activity', cause: e );
    }

    final body = res.data ?? const <String, dynamic>{};
    if ( body[ 'disabled' ] == true ) return const [];

    final entries = body[ 'entries' ];
    if ( entries is! List ) return const [];

    return entries
        .whereType<Map>()
        .map( ( e ) => Map<String, dynamic>.from( e ) )
        .toList();
  }

  /// 🔴 THERE IS NO RECOVERY READ, AND THIS METHOD EXISTS TO SAY SO IN CODE.
  ///
  /// The plan's §6.2 specified draining `GET /api/notifications/undelivered` on resume
  /// and on socket reconnect, filtering `type == 'commons_broadcast_ack'`, and folding
  /// the result in. **That drain cannot return an ack.** `commons_broadcast_ack` is
  /// pushed in-process by the ack watcher and never crosses the `notify_user` route where
  /// `_persist_notification_sync` lives, so no row is written to the store that endpoint
  /// queries.
  ///
  /// The ack IS persisted — to a DIFFERENT store, `io_tbl`, via `push_notification`. That
  /// distinction matters and the earlier wording ("never persisted") was corrected on the
  /// row because it points at the wrong fix. But it does not help here: `_log_to_io_tbl`
  /// writes six fields and `payload` is never among them, and an ack's `message` is an
  /// empty string by design. So the io_tbl row for a broadcast ack is a type label and an
  /// empty string — not the broadcast, not the session, not the persona, not the status.
  ///
  /// ⇒ A drain implemented here would have run, returned nothing, folded nothing, and
  /// left every test green while recovering zero acks. Writing the method as a documented
  /// refusal is the only version of it that cannot be mistaken for working.
  ///
  /// ⇒ WHEN THE SERVER SIDE IS FIXED (lupin row `1c7da903`, Mr. Radio's), this becomes a
  /// real drain with an EXPLICIT limit above any plausible fan-out, and `len == limit`
  /// treated as possibly-truncated. Until then [AckAggregate.confidence] carries the
  /// truth instead.
  Never drainMissedAcks() {
    throw UnsupportedError(
      'Broadcast acks are not recoverable after the socket drops. '
      'See BroadcastRepository.drainMissedAcks and store row 384591dd.',
    );
  }

  static int? _retryAfter( Response<dynamic>? res ) {
    final raw = res?.headers.value( 'retry-after' );
    return raw == null ? null : int.tryParse( raw );
  }
}

class BroadcastException implements Exception {
  final String message;
  final Object? cause;

  const BroadcastException( this.message, { this.cause } );

  @override
  String toString() => 'BroadcastException: $message'
      '${cause == null ? '' : ' (caused by $cause)'}';
}

/// The server is rate-limiting broadcasts for this user.
///
/// ⚠️ ITS OWN TYPE, NOT A GENERIC FAILURE. "Slow down for 30 seconds" and "that did not
/// send" call for different words on screen, and collapsing them tells the operator to
/// retype a message the server already has an opinion about.
class BroadcastRateLimited implements Exception {
  final int? retryAfterSeconds;

  const BroadcastRateLimited( { this.retryAfterSeconds } );

  @override
  String toString() => 'BroadcastRateLimited(retryAfter: $retryAfterSeconds)';
}
