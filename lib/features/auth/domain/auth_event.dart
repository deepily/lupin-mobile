import 'package:equatable/equatable.dart';

/// Base class for events handled by the auth bloc.
abstract class AuthEvent extends Equatable {
  /// Creates an event.
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

/// Fired at app launch to pick the first screen.
///
/// The bloc tries biometric unlock, shows the login screen, or reports an error.
class AuthStarted extends AuthEvent {
  /// Creates the event.
  const AuthStarted();
}

/// The user submitted the login form.
class AuthLoginRequested extends AuthEvent {
  /// The email address entered.
  final String email;
  /// The password entered.
  final String password;

  /// Creates the event; both fields are required.
  const AuthLoginRequested( {
    required this.email,
    required this.password,
  } );

  @override
  List<Object?> get props => [ email, password ];
}

/// The user asked to log out.
class AuthLogoutRequested extends AuthEvent {
  /// Creates the event.
  const AuthLogoutRequested();
}

/// The user asked to unlock with biometrics.
class AuthBiometricUnlockRequested extends AuthEvent {
  /// Creates the event.
  const AuthBiometricUnlockRequested();
}

/// Asks the bloc to re-check the held access token against `/auth/me`.
class AuthSessionValidationRequested extends AuthEvent {
  /// Creates the event.
  const AuthSessionValidationRequested();
}

/// The user picked another server on the server switch.
///
/// The bloc logs out of the current server and clears its stored session.
/// Only then does it switch to [contextId], so the clear cannot hit the new
/// server's session.
class AuthServerContextSwitchRequested extends AuthEvent {
  /// The id of the server to switch to.
  final String contextId;
  /// Creates the event for [contextId].
  const AuthServerContextSwitchRequested( this.contextId );

  @override
  List<Object?> get props => [ contextId ];
}
