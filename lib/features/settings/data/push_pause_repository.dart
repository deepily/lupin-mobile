import 'package:dio/dio.dart';

/// The server's global push pause, as `GET /api/fcm/push-pause` reports it
/// (row 67ee93b0; design: lupin `2026.09.29-mobile-push-kill-switch-design.md`).
class PushPauseState {
  final bool      paused;

  /// Null while paused means "until resumed or the server restarts".
  final DateTime? resumesAt;
  final String?   setBy;
  final DateTime? setAt;
  final bool?     pushEnabled;

  const PushPauseState( {
    required this.paused,
    this.resumesAt,
    this.setBy,
    this.setAt,
    this.pushEnabled,
  } );

  /// Requires:
  ///     - json is the GET body; `resumes_at` / `set_at` are ISO-8601 or null
  ///
  /// Ensures:
  ///     - timestamps come back in the phone's local time zone, so the screen
  ///       shows the wall-clock time Rick will actually see
  factory PushPauseState.fromJson( Map<String, dynamic> json ) => PushPauseState(
    paused      : json["paused"] == true,
    resumesAt   : _time( json["resumes_at"] ),
    setBy       : json["set_by"] as String?,
    setAt       : _time( json["set_at"] ),
    pushEnabled : json["push_enabled"] as bool?,
  );

  static DateTime? _time( Object? v ) =>
      v is String ? DateTime.tryParse( v )?.toLocal() : null;
}

class PushPauseException implements Exception {
  final String message;
  final int?   statusCode;
  const PushPauseException( this.message, { this.statusCode } );

  /// 403: the signed-in user is not an admin, so the controls cannot work.
  bool get isAdminOnly => statusCode == 403;

  @override
  String toString() => "PushPauseException($statusCode): $message";
}

/// Pause and resume the server's push notifications to the phone.
///
/// Uses the shared Dio (its auth interceptor supplies the Bearer token). The
/// pause lives in server memory and a restart clears it, so callers must
/// re-read [getState] rather than trust a cached value.
class PushPauseRepository {
  static const String path = "/api/fcm/push-pause";

  /// The server refuses anything longer (400).
  static const int maxMinutes = 1440;

  final Dio _dio;
  const PushPauseRepository( this._dio );

  Future<PushPauseState> getState() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>( path );
      return PushPauseState.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, "Could not read the push pause" );
    }
  }

  /// Pause push. [minutes] null leaves the field out: paused until resumed.
  Future<void> pause( { int? minutes } ) async {
    try {
      await _dio.post<dynamic>( path, data: <String, dynamic>{
        "paused" : true,
        if ( minutes != null ) "minutes": minutes,
      } );
    } on DioException catch ( e ) {
      throw _err( e, "Could not pause push" );
    }
  }

  Future<void> resume() async {
    try {
      await _dio.post<dynamic>( path, data: <String, dynamic>{ "paused": false } );
    } on DioException catch ( e ) {
      throw _err( e, "Could not resume push" );
    }
  }

  PushPauseException _err( DioException e, String fallback ) {
    final sc   = e.response?.statusCode;
    final data = e.response?.data;
    final msg  = data is Map ? ( data["detail"]?.toString() ?? fallback )
                             : ( e.message ?? fallback );
    return PushPauseException( msg, statusCode: sc );
  }
}
