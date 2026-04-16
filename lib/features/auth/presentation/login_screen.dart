import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../services/auth/server_context_service.dart';
import '../domain/auth_bloc.dart';
import '../domain/auth_event.dart';
import '../domain/auth_state.dart';

class LoginScreen extends StatefulWidget {
  final String? initialEmail;
  final ServerContextService serverContext;

  const LoginScreen( {
    super.key,
    this.initialEmail,
    required this.serverContext,
  } );

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final TextEditingController _email;
  final TextEditingController _password = TextEditingController();
  final GlobalKey<FormState> _form = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _email = TextEditingController( text: widget.initialEmail ?? "" );
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    if ( !_form.currentState!.validate() ) return;
    context.read<AuthBloc>().add( AuthLoginRequested(
      email    : _email.text.trim(),
      password : _password.text,
    ) );
  }

  @override
  Widget build( BuildContext context ) {
    final ctx = widget.serverContext.activeConfig;
    return Scaffold(
      appBar: AppBar(
        title: const Text( "Sign in" ),
        actions: [
          Padding(
            padding: const EdgeInsets.only( right: 12 ),
            child: Center(
              child: _ContextBadge( label: ctx.label ),
            ),
          ),
        ],
      ),
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: ( context, state ) {
          if ( state is AuthError ) {
            ScaffoldMessenger.of( context ).showSnackBar(
              SnackBar( content: Text( state.message ) ),
            );
          }
        },
        builder: ( context, state ) {
          final busy = state is AuthLoading;
          return Padding(
            padding: const EdgeInsets.all( 24 ),
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextFormField(
                    controller: _email,
                    decoration: const InputDecoration( labelText: "Email" ),
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [ AutofillHints.email ],
                    validator: ( v ) =>
                      ( v == null || !v.contains( "@" ) ) ? "Enter a valid email" : null,
                  ),
                  const SizedBox( height: 16 ),
                  TextFormField(
                    controller: _password,
                    decoration: const InputDecoration( labelText: "Password" ),
                    obscureText: true,
                    autofillHints: const [ AutofillHints.password ],
                    validator: ( v ) =>
                      ( v == null || v.isEmpty ) ? "Password required" : null,
                  ),
                  const SizedBox( height: 24 ),
                  FilledButton(
                    onPressed: busy ? null : _submit,
                    child: busy
                      ? const SizedBox(
                          height: 18, width: 18,
                          child: CircularProgressIndicator( strokeWidth: 2 ),
                        )
                      : const Text( "Sign in" ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ContextBadge extends StatelessWidget {
  final String label;
  const _ContextBadge( { required this.label } );

  @override
  Widget build( BuildContext context ) {
    final color = label == "DEV" ? Colors.green : Colors.orange;
    return Container(
      padding: const EdgeInsets.symmetric( horizontal: 10, vertical: 4 ),
      decoration: BoxDecoration(
        color: color.withOpacity( 0.15 ),
        border: Border.all( color: color, width: 1.5 ),
        borderRadius: BorderRadius.circular( 12 ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }
}
