import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/di/service_locator.dart';
import '../../agentic/data/agentic_repository.dart';
import '../../agentic/domain/agentic_submission_bloc.dart';
import '../../agentic/presentation/bug_fix_expediter_form.dart';
import '../../artifacts/audio_artifact_player.dart';
import '../../artifacts/markdown_report_viewer.dart';
import '../../artifacts/slide_deck_viewer.dart';
import '../data/queue_models.dart';
import '../domain/queue_bloc.dart';
import '../domain/queue_event.dart';
import '../domain/queue_state.dart';

class JobDetailScreen extends StatefulWidget {
  final JobSummary job;
  const JobDetailScreen( { super.key, required this.job } );

  @override
  State<JobDetailScreen> createState() => _JobDetailScreenState();
}

class _JobDetailScreenState extends State<JobDetailScreen> {
  @override
  void initState() {
    super.initState();
    if ( widget.job.hasInteractions ) {
      context.read<QueueBloc>().add( QueueLoadInteractions( widget.job.jobId ) );
    }
  }

  void _cancel() {
    context.read<QueueBloc>().add( QueueCancelJob( widget.job.jobId ) );
  }

  void _pause() {
    context.read<QueueBloc>().add( QueuePauseJob( widget.job.jobId ) );
  }

  void _resume() {
    context.read<QueueBloc>().add( QueueResumeJob( widget.job.jobId ) );
  }

  Future<void> _viewArtifact() async {
    final job = widget.job;
    final id  = job.jobId;
    if ( id.startsWith( 'dr-' ) ) {
      try {
        final report = await ServiceLocator.instance<AgenticRepository>()
            .fetchDeepResearchReport( id );
        if ( mounted ) {
          await Navigator.of( context ).push( MaterialPageRoute(
            builder: ( _ ) => MarkdownReportViewer(
              jobId        : id,
              markdownText : report.markdownText,
            ),
          ) );
        }
      } catch ( e ) {
        if ( mounted ) {
          ScaffoldMessenger.of( context ).showSnackBar(
            SnackBar( content: Text( 'Failed to load report: $e' ), backgroundColor: Colors.red ),
          );
        }
      }
    } else if ( id.startsWith( 'pg-' ) || id.startsWith( 'rp-' ) ) {
      final path = job.reportPath ?? '';
      if ( mounted ) {
        await Navigator.of( context ).push( MaterialPageRoute(
          builder: ( _ ) => AudioArtifactPlayer( jobId: id, audioPath: path ),
        ) );
      }
    } else if ( id.startsWith( 'px-' ) || id.startsWith( 'rx-' ) ) {
      final path = job.pptxPath ?? '';
      if ( mounted ) {
        await Navigator.of( context ).push( MaterialPageRoute(
          builder: ( _ ) => SlideDeckViewer( jobId: id, deckPath: path ),
        ) );
      }
    }
  }

  void _rerunWithFix() {
    Navigator.of( context ).push( MaterialPageRoute(
      builder: ( _ ) => BlocProvider(
        create : ( _ ) => ServiceLocator.instance<AgenticSubmissionBloc>(),
        child  : BugFixExpediterForm( deadJobId: widget.job.jobId ),
      ),
    ) );
  }

  bool get _hasArtifact {
    final id = widget.job.jobId;
    return id.startsWith( 'dr-' )
        || id.startsWith( 'pg-' ) || id.startsWith( 'rp-' )
        || id.startsWith( 'px-' ) || id.startsWith( 'rx-' );
  }

  void _showMessageInput() {
    final ctrl = TextEditingController();
    showDialog<void>(
      context: context,
      builder: ( ctx ) => AlertDialog(
        title  : const Text( 'Send message to job' ),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration( hintText: 'Your message...' ),
          autofocus: true,
        ),
        actions: [
          TextButton( onPressed: () => Navigator.pop( ctx ), child: const Text( 'Cancel' ) ),
          FilledButton(
            onPressed: () {
              final msg = ctrl.text.trim();
              if ( msg.isNotEmpty ) {
                context.read<QueueBloc>().add(
                  QueueInjectMessage( jobId: widget.job.jobId, message: msg ),
                );
              }
              Navigator.pop( ctx );
            },
            child: const Text( 'Send' ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build( BuildContext context ) {
    final job    = widget.job;
    final status = job.status;
    return Scaffold(
      appBar: AppBar(
        title   : Text( job.agentType ?? 'Job Detail' ),
        actions : [
          if ( status == 'done' && _hasArtifact )
            IconButton( icon: const Icon( Icons.article_outlined ), tooltip: 'View Artifact', onPressed: _viewArtifact ),
          if ( status == 'dead' )
            IconButton( icon: const Icon( Icons.bug_report_outlined ), tooltip: 'Re-run with Fix', onPressed: _rerunWithFix ),
          if ( status == 'running' )
            IconButton( icon: const Icon( Icons.cancel_outlined ), tooltip: 'Cancel', onPressed: _cancel ),
          if ( status == 'queued' && !job.paused )
            IconButton( icon: const Icon( Icons.pause_circle_outline ), tooltip: 'Pause', onPressed: _pause ),
          if ( job.paused )
            IconButton( icon: const Icon( Icons.play_circle_outline ), tooltip: 'Resume', onPressed: _resume ),
          if ( status == 'running' )
            IconButton( icon: const Icon( Icons.message_outlined ), tooltip: 'Message', onPressed: _showMessageInput ),
        ],
      ),
      body: BlocConsumer<QueueBloc, QueueState>(
        listener: ( context, state ) {
          if ( state is QueueActionComplete ) {
            ScaffoldMessenger.of( context ).showSnackBar(
              SnackBar( content: Text( state.message ) ),
            );
          }
          if ( state is QueueError ) {
            ScaffoldMessenger.of( context ).showSnackBar(
              SnackBar( content: Text( state.message ), backgroundColor: Colors.red ),
            );
          }
        },
        builder: ( context, state ) {
          return ListView( padding: const EdgeInsets.all( 16 ), children: [
            // Header card
            Card( child: Padding( padding: const EdgeInsets.all( 16 ), child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row( children: [
                  Expanded( child: Text(
                    job.questionText ?? job.jobId,
                    style: Theme.of( context ).textTheme.titleMedium,
                  ) ),
                  Chip( label: Text( status ) ),
                ] ),
                if ( job.agentType != null ) ...[
                  const SizedBox( height: 4 ),
                  Text( 'Agent: ${job.agentType}', style: Theme.of( context ).textTheme.bodySmall ),
                ],
                if ( job.startedAt != null ) ...[
                  const SizedBox( height: 4 ),
                  Text( 'Started: ${job.startedAt}', style: Theme.of( context ).textTheme.bodySmall ),
                ],
                if ( job.completedAt != null ) ...[
                  const SizedBox( height: 4 ),
                  Text( 'Completed: ${job.completedAt}', style: Theme.of( context ).textTheme.bodySmall ),
                ],
                if ( job.durationSeconds != null ) ...[
                  const SizedBox( height: 4 ),
                  Text( 'Duration: ${job.durationSeconds!.toStringAsFixed( 1 )}s', style: Theme.of( context ).textTheme.bodySmall ),
                ],
                if ( job.error != null ) ...[
                  const SizedBox( height: 8 ),
                  Text( 'Error: ${job.error}',
                    style: TextStyle( color: Colors.red.shade700, fontSize: 12 ),
                  ),
                ],
              ],
            ) ) ),

            const SizedBox( height: 12 ),

            // Interactions / transcript
            if ( state is QueueInteractionsLoaded ) ...[
              Text( 'Interactions (${state.data.interactionCount})',
                style: Theme.of( context ).textTheme.titleSmall,
              ),
              const SizedBox( height: 8 ),
              ...state.data.interactions.map( ( i ) => _InteractionTile( interaction: i ) ),
            ] else if ( state is QueueLoading && widget.job.hasInteractions ) ...[
              const Center( child: CircularProgressIndicator() ),
            ] else if ( !widget.job.hasInteractions ) ...[
              Text( 'No interactions recorded.', style: Theme.of( context ).textTheme.bodySmall ),
            ],
          ] );
        },
      ),
    );
  }
}

class _InteractionTile extends StatelessWidget {
  final JobInteraction interaction;
  const _InteractionTile( { required this.interaction } );

  @override
  Widget build( BuildContext context ) {
    return Card(
      margin: const EdgeInsets.only( bottom: 8 ),
      child: Padding( padding: const EdgeInsets.all( 12 ), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row( children: [
            Text( interaction.type ?? 'message',
              style: TextStyle( fontSize: 11, color: Colors.grey.shade600 ),
            ),
            const Spacer(),
            Text( interaction.timestamp,
              style: TextStyle( fontSize: 11, color: Colors.grey.shade600 ),
            ),
          ] ),
          const SizedBox( height: 4 ),
          Text( interaction.message ),
          if ( interaction.responseValue != null ) ...[
            const SizedBox( height: 4 ),
            Text( 'Response: ${interaction.responseValue}',
              style: TextStyle( color: Colors.green.shade700, fontSize: 12 ),
            ),
          ],
        ],
      ) ),
    );
  }
}
