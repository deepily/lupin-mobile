/// FcmWakeupService — S5 §3.2 token lifecycle against the S6 contract
/// (§3.1, OSQ-6 RATIFIED-AS-AMENDED, POST-unregister amendment 2026-06-12):
///
///   - `POST /api/fcm/register-token`   `{token, platform:"android", user_email}` → `{"status":"ok"}`
///   - `POST /api/fcm/unregister-token` `{token}`                                 → `{"status":"ok"}`
///
/// Registration is an IDEMPOTENT UPSERT keyed on token (parent-side
/// durable store, AC-S6.1) — so the THREE writers are all safe to fire
/// liberally: (1) auth-state AUTHENTICATED transition (the same signal
/// AuthGate renders on — seam per Arnold residual #1), (2) `onTokenRefresh`
/// (Google rotated the token), (3) EVERY WS reconnect (F-S6-S2-1(b) — the
/// one cheap call that covers parent-restart registry loss, which
/// `onTokenRefresh` can never see: the token didn't change and Google
/// doesn't know Lupin restarted).
///
/// The [dio] is the app's SHARED auth-wired instance — the JWT bearer
/// rides for free (this service runs in the MAIN isolate only; the
/// background handler has its own bootstrap, see `fcm_wake_chain.dart`).
library;

import 'dart:async';

import 'package:dio/dio.dart';

/// Seam over FirebaseMessaging so token-lifecycle unit tests need no
/// platform channels (AC-S5.1/S5.2). The real adapter lives in
/// `fcm_bootstrap.dart` behind the ENABLE_FCM flag.
abstract class FcmTokenSource {
  Future<String?> getToken();
  Stream<String> get onTokenRefresh;
}

class FcmWakeupService {
  static const String registerPath   = '/api/fcm/register-token';
  static const String unregisterPath = '/api/fcm/unregister-token';

  final FcmTokenSource _tokens;
  final Dio            _dio;
  final void Function( String line ) _log;

  String? _currentToken;
  String? _userEmail;
  StreamSubscription<String>? _refreshSub;

  FcmWakeupService( {
    required FcmTokenSource tokenSource,
    required Dio dio,
    void Function( String line )? log,
  } ) : _tokens = tokenSource,
        _dio    = dio,
        _log    = log ?? print;

  /// Login hook (auth-state AUTHENTICATED transition): obtain the FCM
  /// token, register it, and start listening for rotations.
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

  /// WS-reconnect hook (F-S6-S2-1(b)): re-register the CURRENT token —
  /// idempotent upsert; covers parent-restart registry loss.
  Future<void> onWsReconnected() async {
    final token = _currentToken;
    final email = _userEmail;
    if ( token == null || email == null ) return;
    await _register( token, email );
  }

  /// Logout hook: best-effort unregister (POST shape per the OSQ-6
  /// amendment — the DELETE-with-body proxy fragility is discharged).
  Future<void> onLoggedOut() async {
    final token = _currentToken;
    _userEmail = null;
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

  Future<void> dispose() async {
    await _refreshSub?.cancel();
    _refreshSub = null;
  }
}
