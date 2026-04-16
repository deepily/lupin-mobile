import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/claude_code_models.dart';
import '../domain/claude_code_bloc.dart';
import '../domain/claude_code_event.dart';
import '../domain/claude_code_state.dart';

class ChatScreen extends StatefulWidget {
  final ClaudeCodeSession initialSession;
  const ChatScreen( { super.key, required this.initialSession } );

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _inputCtrl = TextEditingController();

  String get _taskId => widget.initialSession.taskId;

  void _inject() {
    final msg = _inputCtrl.text.trim();
    if ( msg.isEmpty ) return;
    _inputCtrl.clear();
    context.read<ClaudeCodeBloc>().add( ClaudeCodeInject( taskId: _taskId, message: msg ) );
  }

  void _interrupt() {
    context.read<ClaudeCodeBloc>().add( ClaudeCodeInterrupt( _taskId ) );
  }

  void _endSession() {
    context.read<ClaudeCodeBloc>().add( ClaudeCodeEnd( _taskId ) );
  }

  void _poll() {
    context.read<ClaudeCodeBloc>().add( ClaudeCodePollStatus( _taskId ) );
  }

  @override
  void dispose() {
    _inputCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build( BuildContext context ) {
    return BlocConsumer<ClaudeCodeBloc, ClaudeCodeState>(
      listener: ( context, state ) {
        if ( state is ClaudeCodeError ) {
          ScaffoldMessenger.of( context ).showSnackBar(
            SnackBar( content: Text( state.message ), backgroundColor: Colors.red ),
          );
        }
      },
      builder: ( context, state ) {
        final session = _sessionFromState( state ) ?? widget.initialSession;
        final isDone  = state is ClaudeCodeDone;
        final isAwait = state is ClaudeCodeAwaitingInput;

        return Scaffold(
          appBar: AppBar(
            title  : Text( session.taskId ),
            actions: [
              IconButton(
                icon   : const Icon( Icons.refresh ),
                tooltip: 'Refresh',
                onPressed: _poll,
              ),
              if ( !isDone )
                IconButton(
                  icon   : const Icon( Icons.stop_circle_outlined ),
                  tooltip: 'Interrupt',
                  onPressed: _interrupt,
                ),
              if ( !isDone )
                IconButton(
                  icon   : const Icon( Icons.power_settings_new ),
                  tooltip: 'End session',
                  onPressed: _endSession,
                ),
            ],
          ),
          body: Column(
            children: [
              _StatusBanner( state: state ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all( 16 ),
                  children: [
                    if ( session.error != null )
                      Card(
                        color: Colors.red.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all( 12 ),
                          child: Text( session.error!, style: TextStyle( color: Colors.red.shade800 ) ),
                        ),
                      ),
                    if ( session.costUsd != null )
                      Padding(
                        padding: const EdgeInsets.only( top: 8 ),
                        child: Text(
                          'Cost: \$${session.costUsd!.toStringAsFixed( 4 )}',
                          style: Theme.of( context ).textTheme.bodySmall,
                          textAlign: TextAlign.end,
                        ),
                      ),
                  ],
                ),
              ),
              if ( isAwait || !isDone )
                _InputBar( ctrl: _inputCtrl, onSend: isAwait ? _inject : null, isDone: isDone ),
            ],
          ),
        );
      },
    );
  }

  ClaudeCodeSession? _sessionFromState( ClaudeCodeState state ) {
    if ( state is ClaudeCodeActive ) return state.session;
    if ( state is ClaudeCodeAwaitingInput ) return state.session;
    if ( state is ClaudeCodeDone ) return state.session;
    return null;
  }
}

class _StatusBanner extends StatelessWidget {
  final ClaudeCodeState state;
  const _StatusBanner( { required this.state } );

  @override
  Widget build( BuildContext context ) {
    String label;
    Color  color;

    if ( state is ClaudeCodeDispatching ) {
      label = 'Dispatching…';
      color = Colors.blue.shade100;
    } else if ( state is ClaudeCodeActive ) {
      label = 'Generating…';
      color = Colors.blue.shade100;
    } else if ( state is ClaudeCodeAwaitingInput ) {
      label = 'Awaiting your input';
      color = Colors.amber.shade100;
    } else if ( state is ClaudeCodeDone ) {
      final session = ( state as ClaudeCodeDone ).session;
      label = 'Session ended (${session.status})';
      color = Colors.grey.shade200;
    } else if ( state is ClaudeCodeError ) {
      label = 'Error';
      color = Colors.red.shade100;
    } else {
      return const SizedBox.shrink();
    }

    return Container(
      width     : double.infinity,
      color     : color,
      padding   : const EdgeInsets.symmetric( vertical: 6, horizontal: 16 ),
      child     : Text( label, style: const TextStyle( fontSize: 13 ) ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController ctrl;
  final VoidCallback? onSend;
  final bool isDone;

  const _InputBar( { required this.ctrl, required this.onSend, required this.isDone } );

  @override
  Widget build( BuildContext context ) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB( 12, 8, 12, 8 ),
        child: Row( children: [
          Expanded(
            child: TextField(
              controller: ctrl,
              decoration: InputDecoration(
                hintText     : isDone ? 'Session ended' : 'Type a message…',
                border       : const OutlineInputBorder(),
                isDense      : true,
                contentPadding: const EdgeInsets.symmetric( horizontal: 12, vertical: 10 ),
              ),
              enabled   : !isDone && onSend != null,
              onSubmitted: onSend != null ? ( _ ) => onSend!() : null,
            ),
          ),
          const SizedBox( width: 8 ),
          IconButton.filled(
            icon     : const Icon( Icons.send ),
            onPressed: onSend,
          ),
        ] ),
      ),
    );
  }
}
