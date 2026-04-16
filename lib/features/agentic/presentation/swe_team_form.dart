import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../queue/data/queue_models.dart';
import '../../queue/presentation/job_detail_screen.dart';
import '../data/agentic_common_models.dart';
import '../data/swe_team_models.dart';
import '../domain/agentic_submission_bloc.dart';
import '../domain/agentic_submission_event.dart';
import '../domain/agentic_submission_state.dart';

class SweTeamForm extends StatefulWidget {
  const SweTeamForm( { super.key } );

  @override
  State<SweTeamForm> createState() => _SweTeamFormState();
}

class _SweTeamFormState extends State<SweTeamForm> {
  final _taskCtrl   = TextEditingController();
  final _budgetCtrl = TextEditingController();
  String? _trustMode;

  static const _trustModes = [ 'disabled', 'shadow', 'suggest', 'active' ];

  @override
  void initState() {
    super.initState();
    context.read<AgenticSubmissionBloc>().add( const AgenticFormReset() );
  }

  @override
  void dispose() {
    _taskCtrl.dispose();
    _budgetCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final task = _taskCtrl.text.trim();
    if ( task.isEmpty ) return;
    final budget = double.tryParse( _budgetCtrl.text.trim() );
    context.read<AgenticSubmissionBloc>().add(
      AgenticSubmitRequested(
        type   : AgenticJobType.sweTeam,
        request: SweTeamRequest(
          task      : task,
          budget    : budget,
          trustMode : _trustMode,
        ),
      ),
    );
  }

  @override
  Widget build( BuildContext context ) {
    return Scaffold(
      appBar: AppBar( title: const Text( 'SWE Team' ) ),
      body: BlocConsumer<AgenticSubmissionBloc, AgenticSubmissionState>(
        listener: ( context, state ) {
          if ( state is AgenticSubmissionSuccess ) {
            Navigator.of( context ).pushReplacement( MaterialPageRoute(
              builder: ( _ ) => JobDetailScreen(
                job: JobSummary( jobId: state.jobId, status: 'queued', agentType: 'swe_team' ),
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
              controller : _taskCtrl,
              minLines   : 4,
              maxLines   : 10,
              decoration : const InputDecoration(
                labelText : 'Engineering task *',
                hintText  : 'Describe the task for the SWE team...',
                border    : OutlineInputBorder(),
              ),
            ),
            const SizedBox( height: 16 ),
            DropdownButtonFormField<String>(
              value      : _trustMode,
              decoration : const InputDecoration( labelText: 'Trust mode', border: OutlineInputBorder() ),
              items      : _trustModes.map( ( m ) =>
                DropdownMenuItem( value: m, child: Text( m ) ),
              ).toList(),
              onChanged  : ( v ) => setState( () => _trustMode = v ),
            ),
            const SizedBox( height: 16 ),
            TextField(
              controller  : _budgetCtrl,
              keyboardType: TextInputType.numberWithOptions( decimal: true ),
              decoration  : const InputDecoration(
                labelText : 'Budget (USD, optional)',
                border    : OutlineInputBorder(),
              ),
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
