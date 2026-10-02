import 'package:dio/dio.dart';

/// The fleet's heartbeat stop poke switch, as `GET /api/heartbeat/poke-mute` reports it.
class HeartbeatPokeState {
  /// Whether the poke is muted; false means sessions are poked when they stop with work owed.
  final bool      muted;

  /// Who last flipped the switch, as the server names them.
  final String?   setBy;

  /// When the switch was last flipped.
  final DateTime? setAt;

  /// Creates a state; only [muted] is required.
  const HeartbeatPokeState( { required this.muted, this.setBy, this.setAt } );

  /// Reads the GET or PUT body into a state.
  ///
  /// Requires:
  ///     - json is the response body; `set_at` is ISO-8601 or null
  ///
  /// Ensures:
  ///     - anything other than a JSON `true` for `muted` reads as not muted, so a
  ///       malformed body never shows the poke as silenced
  ///     - `set_at` comes back in the phone's local time zone
  factory HeartbeatPokeState.fromJson( Map<String, dynamic> json ) => HeartbeatPokeState(
    muted : json["muted"] == true,
    setBy : json["set_by"] as String?,
    setAt : _time( json["set_at"] ),
  );

  static DateTime? _time( Object? v ) =>
      v is String ? DateTime.tryParse( v )?.toLocal() : null;
}

/// A failed poke-mute call, carrying the server's message and HTTP status.
class HeartbeatPokeException implements Exception {
  /// The server's `detail` text, or a local fallback.
  final String message;

  /// The HTTP status, or null when the request never got a response.
  final int?   statusCode;

  /// Creates an exception for [message] with an optional [statusCode].
  const HeartbeatPokeException( this.message, { this.statusCode } );

  /// 403: the signed-in user is not an admin, so the switch cannot be changed.
  bool get isAdminOnly => statusCode == 403;

  @override
  String toString() => "HeartbeatPokeException($statusCode): $message";
}

/// Read and flip the fleet's heartbeat stop poke.
///
/// It uses the shared Dio, whose auth interceptor supplies the Bearer token.
/// Any signed-in user may read; only an admin may write. The switch has no
/// timer: it stays where it was put until someone flips it back.
class HeartbeatPokeRepository {
  /// The server path for reading and setting the mute.
  static const String path = "/api/heartbeat/poke-mute";

  final Dio _dio;

  /// Creates a repository over the shared [Dio].
  const HeartbeatPokeRepository( this._dio );

  /// Reads the current switch state from the server.
  Future<HeartbeatPokeState> getState() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>( path );
      return HeartbeatPokeState.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, "Could not read the stop poke switch" );
    }
  }

  /// Mutes or unmutes the poke and returns the state the server answered with.
  Future<HeartbeatPokeState> setMuted( bool muted ) async {
    try {
      final res = await _dio.put<Map<String, dynamic>>(
          path, data: <String, dynamic>{ "muted": muted } );
      return HeartbeatPokeState.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _err( e, "Could not change the stop poke switch" );
    }
  }

  HeartbeatPokeException _err( DioException e, String fallback ) {
    final sc   = e.response?.statusCode;
    final data = e.response?.data;
    final msg  = data is Map ? ( data["detail"]?.toString() ?? fallback )
                             : ( e.message ?? fallback );
    return HeartbeatPokeException( msg, statusCode: sc );
  }
}
