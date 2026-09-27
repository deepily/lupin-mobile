import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'fleet_models.dart';
import 'fleet_watchable_models.dart';

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

  /// The watchable-roster projection — §3's admin-gated read.
  ///
  /// 🔴 THIS PATH IS NOT FINAL, AND IT IS A CONSTANT SO THAT CHANGING IT IS ONE EDIT.
  /// §3's Open sub-question 6 is open on the REST naming: "transcript" already means
  /// speech-to-text on two other surfaces in this system (`/api/v2/transcribe`,
  /// `/upload-and-transcribe-{mp3,wav}`, and `transcript` as the name of an STT NDJSON
  /// line), so the path may move. It is María's to carry to Rick, not this client's to
  /// choose.
  ///
  /// TODO(OSQ-6): confirm against the server once phase 1 lands and the capture is taken.
  /// A wrong path is not a crash here — [fetchWatchable] reads any failure as "nothing is
  /// watchable" and every button hides, which is the safe direction but also a silent
  /// one. The captured-fixture arm of C5.9 is what will actually pin it.
  static const String watchableRosterEndpoint = "/api/arbiter/fleet-watchable";

  final Dio _dio;

  const FleetRepository( this._dio );

  /// Fetch the fleet composite.
  ///
  /// Ensures:
  ///     - a 2xx body is parsed, INCLUDING the `status: "unreachable"` envelope,
  ///       which the server returns as a 200 on purpose
  ///     - a non-2xx or transport failure raises [FleetApiException] carrying
  ///       the server's own `detail` when it supplied one
  ///     - a CANCELLED request rethrows the DioException unflattened, so the
  ///       caller can tell "the pane went away" from "the fetch failed"
  ///
  /// 🔴 DO NOT COLLAPSE "UNREACHABLE" INTO AN EXCEPTION. They are different
  /// facts and the operator needs to tell them apart: an exception means this
  /// phone could not reach :7999, while the envelope means :7999 is fine and
  /// the :8001 arbiter is not. Both render an empty table; only one of them is
  /// a reason to go and restart something. [FleetComposite.isUnreachable]
  /// carries it.
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
      // 🔴 A CANCELLATION IS NOT A FAILURE. The pane went away mid-request, and
      // flattening that into FleetApiException would have the bloc paint an
      // error on a surface nobody is looking at — and, worse, teach the reader
      // that the arbiter is down when it is not. Let it propagate.
      if ( e.type == DioExceptionType.cancel ) rethrow;
      throw FleetApiException( "Fleet state unavailable: ${ e.message ?? e.type.name }" );
    }
  }

  /// Read the watchable roster — which seats THIS caller may open a console on.
  ///
  /// Requires:
  ///     - nothing. An older server, a non-admin caller and a transport failure are all
  ///       ordinary answers here, not error conditions
  ///
  /// Ensures:
  ///     - 🔴 NEVER THROWS, except to rethrow a cancellation. Every other outcome is
  ///       [FleetWatchableRoster.none] — `unavailable: true`, no rows, no button on any
  ///       row. §5 is explicit: "a missing field, a missing row, a 403 or a failed
  ///       projection call all read as **not watchable**, so the button hides rather than
  ///       offering a watch the server would refuse". This method is where that promise
  ///       is kept, which is why it does not follow [fetchState]'s raise-on-non-2xx shape
  ///     - a 200 carrying `{status: "unreachable"}` is parsed, not raised — the
  ///       projection inherits fleet-state's deliberate envelope, and A3.7 requires an
  ///       unreachable arbiter be distinguishable from an empty fleet
  ///     - a CANCELLED request rethrows the DioException unflattened, so the caller can
  ///       tell "the pane went away" from "there is nothing to watch"
  ///
  /// ⚠️ A SILENT FAILURE IS THE DESIGN HERE, AND THAT IS WORTH SAYING OUT LOUD BECAUSE
  /// IT IS THE SHAPE THIS PLAN HAS BEEN BITTEN BY THREE TIMES. The difference is that
  /// here the silence costs a hidden button rather than a wrong answer: the alternative —
  /// raising, and letting the pane paint an error — would break the fleet table for every
  /// non-admin operator over a feature they cannot use anyway. The `debugPrint` is so the
  /// next person wondering where their button went has a line to find.
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

  /// Read the fleet-size dial's current numbers.
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
