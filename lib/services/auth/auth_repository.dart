import 'package:dio/dio.dart';

/// An access and refresh token pair from the backend.
class AuthTokens {
  /// Short-lived token sent as `Authorization: Bearer`.
  final String accessToken;
  /// Token exchanged for a new pair; the server revokes it on each exchange.
  final String refreshToken;
  /// Token scheme reported by the server; `bearer` when absent.
  final String tokenType;

  /// Creates a token pair.
  const AuthTokens( {
    required this.accessToken,
    required this.refreshToken,
    this.tokenType = "bearer",
  } );

  /// Reads a pair from the backend's `tokens` object.
  factory AuthTokens.fromJson( Map<String, dynamic> json ) {
    return AuthTokens(
      accessToken  : json["access_token"]  as String,
      refreshToken : json["refresh_token"] as String,
      tokenType    : ( json["token_type"] as String? ) ?? "bearer",
    );
  }
}

/// The signed-in user as returned by `/auth/me`.
class AuthUser {
  /// User id from `id`, `user_id` or `sub`.
  final String id;
  /// User's email address.
  final String email;
  /// The full response body, for fields not modelled here.
  final Map<String, dynamic> raw;

  /// Creates a user; [raw] defaults to empty.
  const AuthUser( { required this.id, required this.email, this.raw = const {} } );

  /// Reads a user from the `/auth/me` body.
  factory AuthUser.fromJson( Map<String, dynamic> json ) {
    return AuthUser(
      id    : ( json["id"] ?? json["user_id"] ?? json["sub"] ).toString(),
      email : json["email"] as String,
      raw   : json,
    );
  }
}

/// Failure from an auth call, with the HTTP status when there was a response.
class AuthException implements Exception {
  /// The server's `detail` text, or a fallback.
  final String message;
  /// HTTP status, or null when there was no response.
  final int? statusCode;
  /// Creates an exception with [message] and an optional [statusCode].
  const AuthException( this.message, { this.statusCode } );
  @override
  String toString() => "AuthException($statusCode): $message";
}

/// Direct client for the Lupin `/auth/*` endpoints.
///
/// Owns only the network shape. Storage lives in SecureCredentialStore and the state machine in AuthBloc.
class AuthRepository {
  final Dio _dio;

  /// Creates a repository on [_dio].
  AuthRepository( this._dio );

  /// Exchanges an email and password for tokens.
  ///
  /// Throws [AuthException] on failure.
  Future<AuthTokens> login( String email, String password ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        "/auth/login",
        data: { "email": email, "password": password },
      );
      return _parseTokensEnvelope( res.data!, context: "Login" );
    } on DioException catch ( e ) {
      throw _mapError( e, "Login failed" );
    }
  }

  /// Exchanges [refreshToken] for a new token pair.
  ///
  /// If the response omits a refresh token, [refreshToken] is kept. Throws [AuthException] on failure.
  Future<AuthTokens> refresh( String refreshToken ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        "/auth/refresh",
        data: { "refresh_token": refreshToken },
      );
      return _parseTokensEnvelope(
        res.data!,
        context: "Token refresh",
        fallbackRefreshToken: refreshToken,
      );
    } on DioException catch ( e ) {
      throw _mapError( e, "Token refresh failed" );
    }
  }

  /// Extracts the `tokens` sub-map of a `{message, user?, tokens}` response.
  ///
  /// Malformed responses surface as [AuthException], never as a raw TypeError.
  AuthTokens _parseTokensEnvelope(
    Map<String, dynamic> body, {
    required String context,
    String? fallbackRefreshToken,
  } ) {
    final raw = body[ "tokens" ];
    if ( raw is! Map ) {
      throw AuthException(
        "$context response missing 'tokens' object (got: ${body.keys.toList()})",
      );
    }
    final tokensJson = Map<String, dynamic>.from( raw );
    if ( fallbackRefreshToken != null ) {
      tokensJson.putIfAbsent( "refresh_token", () => fallbackRefreshToken );
    }
    try {
      return AuthTokens.fromJson( tokensJson );
    } catch ( e ) {
      throw AuthException( "$context response has malformed tokens: $e" );
    }
  }

  /// Ends the session on the server by revoking [refreshToken].
  ///
  /// The route takes `{ "refresh_token": ... }` as its body; a call without one is answered 422. So with no
  /// [refreshToken] nothing is sent, because the server has nothing it could revoke.
  ///
  /// A 401 is ignored, because the caller clears local state either way. Throws [AuthException] for other failures.
  /// The refresh token travels only in the request body: it is never logged and never put in an error message.
  Future<void> logout( String accessToken, { String? refreshToken } ) async {
    if ( refreshToken == null ) return;
    try {
      await _dio.post<dynamic>(
        "/auth/logout",
        data    : { "refresh_token": refreshToken },
        options : Options( headers: { "Authorization": "Bearer $accessToken" } ),
      );
    } on DioException catch ( e ) {
      // Logout failures are non-fatal — caller still clears local state.
      if ( e.response?.statusCode == 401 ) return;
      throw _mapError( e, "Logout failed" );
    }
  }

  /// Fetches the user for [accessToken].
  ///
  /// Throws [AuthException] on failure.
  Future<AuthUser> me( String accessToken ) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        "/auth/me",
        options: Options( headers: { "Authorization": "Bearer $accessToken" } ),
      );
      return AuthUser.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _mapError( e, "Fetch /auth/me failed" );
    }
  }

  AuthException _mapError( DioException e, String fallback ) {
    final sc  = e.response?.statusCode;
    final msg = e.response?.data is Map<String, dynamic>
        ? ( ( e.response!.data as Map )["detail"]?.toString() ?? fallback )
        : ( e.message ?? fallback );
    return AuthException( msg, statusCode: sc );
  }
}

