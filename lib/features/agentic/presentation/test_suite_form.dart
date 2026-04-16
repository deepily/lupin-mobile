import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../queue/data/queue_models.dart';
import '../../queue/presentation/job_detail_screen.dart';
import '../data/agentic_common_models.dart';
import '../data/test_suite_models.dart';
import '../domain/agentic_submission_bloc.dart';
import '../domain/agentic_submission_event.dart';
import '../domain/agentic_submission_state.dart';

class TestSuiteForm extends StatefulWidget {
  const TestSuiteForm( { super.key } );

  @override
  State<TestSuiteForm> createState() => _TestSuiteFormState();
}

class _TestSuiteFormState extends State<TestSuiteForm> {
  final _types = { 'integration': true, 'e2e': true, 'unit': false, 'websocket': false };
  bool _dryRun = false;
  bool _autoFix = false;

  @override
  void initState() {
    super.initState();
    context.read<AgenticSubmissionBloc>().add( const AgenticFormReset() );
  }

  String get _testTypesString =>
      _types.entries.where( ( e ) => e.value ).map( ( e ) => e.key ).join( ',' );

  void _submit() {
    final types = _testTypesString;
    if ( types.isEmpty ) return;
    context.read<AgenticSubmissionBloc>().add(
      AgenticSubmitRequested(
        type   : AgenticJobType.testSuite,
        request: TestSuiteRequest(
          testTypes       : types,
          dryRun          : _dryRun,
          autoFixOnFailure: _autoFix,
        ),
      ),
    );
  }

  @override
  Widget build( BuildContext context ) {
    return Scaffold(
      appBar: AppBar( title: const Text( 'Test Suite' ) ),
      body: BlocConsumer<AgenticSubmissionBloc, AgenticSubmissionState>(
        listener: ( context, state ) {
          if ( state is AgenticSubmissionSuccess ) {
            Navigator.of( context ).pushReplacement( MaterialPageRoute(
              builder: ( _ ) => JobDetailScreen(
                job: JobSummary( jobId: state.jobId, status: 'queued', agentType: 'test_suite' ),
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
            Text( 'Test types', style: Theme.of( context ).textTheme.titleSmall ),
            ..._types.keys.map( ( k ) => CheckboxListTile(
              title    : Text( k ),
              value    : _types[ k ],
              onChanged: ( v ) => setState( () => _types[ k ] = v ?? false ),
            ) ),
            const Divider(),
            SwitchListTile(
              title    : const Text( 'Auto-fix on failure' ),
              value    : _autoFix,
              onChanged: ( v ) => setState( () => _autoFix = v ),
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
