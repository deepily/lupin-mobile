import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/auth_bloc.dart';
import '../domain/auth_state.dart';

/// Connects and disconnects the websocket as the auth state changes.
///
/// It is a plain widget so tests and the app wiring can inject the callbacks.
/// [onAuthenticated] receives both the user id and the email.
/// Email-keyed server routes fail or mis-key when given the id.
///
/// Only a change of state type triggers a callback, so repeated authenticated
/// states, such as a token refresh, do not reconnect.
class WsLifecycleListener extends StatelessWidget {
  /// The widget shown below the listener.
  final Widget child;
  /// Called with the user id and email when the user becomes authenticated.
  final Future<void> Function( String userId, String email ) onAuthenticated;
  /// Called when the user is no longer authenticated.
  final Future<void> Function()                              onSignedOut;

  /// Creates the listener; all three arguments are required.
  const WsLifecycleListener( {
    super.key,
    required this.child,
    required this.onAuthenticated,
    required this.onSignedOut,
  } );

  @override
  Widget build( BuildContext context ) {
    return BlocListener<AuthBloc, AuthState>(
      listenWhen: ( prev, curr ) => prev.runtimeType != curr.runtimeType,
      listener : ( _, state ) async {
        if ( state is AuthAuthenticated ) {
          await onAuthenticated( state.userId, state.email );
        } else if ( state is AuthUnauthenticated || state is AuthError ) {
          await onSignedOut();
        }
      },
      child: child,
    );
  }
}
