import 'package:equatable/equatable.dart';

/// Base class for the states of the auth bloc.
abstract class AuthState extends Equatable {
  /// Creates a state.
  const AuthState();

  @override
  List<Object?> get props => [];
}

/// Nothing has happened yet.
class AuthInitial extends AuthState {
  /// Creates the initial state.
  const AuthInitial();
}

/// An auth step is in progress.
class AuthLoading extends AuthState {
  /// Creates the loading state.
  const AuthLoading();
}

/// A refresh token is stored and biometric confirmation is awaited.
///
/// Confirmation comes before a fresh access token is minted. Without
/// biometrics the bloc goes straight to [AuthUnauthenticated] with `lastEmail` set.
class AuthBiometricRequired extends AuthState {
  /// The email of the stored account.
  final String email;
  /// Creates the state for [email].
  const AuthBiometricRequired( { required this.email } );

  @override
  List<Object?> get props => [ email ];
}

/// The user is signed in.
class AuthAuthenticated extends AuthState {
  /// The account id.
  final String userId;
  /// The account email.
  final String email;
  /// The current access token.
  final String accessToken;

  /// Creates the state; all three fields are required.
  const AuthAuthenticated( {
    required this.userId,
    required this.email,
    required this.accessToken,
  } );

  @override
  List<Object?> get props => [ userId, email, accessToken ];
}

/// The user is signed out and should see the login screen.
class AuthUnauthenticated extends AuthState {
  /// The last email used on this server, to prefill the form; may be null.
  final String? lastEmail;
  /// Creates the state.
  const AuthUnauthenticated( { this.lastEmail } );

  @override
  List<Object?> get props => [ lastEmail ];
}

/// An auth step failed.
class AuthError extends AuthState {
  /// The error text to show.
  final String message;
  /// The last email used on this server, to prefill the form; may be null.
  final String? lastEmail;
  /// Creates the state.
  const AuthError( { required this.message, this.lastEmail } );

  @override
  List<Object?> get props => [ message, lastEmail ];
}
