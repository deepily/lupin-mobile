import 'package:dio/dio.dart';

import 'fleet_models.dart';

/// Fleet Status — the read of `/api/arbiter/fleet-state` and the ONE write this
/// pane owns, `PUT /api/arbiter/fleet-size-cap`.
///
/// The auth interceptor registered in `service_locator.dart` injects the Bearer
/// token and refreshes on 401, so nothing here touches credentials — the same
/// house rule `DocRepository` follows.
///
/// 🔴 THIS PANE IS NOT READ-ONLY, AND THE PLAN SAID IT WAS IN TWO PLACES.
/// The pre-cascade draft called Fleet Status "the one pane that is genuinely
/// read-only on web too — no write path to port." The web store issues a PUT
/// (`FleetStatusStore.ts:189`) wired to a live slider
/// (`FleetStatusRenderer.ts:200-203`, `:315`), so the dial is a real write that
/// was nearly dropped on the floor.
class FleetRepository {
  static const String fleetStateEndpoint   = "/api/arbiter/fleet-state";
  static const String fleetSizeCapEndpoint = "/api/arbiter/fleet-size-cap";

  final Dio _dio;

  const FleetRepository( this._dio );

  /// Fetch the fleet composite.
  ///
  /// Ensures:
  ///     - a 2xx body is parsed, INCLUDING the `status: "unreachable"` envelope,
  ///       which the server returns as a 200 on purpose
  ///     - a non-2xx or transport failure raises [FleetApiException] carrying
  ///       the server's own `detail` when it supplied one
  ///
  /// 🔴 DO NOT COLLAPSE "UNREACHABLE" INTO AN EXCEPTION. They are different
  /// facts and the operator needs to tell them apart: an exception means this
  /// phone could not reach :7999, while the envelope means :7999 is fine and
  /// the :8001 arbiter is not. Both render an empty table; only one of them is
  /// a reason to go and restart something. [FleetComposite.isUnreachable]
  /// carries it.
  Future<FleetComposite> fetchState() async {
    try {
      final res = await _dio.get<Object?>(
        fleetStateEndpoint,
        options: Options( validateStatus: ( _ ) => true ),
      );
      final status = res.statusCode ?? 0;
      if ( status < 200 || status >= 300 ) {
        throw FleetApiException( _detailFrom( res.data, status ), statusCode: status );
      }
      return FleetComposite.fromJson( res.data );
    } on DioException catch ( e ) {
      throw FleetApiException( "Fleet state unavailable: ${ e.message ?? e.type.name }" );
    }
  }

  /// Read the fleet-size dial's current numbers.
  ///
  /// Ensures:
  ///     - returns the server's body on a 2xx
  ///     - raises [FleetApiException] on anything else
  Future<Map<String, Object?>> fetchSizeCap() async {
    try {
      final res = await _dio.get<Object?>(
        fleetSizeCapEndpoint,
        options: Options( validateStatus: ( _ ) => true ),
      );
      final status = res.statusCode ?? 0;
      if ( status < 200 || status >= 300 ) {
        throw FleetApiException( _detailFrom( res.data, status ), statusCode: status );
      }
      final body = res.data;
      return body is Map ? Map<String, Object?>.from( body ) : <String, Object?>{};
    } on DioException catch ( e ) {
      throw FleetApiException( "Fleet size cap unavailable: ${ e.message ?? e.type.name }" );
    }
  }

  /// Set the fleet-size cap.
  ///
  /// Requires:
  ///     - cap >= 1. The server declares `ge=1` on the body model
  ///       (`arbiter.py:232-241`) and refuses a smaller value with a 422 that
  ///       names the field.
  ///
  /// Ensures:
  ///     - PUTs `{"cap": <cap>}` to [fleetSizeCapEndpoint]
  ///     - 🔴 RETURNS THE SERVER'S RE-READ OF THE FILE, NOT THE VALUE POSTED
  ///     - raises [FleetApiException] on a refusal, carrying the server's detail
  ///
  /// 🔴 THE ANSWER IS THE SERVER'S RE-READ, AND THAT IS THE WHOLE POINT OF THIS
  /// METHOD RETURNING A BODY AT ALL (`FleetStatusStore.ts:185-188`). A dial that
  /// echoed the posted value would display a number the fleet is not enforcing.
  /// This was proven live on 2026-09-19: the cap sat at 5 against a fleet
  /// already at 6, so zero reviewers could be spawned; Rick moved it to 9 and
  /// all three spawns then succeeded. The spawn path reads the cap FRESH FROM
  /// DISK, so a dial move bites without bouncing the MCP — which is exactly why
  /// the displayed number has to be the one that was re-read, not the one that
  /// was sent.
  ///
  /// ⚠️ ON A REFUSAL THE CALLER MUST RE-READ LIVE STATE rather than leave the
  /// handle sitting at a number the operator never got
  /// (`FleetStatusStore.ts:203-206`). This method raises; the caller owns that
  /// re-read.
  ///
  /// ⚠️ THE UPPER BOUND IS NOT IN THE BODY MODEL and cannot be clamped here.
  /// The ceiling is `cc session fleet size cap maximum`, read at call time
  /// (`arbiter.py:236-239`), so a client-side constant would drift from the
  /// value actually enforced. Let the server refuse.
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

  /// The server's own `detail` when it sent one, else a status-bearing fallback.
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
/// Distinct from [FleetComposite.isUnreachable], which is the server telling us
/// in a 200 that IT cannot reach :8001.
class FleetApiException implements Exception {
  final String message;
  final int?   statusCode;

  const FleetApiException( this.message, { this.statusCode } );

  @override
  String toString() => statusCode == null
      ? "FleetApiException: $message"
      : "FleetApiException($statusCode): $message";
}
