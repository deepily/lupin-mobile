import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'fleet_models.dart';
import 'fleet_watchable_models.dart';

/// Fleet Status reads `/api/arbiter/fleet-state` and owns one write, the fleet-size cap.
///
/// The auth interceptor registered in `lib/services/service_locator.dart` adds the Bearer
/// token and refreshes on 401, so nothing here touches credentials.
///
/// The pane is not read-only: the cap dial issues `PUT /api/arbiter/fleet-size-cap`.
class FleetRepository {
  /// The fleet-state path.
  static const String fleetStateEndpoint   = "/api/arbiter/fleet-state";

  /// The fleet-size-cap path.
  static const String fleetSizeCapEndpoint = "/api/arbiter/fleet-size-cap";

  /// The admin-gated watchable-roster projection path.
  ///
  /// The path is not final: the REST naming is an open question with the lupin server,
  /// because "transcript" already names speech-to-text on other surfaces. It is a constant
  /// so changing it is one edit. A wrong path is not a crash; [fetchWatchable] reads any
  /// failure as "nothing is watchable" and every button hides, which is safe but silent.
  /// TODO: confirm the path against the server and pin it with a captured fixture.
  static const String watchableRosterEndpoint = "/api/arbiter/fleet-watchable";

  final Dio _dio;

  /// Creates the repository over the shared Dio.
  const FleetRepository( this._dio );

  /// Fetches the fleet composite.
  ///
  /// "Unreachable" is not an exception. An exception means this phone could not reach
  /// `:7999`; the envelope means `:7999` is fine and the `:8001` arbiter is not. Only the
  /// second is a reason to restart something, and [FleetComposite.isUnreachable] carries it.
  ///
  /// Ensures:
  ///     - a 2xx body is parsed, including the `status: "unreachable"` envelope (a 200)
  ///     - a non-2xx or transport failure raises [FleetApiException] with the server's
  ///       `detail` when it sent one
  ///     - a cancelled request rethrows the DioException unflattened, so the caller can
  ///       tell "the pane went away" from "the fetch failed"
  Future<FleetComposite> fetchState( { CancelToken? cancelToken } ) async {
    try {
      final res = await _dio.get<Object?>(
        fleetStateEndpoint,
        cancelToken : cancelToken,
        options     : Options( validateStatus: ( _ ) => true ),
      );
      final status = res.statusCode ?? 0;
      if ( status < 200 || status >= 300 ) {
        throw FleetApiException( _detailFrom( res.data, status ), statusCode: status );
      }
      return FleetComposite.fromJson( res.data );
    } on DioException catch ( e ) {
      // A cancellation is not a failure: the pane went away mid-request. Flattening it into
      // FleetApiException would paint an error on a surface nobody is looking at and
      // suggest the arbiter is down. Let it propagate.
      if ( e.type == DioExceptionType.cancel ) rethrow;
      throw FleetApiException( "Fleet state unavailable: ${ e.message ?? e.type.name }" );
    }
  }

  /// Reads the watchable roster: which seats this caller may open a console on.
  ///
  /// An older server, a non-admin caller and a transport failure are ordinary answers.
  /// Failing silently costs a hidden button, where raising would break the fleet table for
  /// every non-admin. The `debugPrint` leaves a line to find when a button is missing.
  ///
  /// Ensures:
  ///     - never throws except to rethrow a cancellation
  ///     - a missing field or row, a 403 or a failed projection returns
  ///       [FleetWatchableRoster.none] (`unavailable: true`, no rows), so the button hides
  ///       instead of offering a watch the server would refuse
  ///     - a 200 carrying `{status: "unreachable"}` is parsed, not raised, so an
  ///       unreachable arbiter stays distinguishable from an empty fleet
  ///     - a cancelled request rethrows the DioException unflattened
  Future<FleetWatchableRoster> fetchWatchable( { CancelToken? cancelToken } ) async {
    try {
      final res = await _dio.get<Object?>(
        watchableRosterEndpoint,
        cancelToken : cancelToken,
        options     : Options( validateStatus: ( _ ) => true ),
      );
      final status = res.statusCode ?? 0;
      if ( status < 200 || status >= 300 ) {
        debugPrint(
          '[FleetWatchable] roster unavailable: HTTP $status '
          '(403 = not an admin, 404 = server predates the projection)',
        );
        return FleetWatchableRoster.none;
      }
      return FleetWatchableRoster.fromJson( res.data );
    } on DioException catch ( e ) {
      // A cancellation is the pane going away, not an answer about watchability.
      if ( e.type == DioExceptionType.cancel ) rethrow;
      debugPrint( '[FleetWatchable] roster unavailable: ${ e.message ?? e.type.name }' );
      return FleetWatchableRoster.none;
    }
  }

  /// Reads the fleet-size dial's current numbers.
  ///
  /// Ensures:
  ///     - returns the server's body on a 2xx
  ///     - raises [FleetApiException] on anything else
  Future<Map<String, Object?>> fetchSizeCap( { CancelToken? cancelToken } ) async {
    try {
      final res = await _dio.get<Object?>(
        fleetSizeCapEndpoint,
        cancelToken : cancelToken,
        options     : Options( validateStatus: ( _ ) => true ),
      );
      final status = res.statusCode ?? 0;
      if ( status < 200 || status >= 300 ) {
        throw FleetApiException( _detailFrom( res.data, status ), statusCode: status );
      }
      final body = res.data;
      return body is Map ? Map<String, Object?>.from( body ) : <String, Object?>{};
    } on DioException catch ( e ) {
      if ( e.type == DioExceptionType.cancel ) rethrow;
      throw FleetApiException( "Fleet size cap unavailable: ${ e.message ?? e.type.name }" );
    }
  }

  /// Sets the fleet-size cap and returns the server's re-read of it.
  ///
  /// The answer is the server's re-read of the file, not the value posted, so the dial
  /// never shows a number the fleet is not enforcing. The spawn path reads the cap fresh
  /// from disk, so a dial move takes effect without bouncing the MCP.
  ///
  /// Requires:
  ///     - cap >= 1; the server refuses a smaller value with a 422 naming the field
  ///     - no upper bound is checked here: the ceiling is the server's `cc session fleet
  ///       size cap maximum` setting, read at call time, so the server refuses instead
  ///
  /// Ensures:
  ///     - PUTs `{"cap": <cap>}` to [fleetSizeCapEndpoint]
  ///     - returns the server's re-read body
  ///     - raises [FleetApiException] on a refusal, carrying the server's detail; the
  ///       caller must then re-read live state, so the handle does not sit at a number
  ///       the operator never got
  Future<Map<String, Object?>> setSizeCap( int cap ) async {
    if ( cap < 1 ) {
      throw ArgumentError.value( cap, "cap", "must be >= 1" );
    }
    try {
      final res = await _dio.put<Object?>(
        fleetSizeCapEndpoint,
        data   : <String, Object?>{ "cap": cap },
        options: Options( validateStatus: ( _ ) => true ),
      );
      final status = res.statusCode ?? 0;
      if ( status < 200 || status >= 300 ) {
        throw FleetApiException( _detailFrom( res.data, status ), statusCode: status );
      }
      final body = res.data;
      return body is Map ? Map<String, Object?>.from( body ) : <String, Object?>{};
    } on DioException catch ( e ) {
      throw FleetApiException( "Fleet cap not saved: ${ e.message ?? e.type.name }" );
    }
  }

  // The server's own `detail` when it sent one, else a status-bearing fallback.
  ///
  /// Ensures:
  ///     - never returns an empty string, so a refusal always says something
  static String _detailFrom( Object? body, int status ) {
    if ( body is Map ) {
      final detail = body[ "detail" ];
      if ( detail is String && detail.isNotEmpty ) return detail;
    }
    return "HTTP $status";
  }
}

/// A transport or HTTP failure reaching the arbiter surfaces.
///
/// Distinct from [FleetComposite.isUnreachable], where the server says in a 200 that it
/// cannot reach `:8001`.
class FleetApiException implements Exception {
  /// The server's detail, or a status-bearing fallback.
  final String message;

  /// The HTTP status, or null for a transport failure.
  final int?   statusCode;

  /// Creates the exception.
  const FleetApiException( this.message, { this.statusCode } );

  @override
  String toString() => statusCode == null
      ? "FleetApiException: $message"
      : "FleetApiException($statusCode): $message";
}
