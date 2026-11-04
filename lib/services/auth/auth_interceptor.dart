import 'package:dio/dio.dart';

import 'auth_repository.dart';
import 'auth_token_provider.dart';

/// Dio interceptor that adds the access token and refreshes it on a 401.
///
/// Reading the stored refresh token and persisting the rotated pair are callbacks, so the interceptor
/// does not import AuthBloc or SecureCredentialStore.
class AuthInterceptor extends Interceptor {
  final Dio             _dio;
  final AuthRepository  _repo;
  /// Reads the stored refresh token for the active server context.
  final Future<String?> Function() readRefreshToken;
  /// Persists the rotated token pair after a successful refresh.
  final Future<void>    Function( AuthTokens tokens ) onTokensRotated;
  /// Called when the session cannot be refreshed, so the app can sign the user out.
  final Future<void>    Function() onRefreshFailed;

  bool _refreshing = false;

  /// Creates an interceptor that sends requests through [dio] and refreshes through [repo].
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

      final rotated = await _refreshRacingBackground( refresh );
      setAccessToken( rotated.accessToken );
      await onTokensRotated( rotated );

      final retryOpts        = err.requestOptions;
      retryOpts.extra[ "_auth_retried" ] = true;
      retryOpts.headers[ "Authorization" ] = "Bearer ${rotated.accessToken}";
      // A multipart body is single-use: the first attempt finalized it, and replaying the same FormData
      // throws inside fetch, so the retry would fail and read as a refresh failure. Clone it, with files
      // re-read from their source, so the refresh stays invisible to the user.
      // Design: src/docs/decisions/README.md (R-AUTH-retry-clone)
      if ( retryOpts.data is FormData ) {
        retryOpts.data = ( retryOpts.data as FormData ).clone();
      }

      final retry = await _dio.fetch<dynamic>( retryOpts );
      handler.resolve( retry );
    } catch ( _ ) {
      await onRefreshFailed();
      handler.next( err );
    } finally {
      _refreshing = false;
    }
  }

  /// Refreshes, surviving a rotation the background wake isolate got to first.
  ///
  /// The stored refresh token has two writers: the FCM wake handler also refreshes it, in its own isolate (`fcm_bootstrap.dart`).
  /// The server revokes on every exchange, so a wake while the app is backgrounded but alive can make both sides present one token.
  /// The loser gets a 401 on a token that was valid when it read it. That is not a dead session, and treating it as one logs the user out.
  ///
  /// Requires:
  ///   - presented is the refresh token this attempt already tried
  ///
  /// Ensures:
  ///   - returns rotated tokens, retrying once only if the 401 came with a different token now in the
  ///     store, which means the other writer won
  ///
  /// Raises:
  ///   - AuthException when the session is dead: any non-401, or a 401 on a token the store still agrees with
  Future<AuthTokens> _refreshRacingBackground( String presented ) async {
    // The board polls every 60 s and wakes are rate-limited to one per 60 s, so the two
    // writers recur on similar cadences rather than colliding rarely.
    try {
      return await _repo.refresh( presented );
    } on AuthException catch ( e ) {
      if ( e.statusCode != 401 ) rethrow;
      final current = await readRefreshToken();
      if ( current == null || current == presented ) rethrow;
      return _repo.refresh( current );
    }
  }

  bool _needsAuth( String path ) {
    // Public endpoints — skip injection.
    const skip = [ "/auth/login", "/auth/refresh", "/api/get-session-id" ];
    return !skip.any( ( p ) => path.startsWith( p ) );
  }
}
