import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../queue/data/queue_models.dart';
import '../../queue/presentation/job_detail_screen.dart';
import '../data/agentic_common_models.dart';
import '../data/podcast_models.dart';
import '../domain/agentic_submission_bloc.dart';
import '../domain/agentic_submission_event.dart';
import '../domain/agentic_submission_state.dart';

class PodcastGeneratorForm extends StatefulWidget {
  const PodcastGeneratorForm( { super.key } );

  @override
  State<PodcastGeneratorForm> createState() => _PodcastGeneratorFormState();
}

class _PodcastGeneratorFormState extends State<PodcastGeneratorForm> {
  final _sourceCtrl = TextEditingController();
  bool  _dryRun     = false;

  @override
  void initState() {
    super.initState();
    context.read<AgenticSubmissionBloc>().add( const AgenticFormReset() );
  }

  @override
  void dispose() {
    _sourceCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final source = _sourceCtrl.text.trim();
    if ( source.isEmpty ) return;
    context.read<AgenticSubmissionBloc>().add(
      AgenticSubmitRequested(
        type   : AgenticJobType.podcast,
        request: PodcastGeneratorRequest(
          researchSource: source,
          dryRun        : _dryRun,
        ),
      ),
    );
  }

  @override
  Widget build( BuildContext context ) {
    return Scaffold(
      appBar: AppBar( title: const Text( 'Podcast Generator' ) ),
      body: BlocConsumer<AgenticSubmissionBloc, AgenticSubmissionState>(
        listener: ( context, state ) {
          if ( state is AgenticSubmissionSuccess ) {
            Navigator.of( context ).pushReplacement( MaterialPageRoute(
              builder: ( _ ) => JobDetailScreen(
                job: JobSummary( jobId: state.jobId, status: 'queued', agentType: 'podcast_generator' ),
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
              controller : _sourceCtrl,
              minLines   : 3,
              maxLines   : 6,
              decoration : const InputDecoration(
                labelText : 'Research source path or description *',
                hintText  : 'e.g. /path/to/report.md or a brief description',
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
