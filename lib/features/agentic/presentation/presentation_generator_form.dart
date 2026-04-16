import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../queue/data/queue_models.dart';
import '../../queue/presentation/job_detail_screen.dart';
import '../data/agentic_common_models.dart';
import '../data/presentation_models.dart';
import '../domain/agentic_submission_bloc.dart';
import '../domain/agentic_submission_event.dart';
import '../domain/agentic_submission_state.dart';

class PresentationGeneratorForm extends StatefulWidget {
  const PresentationGeneratorForm( { super.key } );

  @override
  State<PresentationGeneratorForm> createState() => _PresentationGeneratorFormState();
}

class _PresentationGeneratorFormState extends State<PresentationGeneratorForm> {
  final _pathCtrl     = TextEditingController();
  final _durationCtrl = TextEditingController();
  String? _theme;
  bool    _dryRun     = false;
  bool    _renderOnly = false;

  static const _themes = [ 'default', 'minimal', 'dark', 'corporate' ];

  @override
  void initState() {
    super.initState();
    context.read<AgenticSubmissionBloc>().add( const AgenticFormReset() );
  }

  @override
  void dispose() {
    _pathCtrl.dispose();
    _durationCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final path = _pathCtrl.text.trim();
    if ( path.isEmpty ) return;
    final duration = int.tryParse( _durationCtrl.text.trim() );
    context.read<AgenticSubmissionBloc>().add(
      AgenticSubmitRequested(
        type   : AgenticJobType.presentation,
        request: PresentationGeneratorRequest(
          sourcePath             : path,
          targetDurationMinutes  : duration,
          theme                  : _theme,
          renderOnly             : _renderOnly,
          dryRun                 : _dryRun,
        ),
      ),
    );
  }

  @override
  Widget build( BuildContext context ) {
    return Scaffold(
      appBar: AppBar( title: const Text( 'Presentation Generator' ) ),
      body: BlocConsumer<AgenticSubmissionBloc, AgenticSubmissionState>(
        listener: ( context, state ) {
          if ( state is AgenticSubmissionSuccess ) {
            Navigator.of( context ).pushReplacement( MaterialPageRoute(
              builder: ( _ ) => JobDetailScreen(
                job: JobSummary( jobId: state.jobId, status: 'queued', agentType: 'presentation_generator' ),
              ),
            ) );
          } else if ( state is AgenticSubmissionFailure ) {
            ScaffoldMessenger.of( context ).showSnackBar(
              SnackBar( content: Text( state.error ), backgroundColor: Colors.red ),
            );
          }
        },
        builder: ( context, state ) {
          final loading = state is AgenticSubmissionInProgress;
          return ListView( padding: const EdgeInsets.all( 16 ), children: [
            TextField(
              controller : _pathCtrl,
              decoration : const InputDecoration(
                labelText : 'Source document path *',
                hintText  : '/path/to/research.md',
                border    : OutlineInputBorder(),
              ),
            ),
            const SizedBox( height: 16 ),
            DropdownButtonFormField<String>(
              value      : _theme,
              decoration : const InputDecoration( labelText: 'Theme', border: OutlineInputBorder() ),
              items      : _themes.map( ( t ) =>
                DropdownMenuItem( value: t, child: Text( t ) ),
              ).toList(),
              onChanged  : ( v ) => setState( () => _theme = v ),
            ),
            const SizedBox( height: 16 ),
            TextField(
              controller  : _durationCtrl,
              keyboardType: TextInputType.number,
              decoration  : const InputDecoration(
                labelText : 'Target duration (minutes, optional)',
                border    : OutlineInputBorder(),
              ),
            ),
            const SizedBox( height: 8 ),
            SwitchListTile(
              title    : const Text( 'Render only (skip content generation)' ),
              value    : _renderOnly,
              onChanged: ( v ) => setState( () => _renderOnly = v ),
            ),
            SwitchListTile(
              title    : const Text( 'Dry run' ),
              value    : _dryRun,
              onChanged: ( v ) => setState( () => _dryRun = v ),
            ),
            const SizedBox( height: 24 ),
            FilledButton(
              onPressed: loading ? null : _submit,
              child: loading
                  ? const SizedBox( width: 20, height: 20, child: CircularProgressIndicator( strokeWidth: 2 ) )
                  : const Text( 'Submit' ),
            ),
          ] );
        },
      ),
    );
  }
}
