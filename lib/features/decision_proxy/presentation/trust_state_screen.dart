import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/testing/test_keys.dart';
import '../data/decision_proxy_models.dart';
import '../domain/decision_proxy_bloc.dart';
import '../domain/decision_proxy_event.dart';
import '../domain/decision_proxy_state.dart';

class TrustStateScreen extends StatefulWidget {
  final String userEmail;
  const TrustStateScreen( { super.key, required this.userEmail } );

  @override
  State<TrustStateScreen> createState() => _TrustStateScreenState();
}

class _TrustStateScreenState extends State<TrustStateScreen> {
  @override
  void initState() {
    super.initState();
    context.read<DecisionProxyBloc>().add(
      DecisionProxyLoadTrust( userEmail: widget.userEmail ),
    );
  }

  Future<void> _refresh() async {
    context.read<DecisionProxyBloc>().add(
      DecisionProxyLoadTrust( userEmail: widget.userEmail ),
    );
  }

  Map<String, List<TrustStateItem>> _groupByDomain( List<TrustStateItem> items ) {
    final out = <String, List<TrustStateItem>>{};
    for ( final i in items ) {
      out.putIfAbsent( i.domain, () => [] ).add( i );
    }
    return out;
  }

  @override
  Widget build( BuildContext context ) {
    return Scaffold(
      appBar: AppBar( title: const Text( "Trust Details" ) ),
      body: BlocBuilder<DecisionProxyBloc, DecisionProxyState>(
        builder: ( context, state ) {
          if ( state is DecisionProxyLoading || state is DecisionProxyInitial ) {
            return const Center( child: CircularProgressIndicator() );
          }
          if ( state is DecisionProxyError ) {
            return Center( child: Text( state.message ) );
          }
          if ( state is DecisionProxyTrustLoaded ) {
            final items = state.trust.trustStates;
            if ( items.isEmpty ) {
              return RefreshIndicator(
                onRefresh: _refresh,
                child: ListView(
                  children: const [
                    Padding(
                      padding: EdgeInsets.all( 32 ),
                      child: Center( child: Text( "No trust states" ) ),
                    ),
                  ],
                ),
              );
            }
            final grouped = _groupByDomain( items );
            final domains = grouped.keys.toList()..sort();
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                children: [
                  for ( final domain in domains ) ...[
                    Padding(
                      key: Key( '${TestKeys.trustStateDomainHeaderPrefix}$domain' ),
                      padding: const EdgeInsets.fromLTRB( 16, 16, 16, 4 ),
                      child: Row(
                        children: [
                          const Icon( Icons.domain, size: 18 ),
                          const SizedBox( width: 8 ),
                          Text( domain, style: Theme.of( context ).textTheme.titleSmall ),
                        ],
                      ),
                    ),
                    ...grouped[ domain ]!.map( ( item ) => _TrustStateRow( item: item ) ),
                  ],
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

class _TrustStateRow extends StatelessWidget {
  final TrustStateItem item;
  const _TrustStateRow( { required this.item } );

  @override
  Widget build( BuildContext context ) {
    final breakerOpen = item.circuitBreakerState == "open";
    return Card(
      key: Key( '${TestKeys.trustStateRowPrefix}${item.domain}:${item.category}' ),
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
                  label: Text( item.category, style: const TextStyle( fontSize: 11 ) ),
                ),
                const SizedBox( width: 6 ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text( "L${item.trustLevel}", style: const TextStyle( fontSize: 11 ) ),
                ),
                if ( breakerOpen ) ...[
                  const SizedBox( width: 6 ),
                  const Chip(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: Color( 0xFFFFCDD2 ),
                    label: Text( "circuit open", style: TextStyle( fontSize: 11 ) ),
                  ),
                ],
              ],
            ),
            const SizedBox( height: 8 ),
            Text(
              "${item.totalDecisions} total · ${item.successfulDecisions} approved · ${item.rejectedDecisions} rejected",
              style: Theme.of( context ).textTheme.bodySmall,
            ),
            if ( item.updatedAt != null ) ...[
              const SizedBox( height: 4 ),
              Text(
                "Updated: ${item.updatedAt!.toIso8601String()}",
                style: Theme.of( context ).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
