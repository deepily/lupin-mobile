import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../services/auth/server_context_service.dart';
import '../domain/auth_bloc.dart';
import '../domain/auth_event.dart';
import '../domain/auth_state.dart';
import 'biometric_prompt_screen.dart';
import 'login_screen.dart';

/// Build-time dev credentials baked in via --dart-define. Only consulted in
/// debug builds; release builds always see empty strings regardless of what
/// was passed at build time. The values never touch source files or git.
const String _kDevEmail    = String.fromEnvironment( 'LUPIN_DEV_EMAIL'    );
const String _kDevPassword = String.fromEnvironment( 'LUPIN_DEV_PASSWORD' );

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
        final debugEmail    = kDebugMode && _kDevEmail.isNotEmpty    ? _kDevEmail    : null;
        final debugPassword = kDebugMode && _kDevPassword.isNotEmpty ? _kDevPassword : null;
        return LoginScreen(
          initialEmail    : lastEmail ?? debugEmail,
          initialPassword : debugPassword,
          serverContext   : widget.serverContext,
        );
      },
    );
  }
}
