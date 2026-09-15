import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/testing/test_keys.dart';
import '../../../services/diagnostics/round_trip_probe.dart';

/// Debug screen for [RoundTripProbe]: 20 health calls plus timed WAV uploads
/// on the app's shared Dio, with progress while running and a latency
/// summary + JSONL path at the end. Nothing runs until the user taps Run.
class RoundTripProbeScreen extends StatefulWidget {
  final Dio dio;

  /// Opens the JSONL destination for a run; defaults to [openProbeFileSink].
  final Future<ProbeSink> Function( DateTime now )? openSink;

  /// Network-type lookup; defaults to connectivity_plus.
  final NetworkTypeProvider? networkType;

  const RoundTripProbeScreen( { super.key, required this.dio, this.openSink, this.networkType } );

  @override
  State<RoundTripProbeScreen> createState() => _RoundTripProbeScreenState();
}

class _RoundTripProbeScreenState extends State<RoundTripProbeScreen> {
  bool         _running = false;
  int          _done    = 0;
  String?      _last;
  String?      _path;
  String?      _error;
  ProbeResult? _result;

  Future<void> _run() async {
    setState( () {
      _running = true;
      _done    = 0;
      _last    = null;
      _path    = null;
      _error   = null;
      _result  = null;
    } );
    ProbeSink? sink;
    try {
      final opener = widget.openSink ?? openProbeFileSink;
      sink         = await opener( DateTime.now() );
      if ( mounted ) setState( () => _path = sink!.path );
      final result = await RoundTripProbe( dio: widget.dio, networkType: widget.networkType ).run(
        sink,
        onProgress: ( done, total, s ) {
          if ( !mounted ) return;
          setState( () {
            _done = done;
            _last = '${s.kind}${s.sampleRate != null ? ' ${s.sampleRate}' : ''} · '
                '${s.totalMs.toStringAsFixed( 0 )} ms · ${s.status ?? '-'}'
                '${s.error != null ? ' · ${s.error}' : ''}';
          } );
        },
      );
      if ( mounted ) setState( () => _result = result );
    } catch ( e ) {
      if ( mounted ) setState( () => _error = e.toString() );
    } finally {
      await sink?.close();
      if ( mounted ) setState( () => _running = false );
    }
  }

  String _fmt( double? ms ) => ms == null ? '—' : ms.toStringAsFixed( 0 );

  @override
  Widget build( BuildContext context ) {
    final total  = RoundTripProbe.totalRequests;
    final result = _result;
    return Scaffold(
      appBar: AppBar( title: const Text( 'Debug: network round-trip probe' ) ),
      body: ListView(
        padding: const EdgeInsets.all( 16 ),
        children: [
          const Text(
            '${RoundTripProbe.healthCount} × GET ${RoundTripProbe.healthPath}, then '
            '${RoundTripProbe.uploadRepeats} × 30 s WAV upload at 44.1 kHz and 16 kHz, '
            'on the app\'s own HTTP client.',
          ),
          const SizedBox( height: 16 ),
          FilledButton.icon(
            key       : const Key( TestKeys.probeRunButton ),
            icon      : const Icon( Icons.network_check ),
            label     : Text( _running ? 'Running…' : 'Run probe' ),
            onPressed : _running ? null : _run,
          ),
          if ( _running ) ...[
            const SizedBox( height: 16 ),
            LinearProgressIndicator(
              key   : const Key( TestKeys.probeProgress ),
              value : _done / total,
            ),
            const SizedBox( height: 8 ),
            Text( '$_done / $total' ),
            if ( _last != null ) Text( _last!, style: Theme.of( context ).textTheme.bodySmall ),
          ],
          if ( _error != null ) ...[
            const SizedBox( height: 16 ),
            Text( 'Probe failed: $_error',
                style: TextStyle( color: Theme.of( context ).colorScheme.error ) ),
          ],
          if ( result != null ) ...[
            const SizedBox( height: 16 ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: const [
                  DataColumn( label: Text( 'Kind' ) ),
                  DataColumn( label: Text( 'n' ),        numeric: true ),
                  DataColumn( label: Text( 'p50 ms' ),   numeric: true ),
                  DataColumn( label: Text( 'p90 ms' ),   numeric: true ),
                  DataColumn( label: Text( 'max ms' ),   numeric: true ),
                  DataColumn( label: Text( 'failures' ), numeric: true ),
                ],
                rows: [
                  for ( final g in result.groups )
                    DataRow( cells: [
                      DataCell( Text( g.label ) ),
                      DataCell( Text( '${g.n}' ) ),
                      DataCell( Text( _fmt( g.p50 ) ) ),
                      DataCell( Text( _fmt( g.p90 ) ) ),
                      DataCell( Text( _fmt( g.max ) ) ),
                      DataCell( Text( '${g.failures}' ) ),
                    ] ),
                ],
              ),
            ),
            const SizedBox( height: 8 ),
            Text( 'Network: ${result.networkTypes.join( ', ' )}' ),
          ],
          if ( _path != null ) ...[
            const SizedBox( height: 16 ),
            SelectableText( 'Log: $_path' ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key       : const Key( TestKeys.probeCopyPathButton ),
                icon      : const Icon( Icons.copy ),
                label     : const Text( 'Copy path' ),
                onPressed : () async {
                  await Clipboard.setData( ClipboardData( text: _path! ) );
                  if ( !context.mounted ) return;
                  ScaffoldMessenger.of( context ).showSnackBar(
                    const SnackBar( content: Text( 'Path copied' ) ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }
}
