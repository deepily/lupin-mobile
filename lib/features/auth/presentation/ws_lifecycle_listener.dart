import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/auth_bloc.dart';
import '../domain/auth_state.dart';

/// Drives a transport-layer lifecycle (e.g. WebSocket connect / disconnect)
/// from `AuthBloc` state transitions. Kept as a pure widget so callbacks can
/// be injected by tests and the production wiring in `app.dart`.
///
/// `onAuthenticated` receives BOTH identities because they are not
/// interchangeable: `userId` is the account UUID from `/me`, while every
/// email-keyed server route (senders-visible, FCM register-token) 404s or
/// mis-keys on it. Passing only the UUID is how the reconnect cold start
/// came to ask for a UUID's senders.
///
/// `listenWhen` filters on runtime-type change so successive
/// `AuthAuthenticated` emissions (e.g. token refresh) do not trigger a
/// redundant connect.
class WsLifecycleListener extends StatelessWidget {
  final Widget child;
  final Future<void> Function( String userId, String email ) onAuthenticated;
  final Future<void> Function()                              onSignedOut;

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
