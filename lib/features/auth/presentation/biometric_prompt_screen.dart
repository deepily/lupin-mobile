import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../domain/auth_bloc.dart';
import '../domain/auth_event.dart';

/// Asks the user to unlock the stored account with biometrics.
class BiometricPromptScreen extends StatefulWidget {
  /// The email of the stored account.
  final String email;
  /// Creates the screen for [email].
  const BiometricPromptScreen( { super.key, required this.email } );

  @override
  State<BiometricPromptScreen> createState() => _BiometricPromptScreenState();
}

class _BiometricPromptScreenState extends State<BiometricPromptScreen> {
  @override
  void initState() {
    super.initState();
    // Fire the biometric prompt immediately after first frame.
    WidgetsBinding.instance.addPostFrameCallback( ( _ ) {
      context.read<AuthBloc>().add( const AuthBiometricUnlockRequested() );
    } );
  }

  @override
  Widget build( BuildContext context ) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon( Icons.fingerprint, size: 80 ),
            const SizedBox( height: 16 ),
            Text( "Unlock for ${widget.email}" ),
            const SizedBox( height: 32 ),
            TextButton(
              onPressed: () =>
                context.read<AuthBloc>().add( const AuthLogoutRequested() ),
              child: const Text( "Use password instead" ),
            ),
          ],
        ),
      ),
    );
  }
}
