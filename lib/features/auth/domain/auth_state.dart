import 'package:equatable/equatable.dart';

abstract class AuthState extends Equatable {
  const AuthState();

  @override
  List<Object?> get props => [];
}

class AuthInitial extends AuthState {
  const AuthInitial();
}

class AuthLoading extends AuthState {
  const AuthLoading();
}

/// Refresh token present — waiting for biometric confirmation before
/// minting a fresh access token. If biometrics are unavailable the BLoC
/// goes straight to AuthUnauthenticated with `lastEmail` populated.
class AuthBiometricRequired extends AuthState {
  final String email;
  const AuthBiometricRequired( { required this.email } );

  @override
  List<Object?> get props => [ email ];
}

class AuthAuthenticated extends AuthState {
  final String userId;
  final String email;
  final String accessToken;

  const AuthAuthenticated( {
    required this.userId,
    required this.email,
    required this.accessToken,
  } );

  @override
  List<Object?> get props => [ userId, email, accessToken ];
}

class AuthUnauthenticated extends AuthState {
  final String? lastEmail;
  const AuthUnauthenticated( { this.lastEmail } );

  @override
  List<Object?> get props => [ lastEmail ];
}

class AuthError extends AuthState {
  final String message;
  final String? lastEmail;
  const AuthError( { required this.message, this.lastEmail } );

  @override
  List<Object?> get props => [ message, lastEmail ];
}
