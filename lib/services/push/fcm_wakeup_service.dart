/// Registers the device's FCM token with the Lupin server and keeps it registered.
///
/// The server contract is two calls:
///   - `POST /api/fcm/register-token` with `{token, platform:"android", user_email}` answers `{"status":"ok"}`.
///   - `POST /api/fcm/unregister-token` with `{token}` answers `{"status":"ok"}`.
///
/// Registration is an idempotent upsert keyed on the token, in the parent's durable store.
/// That makes the three writers safe to fire liberally:
///   1. the auth-state authenticated transition, the same signal AuthGate renders on
///   2. `onTokenRefresh`, when Google rotated the token
///   3. every WebSocket reconnect, the one cheap call that covers parent-restart registry loss
///      (`onTokenRefresh` cannot see it, because the token did not change)
///
/// [dio] is the app's shared auth-wired instance, so the JWT bearer rides along.
/// This service runs in the main isolate only. The background handler has its own bootstrap in `fcm_wake_chain.dart`.
library;

import 'dart:async';

import 'package:dio/dio.dart';

/// Seam over FirebaseMessaging, so token-lifecycle unit tests need no platform channels.
///
/// The real adapter lives in `fcm_bootstrap.dart`, behind the ENABLE_FCM flag.
abstract class FcmTokenSource {
  /// Returns the current FCM token, or null when none is available.
  Future<String?> getToken();
  /// Emits each token Google rotates in.
  Stream<String> get onTokenRefresh;
}

/// Registers and unregisters the FCM token; see the library note.
class FcmWakeupService {
  /// Server path that registers a token.
  static const String registerPath   = '/api/fcm/register-token';
  /// Server path that unregisters a token.
  static const String unregisterPath = '/api/fcm/unregister-token';

  final FcmTokenSource _tokens;
  final Dio            _dio;
  final void Function( String line ) _log;

  String? _currentToken;
  String? _userEmail;
  StreamSubscription<String>? _refreshSub;

  /// Creates the service on [tokenSource] and [dio]; [log] defaults to print.
  FcmWakeupService( {
    required FcmTokenSource tokenSource,
    required Dio dio,
    void Function( String line )? log,
  } ) : _tokens = tokenSource,
        _dio    = dio,
        _log    = log ?? print;

  /// Login hook: obtains the FCM token, registers it and starts listening for rotations.
  ///
  /// Call it on the authenticated transition.
  Future<void> onAuthenticated( String userEmail ) async {
    _userEmail = userEmail;
    final token = await _tokens.getToken();
    if ( token == null ) {
      _log( '[FcmWakeup] no FCM token available — registration skipped' );
      return;
    }
    _currentToken = token;
    await _register( token, userEmail );

    _refreshSub ??= _tokens.onTokenRefresh.listen( ( fresh ) async {
      _currentToken = fresh;
      final email = _userEmail;
      if ( email == null ) return;   // rotated while logged out — next login registers
      await _register( fresh, email );
    } );
  }

  /// WebSocket-reconnect hook: re-registers the current token.
  ///
  /// The upsert is idempotent, and the call covers parent-restart registry loss.
  Future<void> onWsReconnected() async {
    final token = _currentToken;
    final email = _userEmail;
    if ( token == null || email == null ) return;
    await _register( token, email );
  }

  /// Logout hook: best-effort unregister of the token.
  ///
  /// Call it BEFORE the access token is cleared: the route needs a JWT, and a call after the clear is a 401.
  /// A failure is logged and ignored. A second call is a no-op, because the token is forgotten on the first.
  Future<void> onLoggedOut() async {
    final token = _currentToken;
    _userEmail    = null;
    _currentToken = null;
    if ( token == null ) return;
    try {
      await _dio.post<Map<String, dynamic>>(
        unregisterPath,
        data: { 'token': token },
      );
      _log( '[FcmWakeup] token unregistered' );
    } on DioException catch ( e ) {
      _log( '[FcmWakeup] unregister failed (best-effort): ${e.message}' );
    }
  }

  Future<void> _register( String token, String userEmail ) async {
    try {
      await _dio.post<Map<String, dynamic>>(
        registerPath,
        data: {
          'token'      : token,
          'platform'   : 'android',
          'user_email' : userEmail,
        },
      );
      _log( '[FcmWakeup] token registered (upsert)' );
    } on DioException catch ( e ) {
      // Non-fatal: the next writer (refresh / WS reconnect) retries.
      _log( '[FcmWakeup] register failed: ${e.message}' );
    }
  }

  /// Cancels the token-refresh subscription.
  Future<void> dispose() async {
    await _refreshSub?.cancel();
    _refreshSub = null;
  }
}
