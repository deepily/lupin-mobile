import 'package:equatable/equatable.dart';

abstract class AuthEvent extends Equatable {
  const AuthEvent();

  @override
  List<Object?> get props => [];
}

/// Fired at app launch: decides whether to attempt biometric unlock,
/// show the login screen, or surface an error.
class AuthStarted extends AuthEvent {
  const AuthStarted();
}

class AuthLoginRequested extends AuthEvent {
  final String email;
  final String password;

  const AuthLoginRequested( {
    required this.email,
    required this.password,
  } );

  @override
  List<Object?> get props => [ email, password ];
}

class AuthLogoutRequested extends AuthEvent {
  const AuthLogoutRequested();
}

class AuthBiometricUnlockRequested extends AuthEvent {
  const AuthBiometricUnlockRequested();
}

/// Re-check the currently-held access token against `/auth/me`.
class AuthSessionValidationRequested extends AuthEvent {
  const AuthSessionValidationRequested();
}

/// The user picked another server on the server switch. AuthBloc logs out
/// of the CURRENT server and clears its stored session first, and only then
/// switches to [contextId], all in one handler, so the clear can't land on
/// the new server's session.
class AuthServerContextSwitchRequested extends AuthEvent {
  final String contextId;
  const AuthServerContextSwitchRequested( this.contextId );

  @override
  List<Object?> get props => [ contextId ];
}

/// Emitted when the user switches server context (Dev ↔ Test).
/// Forces logout and clears the cached session.
class AuthServerContextChanged extends AuthEvent {
  const AuthServerContextChanged();
}
