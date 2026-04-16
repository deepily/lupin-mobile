import 'package:dio/dio.dart';

import 'auth_repository.dart';
import 'auth_token_provider.dart';

/// Dio interceptor that injects the current access token and transparently
/// refreshes on 401. Requires callbacks for reading the stored refresh
/// token and persisting the rotated pair (so the interceptor does not
/// import AuthBloc or SecureCredentialStore directly).
class AuthInterceptor extends Interceptor {
  final Dio             _dio;
  final AuthRepository  _repo;
  final Future<String?> Function() readRefreshToken;
  final Future<void>    Function( AuthTokens tokens ) onTokensRotated;
  final Future<void>    Function() onRefreshFailed;

  bool _refreshing = false;

  AuthInterceptor( {
    required Dio dio,
    required AuthRepository repo,
    required this.readRefreshToken,
    required this.onTokensRotated,
    required this.onRefreshFailed,
  } ) : _dio = dio, _repo = repo;

  @override
  void onRequest( RequestOptions options, RequestInterceptorHandler handler ) {
    if ( !options.headers.containsKey( "Authorization" ) ) {
      final token = readAccessToken();
      if ( token != null && _needsAuth( options.path ) ) {
        options.headers[ "Authorization" ] = "Bearer $token";
      }
    }
    handler.next( options );
  }

  @override
  Future<void> onError( DioException err, ErrorInterceptorHandler handler ) async {
    final response = err.response;
    final path     = err.requestOptions.path;
    final isAuth   = response?.statusCode == 401;
    final alreadyRetried =
        err.requestOptions.extra[ "_auth_retried" ] == true;
    final isAuthEndpoint = path.startsWith( "/auth/login" ) ||
                           path.startsWith( "/auth/refresh" );

    if ( !isAuth || alreadyRetried || isAuthEndpoint || _refreshing ) {
      handler.next( err );
      return;
    }

    _refreshing = true;
    try {
      final refresh = await readRefreshToken();
      if ( refresh == null ) {
        await onRefreshFailed();
        handler.next( err );
        return;
      }

      final rotated = await _repo.refresh( refresh );
      setAccessToken( rotated.accessToken );
      await onTokensRotated( rotated );

      final retryOpts        = err.requestOptions;
      retryOpts.extra[ "_auth_retried" ] = true;
      retryOpts.headers[ "Authorization" ] = "Bearer ${rotated.accessToken}";

      final retry = await _dio.fetch<dynamic>( retryOpts );
      handler.resolve( retry );
    } catch ( _ ) {
      await onRefreshFailed();
      handler.next( err );
    } finally {
      _refreshing = false;
    }
  }

  bool _needsAuth( String path ) {
    // Public endpoints — skip injection.
    const skip = [ "/auth/login", "/auth/refresh", "/api/get-session-id" ];
    return !skip.any( ( p ) => path.startsWith( p ) );
  }
}
