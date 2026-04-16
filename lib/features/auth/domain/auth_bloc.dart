import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../services/auth/auth_repository.dart';
import '../../../services/auth/auth_token_provider.dart';
import '../../../services/auth/biometric_gate.dart';
import '../../../services/auth/secure_credential_store.dart';
import '../../../services/auth/server_context_service.dart';
import 'auth_event.dart';
import 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final AuthRepository         _repo;
  final SecureCredentialStore  _store;
  final ServerContextService   _context;
  final BiometricGate          _biometric;

  AuthBloc( {
    required AuthRepository         repo,
    required SecureCredentialStore  store,
    required ServerContextService   context,
    required BiometricGate          biometric,
  } )  : _repo      = repo,
         _store     = store,
         _context   = context,
         _biometric = biometric,
         super( const AuthInitial() ) {
    on<AuthStarted>( _onStarted );
    on<AuthLoginRequested>( _onLogin );
    on<AuthLogoutRequested>( _onLogout );
    on<AuthBiometricUnlockRequested>( _onBiometric );
    on<AuthSessionValidationRequested>( _onValidate );
    on<AuthServerContextChanged>( _onContextChanged );
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

  Future<void> _onLogout( AuthLogoutRequested _, Emitter<AuthState> emit ) async {
    final email = await _store.readLastEmail( _ctxId );
    final token = readAccessToken();
    try {
      if ( token != null ) await _repo.logout( token );
    } catch ( _ ) {
      // Swallow — local state must still clear.
    }
    clearAccessToken();
    await _store.clearContextSession( _ctxId );
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

  Future<void> _onContextChanged(
    AuthServerContextChanged _,
    Emitter<AuthState> emit,
  ) async {
    clearAccessToken();
    final email = await _store.readLastEmail( _ctxId );
    emit( AuthUnauthenticated( lastEmail: email ) );
  }
}
