import 'package:equatable/equatable.dart';

abstract class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {}

class AuthLoading extends AuthState {}

class AuthAuthenticated extends AuthState {
  final String userId;
  final String email;
  final String token;
  final DateTime? expiresAt;

  const AuthAuthenticated({
    required this.userId,
    required this.email,
    required this.token,
    this.expiresAt,
  });

  @override
  List<Object?> get props => [userId, email, token, expiresAt];
}

class AuthUnauthenticated extends AuthState {}

class AuthError extends AuthState {
  final String message;

  const AuthError({required this.message});

  @override
  List<Object?> get props => [message];
}