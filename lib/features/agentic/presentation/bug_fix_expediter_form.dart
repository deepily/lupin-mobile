import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../queue/data/queue_models.dart';
import '../../queue/presentation/job_detail_screen.dart';
import '../data/agentic_common_models.dart';
import '../data/bug_fix_expediter_models.dart';
import '../domain/agentic_submission_bloc.dart';
import '../domain/agentic_submission_event.dart';
import '../domain/agentic_submission_state.dart';

/// Bug Fix Expediter submission form.
///
/// Primary entry point: [JobDetailScreen] when job status == 'dead' — passes
/// [deadJobId] pre-filled. Also reachable from AgenticHub for manual entry.
class BugFixExpediterForm extends StatefulWidget {
  final String? deadJobId;  // pre-filled when navigated from a dead job

  const BugFixExpediterForm( { super.key, this.deadJobId } );

  @override
  State<BugFixExpediterForm> createState() => _BugFixExpediterFormState();
}

class _BugFixExpediterFormState extends State<BugFixExpediterForm> {
  late final TextEditingController _jobIdCtrl;
  final _contextCtrl = TextEditingController();
  bool _dryRun = false;

  @override
  void initState() {
    super.initState();
    _jobIdCtrl = TextEditingController( text: widget.deadJobId ?? '' );
    context.read<AgenticSubmissionBloc>().add( const AgenticFormReset() );
  }

  @override
  void dispose() {
    _jobIdCtrl.dispose();
    _contextCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final jobId = _jobIdCtrl.text.trim();
    if ( jobId.isEmpty ) return;
    final extra = _contextCtrl.text.trim();
    context.read<AgenticSubmissionBloc>().add(
      AgenticSubmitRequested(
        type   : AgenticJobType.bugFixExpediter,
        request: BugFixExpediterRequest(
          deadJobId    : jobId,
          extraContext : extra.isEmpty ? null : extra,
          dryRun       : _dryRun,
        ),
      ),
    );
  }

  @override
  Widget build( BuildContext context ) {
    return Scaffold(
      appBar: AppBar( title: const Text( 'Bug Fix Expediter' ) ),
      body: BlocConsumer<AgenticSubmissionBloc, AgenticSubmissionState>(
        listener: ( context, state ) {
          if ( state is AgenticSubmissionSuccess ) {
            Navigator.of( context ).pushReplacement( MaterialPageRoute(
              builder: ( _ ) => JobDetailScreen(
                job: JobSummary( jobId: state.jobId, status: 'queued', agentType: 'bug_fix_expediter' ),
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
              controller : _jobIdCtrl,
              decoration : const InputDecoration(
                labelText : 'Dead job ID *',
                hintText  : 'e.g. bfe-a1b2c3d4',
                border    : OutlineInputBorder(),
              ),
            ),
            const SizedBox( height: 16 ),
            TextField(
              controller : _contextCtrl,
              minLines   : 3,
              maxLines   : 6,
              decoration : const InputDecoration(
                labelText : 'Extra context (optional)',
                hintText  : 'Describe the failure or anything helpful for the fix...',
                border    : OutlineInputBorder(),
              ),
            ),
            const SizedBox( height: 8 ),
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
