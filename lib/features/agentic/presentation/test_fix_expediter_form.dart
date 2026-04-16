import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../queue/data/queue_models.dart';
import '../../queue/presentation/job_detail_screen.dart';
import '../data/agentic_common_models.dart';
import '../data/test_fix_expediter_models.dart';
import '../domain/agentic_submission_bloc.dart';
import '../domain/agentic_submission_event.dart';
import '../domain/agentic_submission_state.dart';

class TestFixExpediterForm extends StatefulWidget {
  const TestFixExpediterForm( { super.key } );

  @override
  State<TestFixExpediterForm> createState() => _TestFixExpediterFormState();
}

class _TestFixExpediterFormState extends State<TestFixExpediterForm> {
  final _resumeCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    context.read<AgenticSubmissionBloc>().add( const AgenticFormReset() );
  }

  @override
  void dispose() {
    _resumeCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final from = _resumeCtrl.text.trim();
    if ( from.isEmpty ) return;
    context.read<AgenticSubmissionBloc>().add(
      AgenticSubmitRequested(
        type   : AgenticJobType.testFixExpediter,
        request: TfeResumeFromRequest( resumeFrom: from ),
      ),
    );
  }

  @override
  Widget build( BuildContext context ) {
    return Scaffold(
      appBar: AppBar( title: const Text( 'Test Fix Expediter' ) ),
      body: BlocConsumer<AgenticSubmissionBloc, AgenticSubmissionState>(
        listener: ( context, state ) {
          if ( state is TfeResumeSuccess ) {
            Navigator.of( context ).pushReplacement( MaterialPageRoute(
              builder: ( _ ) => JobDetailScreen(
                job: JobSummary(
                  jobId    : state.response.resumedJobId,
                  status   : 'queued',
                  agentType: 'test_fix_expediter',
                ),
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
              controller : _resumeCtrl,
              decoration : const InputDecoration(
                labelText : 'Job ID, plan path, or description *',
                hintText  : 'e.g. tfe-abc123 or /path/to/plan.md',
                border    : OutlineInputBorder(),
              ),
            ),
            const SizedBox( height: 8 ),
            Text(
              'Accepts a prior TFE job ID, a plan file path, or a plain description. '
              'The server resolves the most recent matching session.',
              style: Theme.of( context ).textTheme.bodySmall,
            ),
            const SizedBox( height: 24 ),
            FilledButton(
              onPressed: loading ? null : _submit,
              child: loading
                  ? const SizedBox( width: 20, height: 20, child: CircularProgressIndicator( strokeWidth: 2 ) )
                  : const Text( 'Resume' ),
            ),
          ] );
        },
      ),
    );
  }
}
