import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../services/auth/server_context_service.dart';
import '../domain/auth_bloc.dart';
import '../domain/auth_event.dart';
import '../domain/auth_state.dart';
import 'biometric_prompt_screen.dart';
import 'login_screen.dart';

/// Top-level widget that routes between login, biometric unlock, and the
/// authenticated app shell based on AuthBloc state.
class AuthGate extends StatefulWidget {
  final ServerContextService serverContext;
  final Widget authenticatedChild;

  const AuthGate( {
    super.key,
    required this.serverContext,
    required this.authenticatedChild,
  } );

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  @override
  void initState() {
    super.initState();
    context.read<AuthBloc>().add( const AuthStarted() );
  }

  @override
  Widget build( BuildContext context ) {
    return BlocBuilder<AuthBloc, AuthState>(
      builder: ( context, state ) {
        if ( state is AuthInitial || state is AuthLoading ) {
          return const Scaffold(
            body: Center( child: CircularProgressIndicator() ),
          );
        }
        if ( state is AuthAuthenticated ) {
          return widget.authenticatedChild;
        }
        if ( state is AuthBiometricRequired ) {
          return BiometricPromptScreen( email: state.email );
        }
        final lastEmail = state is AuthUnauthenticated
          ? state.lastEmail
          : state is AuthError ? state.lastEmail : null;
        return LoginScreen(
          initialEmail  : lastEmail,
          serverContext : widget.serverContext,
        );
      },
    );
  }
}
