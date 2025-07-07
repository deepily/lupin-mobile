import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_event.dart';
import 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  static const String _tokenKey = 'auth_token';
  static const String _userIdKey = 'user_id';
  static const String _emailKey = 'user_email';

  AuthBloc() : super(AuthInitial()) {
    on<AuthStarted>(_onAuthStarted);
    on<AuthLoginRequested>(_onAuthLoginRequested);
    on<AuthLogoutRequested>(_onAuthLogoutRequested);
    on<AuthSessionValidationRequested>(_onAuthSessionValidationRequested);
  }

  Future<void> _onAuthStarted(
    AuthStarted event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());

    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_tokenKey);
      final userId = prefs.getString(_userIdKey);
      final email = prefs.getString(_emailKey);

      if (token != null && userId != null && email != null) {
        // TODO: Validate token with backend
        emit(AuthAuthenticated(
          userId: userId,
          email: email,
          token: token,
        ));
      } else {
        emit(AuthUnauthenticated());
      }
    } catch (e) {
      emit(AuthError(message: 'Failed to check authentication status: ${e.toString()}'));
    }
  }

  Future<void> _onAuthLoginRequested(
    AuthLoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());

    try {
      // TODO: Implement actual authentication with backend
      // For now, simulate successful login
      await Future.delayed(const Duration(seconds: 1));

      final userId = 'user_${event.email.hashCode}';
      final token = 'token_${DateTime.now().millisecondsSinceEpoch}';

      // Store credentials
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_tokenKey, token);
      await prefs.setString(_userIdKey, userId);
      await prefs.setString(_emailKey, event.email);

      emit(AuthAuthenticated(
        userId: userId,
        email: event.email,
        token: token,
      ));
    } catch (e) {
      emit(AuthError(message: 'Login failed: ${e.toString()}'));
    }
  }

  Future<void> _onAuthLogoutRequested(
    AuthLogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());

    try {
      // Clear stored credentials
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_tokenKey);
      await prefs.remove(_userIdKey);
      await prefs.remove(_emailKey);

      emit(AuthUnauthenticated());
    } catch (e) {
      emit(AuthError(message: 'Logout failed: ${e.toString()}'));
    }
  }

  Future<void> _onAuthSessionValidationRequested(
    AuthSessionValidationRequested event,
    Emitter<AuthState> emit,
  ) async {
    try {
      // TODO: Validate token with backend API
      // For now, assume token is valid if it exists
      
      final prefs = await SharedPreferences.getInstance();
      final userId = prefs.getString(_userIdKey);
      final email = prefs.getString(_emailKey);

      if (userId != null && email != null) {
        emit(AuthAuthenticated(
          userId: userId,
          email: email,
          token: event.token,
        ));
      } else {
        emit(AuthUnauthenticated());
      }
    } catch (e) {
      emit(AuthError(message: 'Session validation failed: ${e.toString()}'));
    }
  }
}