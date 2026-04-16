import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/queue_models.dart';
import '../domain/queue_bloc.dart';
import '../domain/queue_event.dart';
import '../domain/queue_state.dart';

class SubmitJobSheet extends StatefulWidget {
  const SubmitJobSheet( { super.key } );

  @override
  State<SubmitJobSheet> createState() => _SubmitJobSheetState();
}

class _SubmitJobSheetState extends State<SubmitJobSheet> {
  final _questionCtrl = TextEditingController();
  bool _agentic = false;
  bool _submitting = false;

  @override
  void dispose() {
    _questionCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final question = _questionCtrl.text.trim();
    if ( question.isEmpty ) return;

    if ( _agentic ) {
      context.read<QueueBloc>().add(
        QueueSubmitAgenticJob(
          PushAgenticRequest( routingCommand: question, websocketId: 'mobile' ),
        ),
      );
    } else {
      context.read<QueueBloc>().add(
        QueueSubmitJob(
          PushJobRequest( question: question, websocketId: 'mobile' ),
        ),
      );
    }
  }

  @override
  Widget build( BuildContext context ) {
    final bottom = MediaQuery.of( context ).viewInsets.bottom;
    return BlocListener<QueueBloc, QueueState>(
      listener: ( context, state ) {
        if ( state is QueueSubmitted ) {
          Navigator.of( context ).pop();
        }
        if ( state is QueueSubmitting ) {
          setState( () => _submitting = true );
        }
        if ( state is QueueError ) {
          setState( () => _submitting = false );
        }
      },
      child: Padding(
        padding: EdgeInsets.fromLTRB( 16, 20, 16, bottom + 20 ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text( 'Submit Job', style: Theme.of( context ).textTheme.titleLarge ),
            const SizedBox( height: 16 ),
            TextField(
              controller : _questionCtrl,
              decoration : const InputDecoration(
                labelText: 'Question / Command',
                border   : OutlineInputBorder(),
              ),
              minLines  : 3,
              maxLines  : 6,
              autofocus : true,
            ),
            const SizedBox( height: 12 ),
            SwitchListTile(
              title      : const Text( 'Agentic job' ),
              subtitle   : const Text( 'Use agentic routing (longer-running tasks)' ),
              value      : _agentic,
              onChanged  : _submitting ? null : ( v ) => setState( () => _agentic = v ),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox( height: 12 ),
            FilledButton(
              onPressed: _submitting ? null : _submit,
              child    : _submitting
                  ? const SizedBox( width: 20, height: 20, child: CircularProgressIndicator( strokeWidth: 2 ) )
                  : const Text( 'Submit' ),
            ),
          ],
        ),
      ),
    );
  }
}
