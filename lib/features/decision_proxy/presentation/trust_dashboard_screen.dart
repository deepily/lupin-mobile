import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/decision_proxy_models.dart';
import '../domain/decision_proxy_bloc.dart';
import '../domain/decision_proxy_event.dart';
import '../domain/decision_proxy_state.dart';

class TrustDashboardScreen extends StatefulWidget {
  final String userEmail;
  const TrustDashboardScreen( { super.key, required this.userEmail } );

  @override
  State<TrustDashboardScreen> createState() => _TrustDashboardScreenState();
}

class _TrustDashboardScreenState extends State<TrustDashboardScreen> {
  @override
  void initState() {
    super.initState();
    context.read<DecisionProxyBloc>().add(
      DecisionProxyLoadDashboard( widget.userEmail ),
    );
  }

  Color _modeColor( TrustMode m ) {
    switch ( m ) {
      case TrustMode.disabled: return Colors.grey;
      case TrustMode.shadow:   return Colors.blue;
      case TrustMode.suggest:  return Colors.orange;
      case TrustMode.active:   return Colors.green;
      case TrustMode.unknown:  return Colors.red;
    }
  }

  Future<void> _refresh() async {
    context.read<DecisionProxyBloc>().add(
      DecisionProxyLoadDashboard( widget.userEmail ),
    );
  }

  Future<bool> _confirmModeChange( BuildContext ctx, TrustMode from, TrustMode to ) async {
    if ( from != TrustMode.active ) return true;
    final ok = await showDialog<bool>(
      context: ctx,
      builder: ( c ) => AlertDialog(
        title  : const Text( "Downshift trust mode?" ),
        content: Text( "Switching from active to ${trustModeToString( to )}. "
                       "Already-running jobs may be affected." ),
        actions: [
          TextButton( onPressed: () => Navigator.of( c ).pop( false ), child: const Text( "Cancel" ) ),
          FilledButton( onPressed: () => Navigator.of( c ).pop( true ), child: const Text( "Switch" ) ),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build( BuildContext context ) {
    return Scaffold(
      appBar: AppBar( title: const Text( "Trust Dashboard" ) ),
      body: BlocBuilder<DecisionProxyBloc, DecisionProxyState>(
        builder: ( context, state ) {
          if ( state is DecisionProxyLoading || state is DecisionProxyInitial ) {
            return const Center( child: CircularProgressIndicator() );
          }
          if ( state is DecisionProxyError ) {
            return Center( child: Text( state.message ) );
          }
          if ( state is DecisionProxyDashboardLoaded ) {
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                children: [
                  _ModeHeader(
                    mode      : state.mode,
                    onPick    : ( newMode ) async {
                      final ok = await _confirmModeChange(
                        context,
                        state.mode.effective,
                        newMode,
                      );
                      if ( ok && context.mounted ) {
                        context.read<DecisionProxyBloc>().add(
                          DecisionProxySetMode( mode: newMode ),
                        );
                      }
                    },
                    color     : _modeColor( state.mode.effective ),
                  ),
                  if ( state.pending.isEmpty )
                    const Padding(
                      padding: EdgeInsets.all( 32 ),
                      child: Center( child: Text( "No pending decisions" ) ),
                    )
                  else
                    ...state.pending.map( ( d ) => _DecisionCard(
                      decision  : d,
                      userEmail : widget.userEmail,
                    ) ),
                  const Divider(),
                  _SummaryFooter(
                    summary: state.summary,
                    batch  : state.batch,
                    onAck  : () => context.read<DecisionProxyBloc>().add(
                      DecisionProxyAcknowledge( widget.userEmail ),
                    ),
                  ),
                ],
              ),
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}

class _ModeHeader extends StatelessWidget {
  final TrustModeStatus            mode;
  final void Function( TrustMode ) onPick;
  final Color                      color;

  const _ModeHeader( {
    required this.mode,
    required this.onPick,
    required this.color,
  } );

  @override
  Widget build( BuildContext context ) {
    return Card(
      margin: const EdgeInsets.all( 12 ),
      child: Padding(
        padding: const EdgeInsets.all( 16 ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon( Icons.shield, color: color ),
                const SizedBox( width: 8 ),
                Text(
                  "Effective: ${trustModeToString( mode.effective )}",
                  style: Theme.of( context ).textTheme.titleMedium,
                ),
              ],
            ),
            const SizedBox( height: 4 ),
            Text(
              "ini=${trustModeToString( mode.iniMode )}"
              + ( mode.runningMode != null
                  ? " · running=${trustModeToString( mode.runningMode! )}"
                  : "" ),
              style: Theme.of( context ).textTheme.bodySmall,
            ),
            const SizedBox( height: 12 ),
            SegmentedButton<TrustMode>(
              segments: const [
                ButtonSegment( value: TrustMode.disabled, label: Text( "Off"     ) ),
                ButtonSegment( value: TrustMode.shadow,   label: Text( "Shadow"  ) ),
                ButtonSegment( value: TrustMode.suggest,  label: Text( "Suggest" ) ),
                ButtonSegment( value: TrustMode.active,   label: Text( "Active"  ) ),
              ],
              selected: { mode.effective },
              onSelectionChanged: ( s ) => onPick( s.first ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DecisionCard extends StatelessWidget {
  final ProxyDecision decision;
  final String        userEmail;

  const _DecisionCard( { required this.decision, required this.userEmail } );

  @override
  Widget build( BuildContext context ) {
    return Card(
      margin: const EdgeInsets.symmetric( horizontal: 12, vertical: 4 ),
      child: Padding(
        padding: const EdgeInsets.all( 12 ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text( decision.category, style: const TextStyle( fontSize: 11 ) ),
                ),
                const SizedBox( width: 6 ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text( "L${decision.trustLevel}", style: const TextStyle( fontSize: 11 ) ),
                ),
                const Spacer(),
                Text( "${( decision.confidence * 100 ).toStringAsFixed( 0 )}%",
                  style: Theme.of( context ).textTheme.bodySmall ),
              ],
            ),
            const SizedBox( height: 8 ),
            Text( decision.question,
              style: Theme.of( context ).textTheme.bodyLarge ),
            if ( decision.reason.isNotEmpty ) ...[
              const SizedBox( height: 4 ),
              Text( decision.reason,
                style: Theme.of( context ).textTheme.bodySmall ),
            ],
            const SizedBox( height: 12 ),
            Row(
              children: [
                IconButton(
                  tooltip: "Reject",
                  icon: const Icon( Icons.close ),
                  color: Colors.red,
                  onPressed: () => context.read<DecisionProxyBloc>().add(
                    DecisionProxyRatify(
                      decisionId : decision.id,
                      userEmail  : userEmail,
                      approved   : false,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: "Approve",
                  icon: const Icon( Icons.check ),
                  color: Colors.green,
                  onPressed: () => context.read<DecisionProxyBloc>().add(
                    DecisionProxyRatify(
                      decisionId : decision.id,
                      userEmail  : userEmail,
                      approved   : true,
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  tooltip: "Delete",
                  icon: const Icon( Icons.delete_outline ),
                  onPressed: () => context.read<DecisionProxyBloc>().add(
                    DecisionProxyDeleteDecision(
                      decisionId : decision.id,
                      userEmail  : userEmail,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryFooter extends StatelessWidget {
  final PendingSummary    summary;
  final BatchIdResponse?  batch;
  final VoidCallback      onAck;

  const _SummaryFooter( {
    required this.summary,
    required this.batch,
    required this.onAck,
  } );

  @override
  Widget build( BuildContext context ) {
    return Padding(
      padding: const EdgeInsets.all( 16 ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text( "${summary.totalPending} pending",
            style: Theme.of( context ).textTheme.titleSmall ),
          if ( summary.oldestPending != null )
            Text( "Oldest: ${summary.oldestPending}",
              style: Theme.of( context ).textTheme.bodySmall ),
          if ( batch != null ) ...[
            const SizedBox( height: 4 ),
            Text( "Batch: ${batch!.batchId}",
              style: Theme.of( context ).textTheme.bodySmall ),
          ],
          const SizedBox( height: 12 ),
          OutlinedButton.icon(
            icon  : const Icon( Icons.check_circle_outline ),
            label : const Text( "Acknowledge batch" ),
            onPressed: onAck,
          ),
        ],
      ),
    );
  }
}
