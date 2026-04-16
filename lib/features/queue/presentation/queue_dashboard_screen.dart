import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/queue_models.dart';
import '../domain/queue_bloc.dart';
import '../domain/queue_event.dart';
import '../domain/queue_state.dart';
import 'job_detail_screen.dart';
import 'submit_job_sheet.dart';

const _queueNames = [ 'todo', 'run', 'done', 'dead' ];
const _tabLabels  = [ 'Todo', 'Running', 'Done', 'Dead' ];

class QueueDashboardScreen extends StatefulWidget {
  const QueueDashboardScreen( { super.key } );

  @override
  State<QueueDashboardScreen> createState() => _QueueDashboardScreenState();
}

class _QueueDashboardScreenState extends State<QueueDashboardScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController( length: _queueNames.length, vsync: this );
    _tabs.addListener( _onTabChanged );
    _load( 0 );
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if ( !_tabs.indexIsChanging ) _load( _tabs.index );
  }

  void _load( int index ) {
    context.read<QueueBloc>().add( QueueLoadSnapshot( _queueNames[ index ] ) );
  }

  Future<void> _refresh() async {
    _load( _tabs.index );
  }

  void _openSubmitSheet() {
    showModalBottomSheet<void>(
      context    : context,
      isScrollControlled: true,
      builder    : ( _ ) => BlocProvider.value(
        value: context.read<QueueBloc>(),
        child: const SubmitJobSheet(),
      ),
    );
  }

  @override
  Widget build( BuildContext context ) {
    return Scaffold(
      appBar: AppBar(
        title: const Text( 'Queue' ),
        bottom: TabBar(
          controller : _tabs,
          tabs       : _tabLabels.map( ( l ) => Tab( text: l ) ).toList(),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed : _openSubmitSheet,
        tooltip   : 'Submit job',
        child     : const Icon( Icons.add ),
      ),
      body: BlocConsumer<QueueBloc, QueueState>(
        listener: ( context, state ) {
          if ( state is QueueSubmitted ) {
            ScaffoldMessenger.of( context ).showSnackBar(
              SnackBar( content: Text( 'Job queued: ${state.response.jobId ?? ""}' ) ),
            );
            _refresh();
          }
          if ( state is QueueActionComplete ) {
            ScaffoldMessenger.of( context ).showSnackBar(
              SnackBar( content: Text( state.message ) ),
            );
            _refresh();
          }
          if ( state is QueueError ) {
            ScaffoldMessenger.of( context ).showSnackBar(
              SnackBar( content: Text( state.message ), backgroundColor: Colors.red ),
            );
          }
        },
        builder: ( context, state ) {
          if ( state is QueueLoading || state is QueueInitial ) {
            return const Center( child: CircularProgressIndicator() );
          }
          if ( state is QueueError ) {
            return _ErrorView( message: state.message, onRetry: _refresh );
          }
          if ( state is QueueSnapshotLoaded ) {
            return TabBarView(
              controller : _tabs,
              children   : _queueNames.map( ( name ) {
                if ( name == state.snapshot.queueName ) {
                  return _JobList( jobs: state.snapshot.jobs, onRefresh: _refresh );
                }
                return const Center( child: CircularProgressIndicator() );
              } ).toList(),
            );
          }
          return TabBarView(
            controller : _tabs,
            children   : _queueNames.map( ( _ ) => const SizedBox.shrink() ).toList(),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Private widgets
// ─────────────────────────────────────────────

class _JobList extends StatelessWidget {
  final List<JobSummary> jobs;
  final Future<void> Function() onRefresh;

  const _JobList( { required this.jobs, required this.onRefresh } );

  @override
  Widget build( BuildContext context ) {
    if ( jobs.isEmpty ) {
      return RefreshIndicator(
        onRefresh: onRefresh,
        child: ListView( children: const [
          SizedBox( height: 200 ),
          Center( child: Text( 'No jobs' ) ),
        ] ),
      );
    }
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView.separated(
        itemCount      : jobs.length,
        separatorBuilder: ( _, __ ) => const Divider( height: 1 ),
        itemBuilder    : ( _, i ) => _JobTile( job: jobs[ i ] ),
      ),
    );
  }
}

class _JobTile extends StatelessWidget {
  final JobSummary job;
  const _JobTile( { required this.job } );

  Color _statusColor( String status ) {
    switch ( status ) {
      case 'running' : return Colors.blue;
      case 'completed': return Colors.green;
      case 'failed'  : return Colors.red;
      case 'paused'  : return Colors.orange;
      case 'dead'    : return Colors.red.shade900;
      default        : return Colors.grey;
    }
  }

  @override
  Widget build( BuildContext context ) {
    return ListTile(
      title    : Text(
        job.questionText ?? job.jobId,
        maxLines  : 2,
        overflow  : TextOverflow.ellipsis,
      ),
      subtitle : Text( job.agentType ?? job.status ),
      trailing : Chip(
        label          : Text( job.status, style: const TextStyle( fontSize: 11 ) ),
        backgroundColor: _statusColor( job.status ).withOpacity( 0.2 ),
      ),
      onTap    : () => Navigator.of( context ).push( MaterialPageRoute(
        builder: ( _ ) => BlocProvider.value(
          value: context.read<QueueBloc>(),
          child: JobDetailScreen( job: job ),
        ),
      ) ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView( { required this.message, required this.onRetry } );

  @override
  Widget build( BuildContext context ) => Center(
    child: Column( mainAxisSize: MainAxisSize.min, children: [
      Text( message, textAlign: TextAlign.center ),
      const SizedBox( height: 12 ),
      ElevatedButton( onPressed: onRetry, child: const Text( 'Retry' ) ),
    ] ),
  );
}
