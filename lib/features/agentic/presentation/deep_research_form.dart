import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../queue/data/queue_models.dart';
import '../../queue/presentation/job_detail_screen.dart';
import '../data/agentic_common_models.dart';
import '../data/deep_research_models.dart';
import '../domain/agentic_submission_bloc.dart';
import '../domain/agentic_submission_event.dart';
import '../domain/agentic_submission_state.dart';

class DeepResearchForm extends StatefulWidget {
  const DeepResearchForm( { super.key } );

  @override
  State<DeepResearchForm> createState() => _DeepResearchFormState();
}

class _DeepResearchFormState extends State<DeepResearchForm> {
  final _queryCtrl    = TextEditingController();
  final _budgetCtrl   = TextEditingController();
  String? _audience;
  bool    _dryRun     = false;

  static const _audiences = [ 'beginner', 'general', 'expert', 'academic' ];

  @override
  void initState() {
    super.initState();
    context.read<AgenticSubmissionBloc>().add( const AgenticFormReset() );
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    _budgetCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final query = _queryCtrl.text.trim();
    if ( query.isEmpty ) return;
    final budget = double.tryParse( _budgetCtrl.text.trim() );
    context.read<AgenticSubmissionBloc>().add(
      AgenticSubmitRequested(
        type   : AgenticJobType.deepResearch,
        request: DeepResearchRequest(
          query    : query,
          budget   : budget,
          audience : _audience,
          dryRun   : _dryRun,
        ),
      ),
    );
  }

  @override
  Widget build( BuildContext context ) {
    return Scaffold(
      appBar: AppBar( title: const Text( 'Deep Research' ) ),
      body: BlocConsumer<AgenticSubmissionBloc, AgenticSubmissionState>(
        listener: ( context, state ) {
          if ( state is AgenticSubmissionSuccess ) {
            Navigator.of( context ).pushReplacement( MaterialPageRoute(
              builder: ( _ ) => JobDetailScreen(
                job: JobSummary(
                  jobId    : state.jobId,
                  status   : 'queued',
                  agentType: 'deep_research',
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
              controller : _queryCtrl,
              minLines   : 4,
              maxLines   : 8,
              decoration : const InputDecoration(
                labelText : 'Research query *',
                hintText  : 'What would you like researched?',
                border    : OutlineInputBorder(),
              ),
            ),
            const SizedBox( height: 16 ),
            DropdownButtonFormField<String>(
              value      : _audience,
              decoration : const InputDecoration( labelText: 'Audience', border: OutlineInputBorder() ),
              items      : _audiences.map( ( a ) =>
                DropdownMenuItem( value: a, child: Text( a ) ),
              ).toList(),
              onChanged  : ( v ) => setState( () => _audience = v ),
            ),
            const SizedBox( height: 16 ),
            TextField(
              controller : _budgetCtrl,
              keyboardType: TextInputType.numberWithOptions( decimal: true ),
              decoration : const InputDecoration(
                labelText : 'Budget (USD, optional)',
                border    : OutlineInputBorder(),
              ),
            ),
            const SizedBox( height: 8 ),
            SwitchListTile(
              title    : const Text( 'Dry run (simulate, no real work)' ),
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
