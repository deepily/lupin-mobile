import 'package:dio/dio.dart';

import 'broadcast_models.dart';

/// The Broadcast pane's four doors: who is listening, say it, what came back, and —
/// after the app stopped listening — what came back while it was away.
///
/// ⚠️ THERE IS STILL NO POLL HERE, AND THAT IS THE DESIGN RATHER THAN AN OMISSION. Acks
/// ride `commons_broadcast_ack` on the `notification_queue_update` socket stream this
/// client already holds open; for this one pane socket-first is how the feature works.
/// [drainMissedAcks] is not a poller — it fires on resume and on reconnect, the two
/// moments the socket is known to have missed something, and never on a timer. Any doc
/// text saying "all panes poll" is a doc defect.
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

  /// The server's own scan cap, named here rather than inherited (`notifications.py:2446`).
  /// 500 is far above any plausible fleet fan-out; it is sent so a change to the server's
  /// default cannot silently alter what this pane asks for.
  static const ackLimit = 500;

  /// 🔴 TWO SEGMENTS, AND THE ORDER OF THE SERVER'S ROUTES DEPENDS ON IT. This is
  /// registered BEFORE `/notifications/{user_id}/next` precisely so `broadcast-acks` is
  /// not captured as a user id (`notifications.py:2428-2430`). There is no user id in the
  /// path at all — the caller's key IS the scope.
  static String ackDrainPath( String broadcastId ) =>
      '/api/notifications/broadcast-acks/$broadcastId?limit=$ackLimit';

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
  ///   - a kill-switched endpoint (`disabled: true`) returns `disabled` with no entries
  ///     rather than an error, because a feature the operator turned off is not a
  ///     fault — and NOT a bare empty list, because it is not "no activity" either
  ///   - an absent `disabled` key reads as enabled, which is how the live endpoint
  ///     actually answers — the key exists only in the disabled branch
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

  /// The recovery read: every ack this broadcast has collected, from the SAVED rows.
  ///
  /// 🔴 THIS METHOD SPENT A PHASE AS A DOCUMENTED REFUSAL, AND THE REFUSAL WAS RIGHT AT
  /// THE TIME. The plan's §6.2 specified draining `/api/notifications/undelivered` and
  /// filtering `type == 'commons_broadcast_ack'`. That drain could not return an ack:
  /// the undelivered inbox skips anything already handed to a socket, and an ack that
  /// landed while the app was open is marked delivered instantly. A drain built on it
  /// would have run, folded nothing, and left every test green while recovering zero.
  ///
  /// ⇒ The server side landed (lupin row `1c7da903`). `GET /api/notifications/broadcast-acks/{id}`
  /// asks a different question — "which seats have acked this broadcast" — and
  /// `get_latest_acks_for_broadcast` (`notification_repository.py:653`) deliberately does
  /// NOT filter on delivery state. That is the whole reason the endpoint exists, and it
  /// is why this method can be honest now when it could not be before.
  ///
  /// Requires:
  ///   - broadcastId is the id the server returned from [send]
  ///
  /// Ensures:
  ///   - returns one ack per acking seat, the server's latest for that seat
  ///     (`notifications.py:2441-2492`; the latest-per-session fold is server-side)
  ///   - a 200 carrying `acks: []` returns an EMPTY LIST — nobody acked is an answer
  ///   - any transport or server failure throws [BroadcastException], because a caller
  ///     that cannot tell "nobody acked" from "the read failed" will paint the first
  ///   - a cancellation propagates untranslated, same as the other three doors
  ///
  /// ⚠️ NO TRUNCATION GUARD, AND ITS ABSENCE IS DELIBERATE. `len == ackLimit` is not
  /// evidence of truncation here: the limit caps the PRE-fold row scan and the
  /// latest-per-session fold can only shrink the result, so a full scan routinely
  /// answers with far fewer rows. A guard on that comparison would fire on a number
  /// that means nothing (row `973e4b6b`).
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
