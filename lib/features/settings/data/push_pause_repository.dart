import 'package:dio/dio.dart';

/// The server's global push pause, as `GET /api/fcm/push-pause` reports it.
class PushPauseState {
  /// Whether the server is currently holding back push notifications.
  final bool      paused;

  /// When the pause ends; null while paused means until resumed or the server restarts.
  final DateTime? resumesAt;

  /// Who set the pause, as the server names them.
  final String?   setBy;

  /// When the pause was set.
  final DateTime? setAt;

  /// Whether the server has push enabled at all; null when the server does not say.
  final bool?     pushEnabled;

  /// Creates a state; only [paused] is required.
  const PushPauseState( {
    required this.paused,
    this.resumesAt,
    this.setBy,
    this.setAt,
    this.pushEnabled,
  } );

  /// Reads the GET body into a state.
  ///
  /// Requires:
  ///     - json is the GET body; `resumes_at` and `set_at` are ISO-8601 or null
  ///
  /// Ensures:
  ///     - timestamps come back in the phone's local time zone, so the screen
  ///       shows the wall-clock time the user will see
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

/// A failed push-pause call, carrying the server's message and HTTP status.
class PushPauseException implements Exception {
  /// The server's `detail` text, or a local fallback.
  final String message;

  /// The HTTP status, or null when the request never got a response.
  final int?   statusCode;

  /// Creates an exception for [message] with an optional [statusCode].
  const PushPauseException( this.message, { this.statusCode } );

  /// 403: the signed-in user is not an admin, so the controls cannot work.
  bool get isAdminOnly => statusCode == 403;

  @override
  String toString() => "PushPauseException($statusCode): $message";
}

/// Pause and resume the server's push notifications to the phone.
///
/// It uses the shared Dio, whose auth interceptor supplies the Bearer token.
/// The pause lives in server memory and a restart clears it, so callers re-read
/// [getState] rather than trust a cached value.
class PushPauseRepository {
  /// The server path for reading and setting the pause.
  static const String path = "/api/fcm/push-pause";

  /// The longest pause in minutes; the server refuses anything longer with a 400.
  static const int maxMinutes = 1440;

  final Dio _dio;

  /// Creates a repository over the shared [Dio].
  const PushPauseRepository( this._dio );

  /// Reads the current pause state from the server.
  Future<PushPauseState> getState() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>( path );
      return PushPauseState.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, "Could not read the push pause" );
    }
  }

  /// Pauses push; a null [minutes] leaves the field out, so the pause lasts until resumed.
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

  /// Lifts the pause.
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
