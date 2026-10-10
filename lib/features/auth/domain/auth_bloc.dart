import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../services/auth/auth_repository.dart';
import '../../../services/auth/auth_token_provider.dart';
import '../../../services/auth/biometric_gate.dart';
import '../../../services/auth/secure_credential_store.dart';
import '../../../services/auth/server_context_service.dart';
import 'auth_event.dart';
import 'auth_state.dart';

/// Runs login, logout, biometric unlock, session checks and server switching.
class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository         _repo;
  final SecureCredentialStore  _store;
  final ServerContextService   _context;
  final BiometricGate          _biometric;
  final Future<void> Function()? _onBeforeSignOut;

  /// Creates the bloc over its four services, starting in [AuthInitial].
  ///
  /// [onBeforeSignOut] runs on every sign-out and server switch while the access token is still set; it is how
  /// the push token is unregistered with a bearer. Its failure never stops the sign-out.
  AuthBloc( {
    required AuthRepository         repo,
    required SecureCredentialStore  store,
    required ServerContextService   context,
    required BiometricGate          biometric,
    Future<void> Function()?        onBeforeSignOut,
  } )  : _repo            = repo,
         _store           = store,
         _context         = context,
         _biometric       = biometric,
         _onBeforeSignOut = onBeforeSignOut,
         super( const AuthInitial() ) {
    on<AuthStarted>( _onStarted );
    on<AuthLoginRequested>( _onLogin );
    on<AuthLogoutRequested>( _onLogout );
    on<AuthBiometricUnlockRequested>( _onBiometric );
    on<AuthSessionValidationRequested>( _onValidate );
    on<AuthServerContextSwitchRequested>( _onContextSwitchRequested );
  }

  String get _ctxId => _context.activeConfig.id;

  Future<void> _onStarted( AuthStarted _, Emitter<AuthState> emit ) async {
    emit( const AuthLoading() );
    try {
      final refresh = await _store.readRefreshToken( _ctxId );
      final email   = await _store.readLastEmail( _ctxId );

      if ( refresh == null || email == null ) {
        emit( AuthUnauthenticated( lastEmail: email ) );
        return;
      }

      final biometricOk = await _biometric.isAvailable();
      if ( biometricOk ) {
        emit( AuthBiometricRequired( email: email ) );
      } else {
        // No hardware enrollment — require password re-entry.
        emit( AuthUnauthenticated( lastEmail: email ) );
      }
    } catch ( e ) {
      emit( AuthError( message: "Auth startup failed: $e" ) );
    }
  }

  Future<void> _onBiometric(
    AuthBiometricUnlockRequested _,
    Emitter<AuthState> emit,
  ) async {
    emit( const AuthLoading() );
    final email = await _store.readLastEmail( _ctxId );
    final refresh = await _store.readRefreshToken( _ctxId );

    if ( email == null || refresh == null ) {
      emit( AuthUnauthenticated( lastEmail: email ) );
      return;
    }

    final outcome = await _biometric.authenticate();
    if ( outcome != BiometricOutcome.authenticated ) {
      emit( AuthUnauthenticated( lastEmail: email ) );
      return;
    }

    try {
      final tokens = await _repo.refresh( refresh );
      setAccessToken( tokens.accessToken );
      await _store.writeRefreshToken( _ctxId, tokens.refreshToken );

      final user = await _repo.me( tokens.accessToken );
      emit( AuthAuthenticated(
        userId      : user.id,
        email       : user.email,
        accessToken : tokens.accessToken,
      ) );
    } on AuthException catch ( e ) {
      // Stored refresh token is invalid — force password re-login.
      await _store.deleteRefreshToken( _ctxId );
      clearAccessToken();
      emit( AuthUnauthenticated( lastEmail: email ) );
      if ( e.statusCode != 401 ) {
        emit( AuthError( message: e.message, lastEmail: email ) );
      }
    }
  }

  Future<void> _onLogin(
    AuthLoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit( const AuthLoading() );
    try {
      final tokens = await _repo.login( event.email, event.password );
      setAccessToken( tokens.accessToken );
      await _store.writeRefreshToken( _ctxId, tokens.refreshToken );
      await _store.writeLastEmail( _ctxId, event.email );

      final user = await _repo.me( tokens.accessToken );
      emit( AuthAuthenticated(
        userId      : user.id,
        email       : user.email,
        accessToken : tokens.accessToken,
      ) );
    } on AuthException catch ( e ) {
      emit( AuthError( message: e.message, lastEmail: event.email ) );
    } catch ( e ) {
      emit( AuthError( message: "Login failed: $e", lastEmail: event.email ) );
    }
  }

  /// Runs the server-side end of a sign-out, in the order the server needs, before local state is cleared.
  ///
  /// Ensures:
  ///   - [_onBeforeSignOut] runs first, while the access token is still set
  ///   - the server logout then receives the stored refresh token as its body
  ///   - neither step's failure propagates: the caller clears local state either way
  Future<void> _endServerSession( String ctxId ) async {
    final hook = _onBeforeSignOut;
    if ( hook != null ) {
      try {
        await hook();
      } catch ( _ ) {
        // Best effort — a failed push unregister must not keep the user signed in.
      }
    }
    final token = readAccessToken();
    try {
      // Inside the try: a keystore that cannot be read must not leave the user signed in.
      final refresh = await _store.readRefreshToken( ctxId );
      if ( token != null ) await _repo.logout( token, refreshToken: refresh );
    } catch ( _ ) {
      // Swallow — local state must still clear.
    }
  }

  /// Deletes [ctxId]'s stored session, ignoring a keystore that refuses.
  ///
  /// Ensures:
  ///   - never throws, so the caller still emits the signed-out state; a stale stored token is
  ///     harmless once the in-memory access token is cleared and the user is shown the login screen
  Future<void> _clearSessionOrIgnore( String ctxId ) async {
    try {
      await _store.clearContextSession( ctxId );
    } catch ( _ ) {
      // Best effort — the user must still be signed out.
    }
  }

  /// The email to pre-fill after sign-out, or null when the keystore cannot be read.
  Future<String?> _lastEmailOrNull( String ctxId ) async {
    try {
      return await _store.readLastEmail( ctxId );
    } catch ( _ ) {
      return null;
    }
  }

  Future<void> _onLogout( AuthLogoutRequested _, Emitter<AuthState> emit ) async {
    final email = await _lastEmailOrNull( _ctxId );
    await _endServerSession( _ctxId );
    clearAccessToken();
    await _clearSessionOrIgnore( _ctxId );
    emit( AuthUnauthenticated( lastEmail: email ) );
  }

  Future<void> _onValidate(
    AuthSessionValidationRequested _,
    Emitter<AuthState> emit,
  ) async {
    final token = readAccessToken();
    if ( token == null ) {
      final email = await _store.readLastEmail( _ctxId );
      emit( AuthUnauthenticated( lastEmail: email ) );
      return;
    }
    try {
      final user = await _repo.me( token );
      emit( AuthAuthenticated(
        userId      : user.id,
        email       : user.email,
        accessToken : token,
      ) );
    } on AuthException catch ( e ) {
      final email = await _store.readLastEmail( _ctxId );
      emit( AuthError( message: e.message, lastEmail: email ) );
    }
  }

  /// Logs out of the current server, clears its stored session, then switches.
  ///
  /// Ensures:
  ///   - the best-effort server logout goes to the old host
  ///   - the old context's refresh token and session ids are deleted
  ///   - the new context's stored session is untouched
  ///   - ends in [AuthUnauthenticated] with the new context's last email
  //
  // One handler, not a logout event plus a switch event: the bloc runs
  // handlers for different event types concurrently, and a separate logout
  // event could clear the new server's session instead of the old one's.
  Future<void> _onContextSwitchRequested(
    AuthServerContextSwitchRequested event,
    Emitter<AuthState> emit,
  ) async {
    final oldId = _ctxId;
    if ( event.contextId == oldId ) return;

    await _endServerSession( oldId );
    clearAccessToken();
    await _clearSessionOrIgnore( oldId );

    await _context.setActive( event.contextId );
    final email = await _lastEmailOrNull( event.contextId );
    emit( AuthUnauthenticated( lastEmail: email ) );
  }
}
