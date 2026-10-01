import 'package:dio/dio.dart';

import 'broadcast_models.dart';

/// The Broadcast pane's four doors: who is listening, send, acks, and missed acks.
///
/// There is no poll here, and that is the design. Acks ride `commons_broadcast_ack` on the
/// `notification_queue_update` socket stream this client already holds open. For this pane
/// socket-first is how the feature works. [drainMissedAcks] is not a poller. It fires on
/// resume and on reconnect, the two moments the socket is known to have missed something,
/// and never on a timer.
class BroadcastRepository {
  final Dio _dio;

  /// Creates the repository over the shared Dio.
  const BroadcastRepository( this._dio );

  /// The active-sessions path.
  static const activeSessionsPath = '/api/commons/active-sessions';

  /// The broadcast path.
  static const broadcastPath      = '/api/commons/broadcast-to-cc-sessions';

  /// The recent-history path, with an explicit limit of five.
  ///
  /// The server's default is 200 and the pane shows five. Taking the default would pull two
  /// hundred rows of live fleet traffic over a phone link. The number is in the path, so it
  /// is visible at the call site and not inherited from a default that can move.
  static const historyPath = '/api/commons/broadcast-history?limit=5';

  /// The ack read's scan limit, named here instead of inherited from the server.
  ///
  /// 500 is far above any plausible fleet fan-out. It is sent so a change to the server's
  /// default cannot silently alter what this pane asks for.
  static const ackLimit = 500;

  /// The path of the saved-acks read for one broadcast.
  ///
  /// The caller's key is the scope, so there is no user id in the path. The server registers
  /// this route before `/notifications/{user_id}/next` so that `broadcast-acks` is not
  /// captured as a user id, and its two segments depend on that order.
  static String ackDrainPath( String broadcastId ) =>
      '/api/notifications/broadcast-acks/$broadcastId?limit=$ackLimit';

  /// Fetches who would receive a broadcast sent right now.
  ///
  /// Ensures:
  ///   - an empty roster returns [ActiveSessionRoster.empty], never an exception, because
  ///     nobody listening is an answer and not a failure
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

  /// Fans a message out to every live session belonging to this user.
  ///
  /// Requires:
  ///   - message is non-empty; the Send button enforces this, and the server answers 400 if
  ///     it slips through, which becomes a [BroadcastException]
  ///
  /// Ensures:
  ///   - returns the server's own accounting, including [BroadcastSendResult.failedRecipients]
  ///   - a 429 becomes a [BroadcastRateLimited] carrying the server's Retry-After
  ///   - `require_ack` and `include_originator` are sent explicitly, not left to the
  ///     server's defaults, so a default change cannot silently alter this pane
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
          // Named, not defaulted. `include_originator: true` is why the sender's own seat
          // shows up in its own ack tally, which is surprising enough to be readable here
          // and not looked up in the server's model.
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

  /// Fetches recent commons traffic, for the Recent Activity strip.
  ///
  /// Ensures:
  ///   - a kill-switched endpoint (`disabled: true`) returns `disabled` with no entries,
  ///     not an error, since a feature the operator turned off is not a fault, and not a
  ///     bare empty list, since it is not "no activity" either
  ///   - an absent `disabled` key reads as enabled, which is how the live endpoint answers;
  ///     the key exists only in the disabled branch
  Future<BroadcastHistory> fetchHistory( { CancelToken? cancelToken } ) async {
    final Response<Map<String, dynamic>> res;
    try {
      res = await _dio.get<Map<String, dynamic>>( historyPath, cancelToken: cancelToken );
    } on DioException catch ( e ) {
      if ( CancelToken.isCancel( e ) ) rethrow;
      throw BroadcastException( 'could not read recent activity', cause: e );
    }

    final body = res.data ?? const <String, dynamic>{};
    if ( body[ 'disabled' ] == true ) return const BroadcastHistory( disabled: true );

    final entries = body[ 'entries' ];
    if ( entries is! List ) return const BroadcastHistory();

    return BroadcastHistory(
      entries : entries
          .whereType<Map>()
          .map( ( e ) => Map<String, dynamic>.from( e ) )
          .toList(),
    );
  }

  /// The recovery read: every ack this broadcast has collected, from the saved rows.
  ///
  /// It cannot use `/api/notifications/undelivered`, which skips anything already handed to
  /// a socket. An ack that landed while the app was open is marked delivered instantly, so
  /// that drain would recover zero. The acks endpoint does not filter on delivery state.
  ///
  /// Requires:
  ///   - broadcastId is the id the server returned from [send]
  ///
  /// Ensures:
  ///   - returns one ack per acking seat, the server's latest for that seat; the
  ///     latest-per-session fold is server-side
  ///   - a 200 carrying `acks: []` returns an empty list, since nobody acked is an answer
  ///   - any transport or server failure throws [BroadcastException], because a caller that
  ///     cannot tell "nobody acked" from "the read failed" will paint the first
  ///   - a cancellation propagates untranslated, as for the other three doors
  ///   - there is no truncation guard: `len == ackLimit` is not evidence of truncation,
  ///     because the limit caps the pre-fold row scan and the fold can only shrink the
  ///     result, so a guard would fire on a number that means nothing
  Future<List<BroadcastAck>> drainMissedAcks(
    String broadcastId, {
    CancelToken? cancelToken,
  } ) async {
    final Response<Map<String, dynamic>> res;
    try {
      res = await _dio.get<Map<String, dynamic>>(
        ackDrainPath( broadcastId ),
        cancelToken: cancelToken,
      );
    } on DioException catch ( e ) {
      if ( CancelToken.isCancel( e ) ) rethrow;
      throw BroadcastException( 'could not read the saved acks', cause: e );
    }

    final raw = ( res.data ?? const <String, dynamic>{} )[ 'acks' ];
    if ( raw is! List ) return const [];

    return raw
        .whereType<Map>()
        .map( ( e ) => BroadcastAck.fromSavedAck( Map<String, dynamic>.from( e ) ) )
        .whereType<BroadcastAck>()
        .toList();
  }

  static int? _retryAfter( Response<dynamic>? res ) {
    final raw = res?.headers.value( 'retry-after' );
    return raw == null ? null : int.tryParse( raw );
  }
}

/// A broadcast read or write that failed.
class BroadcastException implements Exception {
  /// A short description of what failed.
  final String message;

  /// The underlying error, usually a `DioException`.
  final Object? cause;

  /// Creates the exception.
  const BroadcastException( this.message, { this.cause } );

  @override
  String toString() => 'BroadcastException: $message'
      '${cause == null ? '' : ' (caused by $cause)'}';
}

/// The server is rate-limiting broadcasts for this user.
///
/// It is its own type, not a generic failure. "Slow down for 30 seconds" and "that did not
/// send" call for different words on screen. Collapsing them tells the operator to retype
/// a message the server already has an opinion about.
class BroadcastRateLimited implements Exception {
  /// The server's Retry-After, in seconds, or null when it sent none.
  final int? retryAfterSeconds;

  /// Creates the exception.
  const BroadcastRateLimited( { this.retryAfterSeconds } );

  @override
  String toString() => 'BroadcastRateLimited(retryAfter: $retryAfterSeconds)';
}
