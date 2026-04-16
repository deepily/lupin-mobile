import 'package:dio/dio.dart';

class AuthTokens {
  final String accessToken;
  final String refreshToken;
  final String tokenType;

  const AuthTokens( {
    required this.accessToken,
    required this.refreshToken,
    this.tokenType = "bearer",
  } );

  factory AuthTokens.fromJson( Map<String, dynamic> json ) {
    return AuthTokens(
      accessToken  : json["access_token"]  as String,
      refreshToken : json["refresh_token"] as String,
      tokenType    : ( json["token_type"] as String? ) ?? "bearer",
    );
  }
}

class AuthUser {
  final String id;
  final String email;
  final Map<String, dynamic> raw;

  const AuthUser( { required this.id, required this.email, this.raw = const {} } );

  factory AuthUser.fromJson( Map<String, dynamic> json ) {
    return AuthUser(
      id    : ( json["id"] ?? json["user_id"] ?? json["sub"] ).toString(),
      email : json["email"] as String,
      raw   : json,
    );
  }
}

class AuthException implements Exception {
  final String message;
  final int? statusCode;
  const AuthException( this.message, { this.statusCode } );
  @override
  String toString() => "AuthException($statusCode): $message";
}

/// Direct client for Lupin v0.1.6 `/auth/*` endpoints.
/// Owns only the network shape; storage and state-machine concerns live
/// in SecureCredentialStore and AuthBloc respectively.
class AuthRepository {
  final Dio _dio;

  AuthRepository( this._dio );

  Future<AuthTokens> login( String email, String password ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        "/auth/login",
        data: { "email": email, "password": password },
      );
      return AuthTokens.fromJson( res.data! );
    } on DioException catch ( e ) {
      throw _mapError( e, "Login failed" );
    }
  }

  Future<AuthTokens> refresh( String refreshToken ) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        "/auth/refresh",
        data: { "refresh_token": refreshToken },
      );
      final json = Map<String, dynamic>.from( res.data! );
      // Some backends only rotate access; keep old refresh if omitted.
      json.putIfAbsent( "refresh_token", () => refreshToken );
      return AuthTokens.fromJson( json );
    } on DioException catch ( e ) {
      throw _mapError( e, "Token refresh failed" );
    }
  }

  Future<void> logout( String accessToken ) async {
    try {
      await _dio.post<dynamic>(
        "/auth/logout",
        options: Options( headers: { "Authorization": "Bearer $accessToken" } ),
      );
    } on DioException catch ( e ) {
      // Logout failures are non-fatal — caller still clears local state.
      if ( e.response?.statusCode == 401 ) return;
      throw _mapError( e, "Logout failed" );
    }
  }

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

