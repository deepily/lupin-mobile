import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/claude_code_models.dart';
import '../domain/claude_code_bloc.dart';
import '../domain/claude_code_state.dart';
import 'chat_screen.dart';
import 'dispatch_sheet.dart';

class SessionListScreen extends StatelessWidget {
  const SessionListScreen( { super.key } );

  void _openDispatch( BuildContext context ) {
    showModalBottomSheet<void>(
      context            : context,
      isScrollControlled : true,
      builder            : ( _ ) => BlocProvider.value(
        value: context.read<ClaudeCodeBloc>(),
        child: const DispatchSheet(),
      ),
    );
  }

  void _openChat( BuildContext context, ClaudeCodeSession session ) {
    Navigator.of( context ).push( MaterialPageRoute(
      builder: ( _ ) => BlocProvider.value(
        value: context.read<ClaudeCodeBloc>(),
        child: ChatScreen( initialSession: session ),
      ),
    ) );
  }

  @override
  Widget build( BuildContext context ) {
    return Scaffold(
      appBar: AppBar( title: const Text( 'Claude Code' ) ),
      floatingActionButton: FloatingActionButton(
        onPressed : () => _openDispatch( context ),
        tooltip   : 'New session',
        child     : const Icon( Icons.add ),
      ),
      body: BlocConsumer<ClaudeCodeBloc, ClaudeCodeState>(
        listener: ( context, state ) {
          if ( state is ClaudeCodeError ) {
            ScaffoldMessenger.of( context ).showSnackBar(
              SnackBar( content: Text( state.message ), backgroundColor: Colors.red ),
            );
          }
          // Navigate to chat when a new interactive session becomes active.
          if ( state is ClaudeCodeActive || state is ClaudeCodeAwaitingInput ) {
            final session = state is ClaudeCodeActive
                ? ( state as ClaudeCodeActive ).session
                : ( state as ClaudeCodeAwaitingInput ).session;
            _openChat( context, session );
          }
          if ( state is ClaudeCodeQueued ) {
            ScaffoldMessenger.of( context ).showSnackBar(
              SnackBar( content: Text( 'Job queued: ${state.response.jobId ?? ""}' ) ),
            );
          }
        },
        builder: ( context, state ) {
          if ( state is ClaudeCodeInitial ) {
            return const Center( child: Text( 'No active sessions.\nTap + to dispatch a new session.', textAlign: TextAlign.center ) );
          }
          if ( state is ClaudeCodeDispatching ) {
            return const Center( child: CircularProgressIndicator() );
          }
          if ( state is ClaudeCodeDone ) {
            return _SessionTile(
              session  : state.session,
              onTap    : () => _openChat( context, state.session ),
            );
          }
          return const Center( child: Text( 'No active sessions.\nTap + to dispatch a new session.', textAlign: TextAlign.center ) );
        },
      ),
    );
  }
}

class _SessionTile extends StatelessWidget {
  final ClaudeCodeSession session;
  final VoidCallback onTap;
  const _SessionTile( { required this.session, required this.onTap } );

  @override
  Widget build( BuildContext context ) {
    return ListTile(
      title   : Text( session.taskId ),
      subtitle: Text( session.status ),
      trailing: Chip(
        label: Text( session.status, style: const TextStyle( fontSize: 11 ) ),
      ),
      onTap: onTap,
    );
  }
}
