import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/claude_code_models.dart';
import '../domain/claude_code_bloc.dart';
import '../domain/claude_code_event.dart';
import '../domain/claude_code_state.dart';

class DispatchSheet extends StatefulWidget {
  const DispatchSheet( { super.key } );

  @override
  State<DispatchSheet> createState() => _DispatchSheetState();
}

class _DispatchSheetState extends State<DispatchSheet> {
  final _promptCtrl  = TextEditingController();
  final _projectCtrl = TextEditingController();
  ClaudeCodeTaskType _taskType  = ClaudeCodeTaskType.interactive;
  bool               _loading   = false;

  @override
  void dispose() {
    _promptCtrl.dispose();
    _projectCtrl.dispose();
    super.dispose();
  }

  void _dispatch() {
    final prompt = _promptCtrl.text.trim();
    if ( prompt.isEmpty ) return;

    final request = ClaudeCodeDispatchRequest(
      prompt   : prompt,
      project  : _projectCtrl.text.trim().isEmpty ? null : _projectCtrl.text.trim(),
      taskType : _taskType,
    );

    if ( _taskType == ClaudeCodeTaskType.interactive ) {
      context.read<ClaudeCodeBloc>().add( ClaudeCodeDispatch( request ) );
    } else {
      context.read<ClaudeCodeBloc>().add(
        ClaudeCodeQueueSubmit(
          ClaudeCodeQueueRequest( prompt: prompt, project: _projectCtrl.text.trim().isEmpty ? null : _projectCtrl.text.trim() ),
        ),
      );
    }
  }

  @override
  Widget build( BuildContext context ) {
    final bottom = MediaQuery.of( context ).viewInsets.bottom;
    return BlocListener<ClaudeCodeBloc, ClaudeCodeState>(
      listener: ( context, state ) {
        if ( state is ClaudeCodeActive || state is ClaudeCodeAwaitingInput || state is ClaudeCodeQueued ) {
          Navigator.of( context ).pop();
        }
        if ( state is ClaudeCodeDispatching ) {
          setState( () => _loading = true );
        }
        if ( state is ClaudeCodeError ) {
          setState( () => _loading = false );
        }
      },
      child: Padding(
        padding: EdgeInsets.fromLTRB( 16, 20, 16, bottom + 20 ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text( 'New Claude Code Session', style: Theme.of( context ).textTheme.titleLarge ),
            const SizedBox( height: 16 ),
            TextField(
              controller : _promptCtrl,
              decoration : const InputDecoration(
                labelText: 'Prompt',
                border   : OutlineInputBorder(),
              ),
              minLines  : 3,
              maxLines  : 6,
              autofocus : true,
            ),
            const SizedBox( height: 12 ),
            TextField(
              controller : _projectCtrl,
              decoration : const InputDecoration(
                labelText: 'Project path (optional)',
                border   : OutlineInputBorder(),
              ),
            ),
            const SizedBox( height: 12 ),
            SegmentedButton<ClaudeCodeTaskType>(
              segments: const [
                ButtonSegment( value: ClaudeCodeTaskType.interactive, label: Text( 'Interactive' ) ),
                ButtonSegment( value: ClaudeCodeTaskType.bounded,     label: Text( 'Bounded' ) ),
              ],
              selected : { _taskType },
              onSelectionChanged: _loading
                  ? null
                  : ( s ) => setState( () => _taskType = s.first ),
            ),
            const SizedBox( height: 16 ),
            FilledButton(
              onPressed: _loading ? null : _dispatch,
              child    : _loading
                  ? const SizedBox( width: 20, height: 20, child: CircularProgressIndicator( strokeWidth: 2 ) )
                  : const Text( 'Dispatch' ),
            ),
          ],
        ),
      ),
    );
  }
}
