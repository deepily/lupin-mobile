import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lupin_mobile/services/asr/asr_service.dart';
import 'package:lupin_mobile/services/diagnostics/round_trip_probe.dart';

/// Adapter that drains the request body (so Dio's onSendProgress fires, as it
/// does on a real socket), records every request, and can fail chosen calls.
class _ProbeAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests  = [];
  final List<int>            bodyBytes = [];

  /// Zero-based request indices that should fail at the transport layer.
  final Set<int> throwOn;

  /// Zero-based request indices that should answer 500.
  final Set<int> serverErrorOn;

  /// Zero-based request indices whose body is NOT drained (send never completes).
  final Set<int> skipDrainOn;

  /// Called as each request arrives, with its zero-based index.
  final void Function( int index )? onFetch;

  /// Zero-based request indices that never answer on their own (only a cancel ends them).
  final Set<int> hangOn;

  _ProbeAdapter( {
    this.throwOn       = const {},
    this.serverErrorOn = const {},
    this.skipDrainOn   = const {},
    this.hangOn        = const {},
    this.onFetch,
  } );

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final index = requests.length;
    requests.add( options );
    onFetch?.call( index );
    if ( hangOn.contains( index ) ) {
      await Completer<void>().future;
    }
    var n = 0;
    if ( requestStream != null && !skipDrainOn.contains( index ) ) {
      await for ( final chunk in requestStream ) {
        n += chunk.length;
      }
    }
    bodyBytes.add( n );
    if ( throwOn.contains( index ) ) {
      throw DioException.connectionError(
        requestOptions : options,
        reason         : 'simulated drop',
      );
    }
    final status = serverErrorOn.contains( index ) ? 500 : 200;
    final body   = options.path == AsrService.endpointPath ? '"a transcript"' : '{"status":"ok"}';
    return ResponseBody.fromString(
      body,
      status,
      headers: { Headers.contentTypeHeader: [ Headers.jsonContentType ] },
    );
  }

  @override
  void close( { bool force = false } ) {}
}

class _MemorySink implements ProbeSink {
  final List<String> lines = [];
  @override
  String get path => '/memory/round-trip-probe-test.jsonl';
  @override
  Future<void> writeLine( String line ) async => lines.add( line );
  @override
  Future<void> close() async {}
}

/// Interceptor that counts what passes through the Dio it is attached to.
class _CountingInterceptor extends Interceptor {
  int seen = 0;
  @override
  void onRequest( RequestOptions options, RequestInterceptorHandler handler ) {
    seen++;
    handler.next( options );
  }
}

/// Gives the upload a body whose length the client cannot state: the data
/// becomes a raw byte stream and content-length says -1, so Dio reports send
/// progress against a non-positive total. That is the only way `_upload` can
/// see `totalBytes <= 0`, and it is what a chunked / unknown-length body looks
/// like from inside the request. The probe's own code still decides what to
/// log — nothing about ProbeSample is faked here.
class _UnknownLengthBody extends Interceptor {
  @override
  void onRequest( RequestOptions options, RequestInterceptorHandler handler ) {
    if ( options.path == AsrService.endpointPath ) {
      options.data = Stream<List<int>>.fromIterable( [ [ 1, 2, 3 ], [ 4, 5, 6 ] ] );
      options.headers[ Headers.contentLengthHeader ] = '-1';
    }
    handler.next( options );
  }
}

Future<Uint8List> _tinyClip( int rate ) async => Uint8List( 44 + rate ~/ 100 );

void main() {
  group( 'RoundTripProbe.percentile (nearest rank)', () {
    test( 'empty list gives null', () {
      expect( RoundTripProbe.percentile( [], 50 ), isNull );
    } );

    test( 'values 1..10: p50 = 5, p90 = 9, p100 = 10', () {
      final v = [ for ( var i = 10; i >= 1; i-- ) i.toDouble() ];
      expect( RoundTripProbe.percentile( v, 50 ),  5 );
      expect( RoundTripProbe.percentile( v, 90 ),  9 );
      expect( RoundTripProbe.percentile( v, 100 ), 10 );
    } );

    test( 'single value is every percentile', () {
      expect( RoundTripProbe.percentile( [ 42.0 ], 50 ), 42 );
      expect( RoundTripProbe.percentile( [ 42.0 ], 90 ), 42 );
    } );

    test( 'n = 20: p90 is the 18th smallest', () {
      final v = [ for ( var i = 1; i <= 20; i++ ) i * 10.0 ];
      expect( RoundTripProbe.percentile( v, 50 ), 100 );
      expect( RoundTripProbe.percentile( v, 90 ), 180 );
    } );
  } );

  group( 'networkTypeName', () {
    test( 'maps to wifi / mobile / none / other', () {
      expect( networkTypeName( ConnectivityResult.wifi ),     'wifi' );
      expect( networkTypeName( ConnectivityResult.mobile ),   'mobile' );
      expect( networkTypeName( ConnectivityResult.none ),     'none' );
      expect( networkTypeName( ConnectivityResult.ethernet ), 'other' );
      expect( networkTypeName( ConnectivityResult.vpn ),      'other' );
    } );
  } );

  test( 'fileNameFor pads to yyyyMMdd-HHmmss', () {
    expect( RoundTripProbe.fileNameFor( DateTime( 2026, 9, 5, 7, 3, 9 ) ),
        'round-trip-probe-20260905-070309.jsonl' );
  } );

  group( 'RoundTripProbe.run', () {
    late _ProbeAdapter        adapter;
    late Dio                  dio;
    late _MemorySink          sink;
    late _CountingInterceptor counter;

    RoundTripProbe probeWith( { NetworkTypeProvider? network } ) => RoundTripProbe(
      dio         : dio,
      networkType : network ?? () async => 'wifi',
      clock       : () => DateTime.utc( 2026, 9, 15, 12 ),
      clipFor     : _tinyClip,
    );

    setUp( () {
      adapter = _ProbeAdapter();
      counter = _CountingInterceptor();
      dio     = Dio( BaseOptions( baseUrl: 'http://probe.test' ) )
        ..httpClientAdapter = adapter
        ..interceptors.add( counter );
      sink    = _MemorySink();
    } );

    test( 'makes exactly 20 health calls then 6 uploads (3 per sample rate, interleaved)', () async {
      final result = await probeWith().run( sink );

      final paths = adapter.requests.map( ( r ) => '${r.method} ${r.path}' ).toList();
      expect( paths.length, 26 );
      expect( paths.take( 20 ), everyElement( 'GET /health' ) );
      expect( paths.skip( 20 ), everyElement( 'POST ${AsrService.endpointPath}' ) );

      final uploads = result.samples.where( ( s ) => s.kind == 'upload' ).toList();
      expect( uploads.map( ( s ) => s.sampleRate ), [ 44100, 16000, 44100, 16000, 44100, 16000 ] );
      expect( uploads.map( ( s ) => s.bytes ), [ 485, 204, 485, 204, 485, 204 ] );
      expect( result.samples.where( ( s ) => s.kind == 'health' ).length, 20 );
    } );

    test( 'uses the injected Dio and its interceptors, not a new client', () async {
      await probeWith().run( sink );
      expect( counter.seen, 26 );
      expect( adapter.requests.every( ( r ) => r.baseUrl == 'http://probe.test' ), isTrue );
    } );

    test( 'upload body carries the clip and records send-complete time', () async {
      final result = await probeWith().run( sink );
      final upload = result.samples.firstWhere( ( s ) => s.kind == 'upload' );
      expect( adapter.bodyBytes[ 20 ], greaterThan( 485 ) );    // multipart wraps the WAV
      expect( upload.sendMs, isNotNull );
      expect( upload.sendMs!, lessThanOrEqualTo( upload.totalMs ) );
      expect( upload.status, 200 );
    } );

    test( 'records the network type per sample', () async {
      var call = 0;
      final result = await probeWith(
        network: () async => ( call++ ).isEven ? 'wifi' : 'mobile',
      ).run( sink );
      expect( result.samples.length, 26 );
      for ( var i = 0; i < result.samples.length; i++ ) {
        expect( result.samples[ i ].networkType, i.isEven ? 'wifi' : 'mobile' );
      }
      expect( result.networkTypes, { 'wifi', 'mobile' } );
    } );

    test( 'a network-type lookup that throws is logged as other and the run goes on', () async {
      final result = await probeWith( network: () async => throw StateError( 'no plugin' ) ).run( sink );
      expect( result.samples.length, 26 );
      expect( result.networkTypes, { 'other' } );
    } );

    test( 'failing requests become failure samples and do not abort the run', () async {
      adapter = _ProbeAdapter( throwOn: { 3 }, serverErrorOn: { 22 } );
      dio.httpClientAdapter = adapter;

      final progress = <int>[];
      final result   = await probeWith().run( sink, onProgress: ( done, total, _ ) {
        expect( total, 26 );
        progress.add( done );
      } );

      expect( adapter.requests.length, 26 );
      expect( progress, [ for ( var i = 1; i <= 26; i++ ) i ] );

      final dropped = result.samples[ 3 ];
      expect( dropped.ok, isFalse );
      expect( dropped.status, isNull );
      expect( dropped.error, contains( 'connectionError' ) );

      final serverError = result.samples[ 22 ];
      expect( serverError.kind, 'upload' );
      expect( serverError.status, 500 );
      expect( serverError.error, isNotNull );

      final health = result.groups.firstWhere( ( g ) => g.label == 'health' );
      expect( health.n, 20 );
      expect( health.failures, 1 );
      expect( health.p50, isNotNull );

      final up44 = result.groups.firstWhere( ( g ) => g.label == 'upload 44.1 kHz' );
      final up16 = result.groups.firstWhere( ( g ) => g.label == 'upload 16 kHz' );
      expect( up44.n, 3 );
      expect( up16.n, 3 );
      expect( up44.failures + up16.failures, 1 );
    } );

    test( 'every JSONL line parses and carries the required fields', () async {
      adapter = _ProbeAdapter( throwOn: { 0 } );
      dio.httpClientAdapter = adapter;
      final result = await probeWith().run( sink );

      expect( result.outputPath, sink.path );
      expect( sink.lines.length, 26 );
      for ( final line in sink.lines ) {
        expect( line.contains( '\n' ), isFalse );
        final m = jsonDecode( line ) as Map<String, dynamic>;
        expect( DateTime.tryParse( m[ 'timestamp' ] as String ), isNotNull );
        expect( m[ 'timestamp' ], '2026-09-15T12:00:00.000Z' );
        expect( m[ 'kind' ], anyOf( 'health', 'upload' ) );
        expect( m[ 'network_type' ], 'wifi' );
        expect( m[ 'total_ms' ], isA<num>() );
        expect( m.containsKey( 'status' ), isTrue );
        expect( m.containsKey( 'error' ), isTrue );
        if ( m[ 'kind' ] == 'upload' ) {
          expect( m[ 'sample_rate' ], anyOf( 44100, 16000 ) );
          expect( m[ 'bytes' ], isA<int>() );
          expect( m.containsKey( 'send_ms' ), isTrue );
          expect( m[ 'total_ms_includes_transcription' ], isTrue );
          expect( m[ 'send_ms' ], isNotNull );
          expect( m.containsKey( 'send_ms_null_reason' ), isFalse );
        } else {
          expect( m.containsKey( 'sample_rate' ), isFalse );
          expect( m.containsKey( 'total_ms_includes_transcription' ), isFalse );
          expect( m.containsKey( 'send_ms_null_reason' ), isFalse );
        }
      }
      final first = jsonDecode( sink.lines.first ) as Map<String, dynamic>;
      expect( first[ 'error' ], isNotNull );
    } );

    test( 'an upload whose body never finished sending logs send_ms null with reason not_fully_sent', () async {
      adapter = _ProbeAdapter( skipDrainOn: { 20 }, throwOn: { 20 } );
      dio.httpClientAdapter = adapter;
      await probeWith().run( sink );

      final m = jsonDecode( sink.lines[ 20 ] ) as Map<String, dynamic>;
      expect( m[ 'kind' ], 'upload' );
      expect( m[ 'send_ms' ], isNull );
      expect( m[ 'send_ms_null_reason' ], 'not_fully_sent' );
      expect( m[ 'total_ms_includes_transcription' ], isTrue );
    } );

    // Fold-later from the probe review (row 8d9b2a0c): the unknown_length arm
    // of `_upload` was only ever seen through a hand-built ProbeSample, so
    // nothing proved the probe itself could reach it. This drives the real
    // request path.
    test( 'an upload whose body length the client cannot state logs send_ms null with reason unknown_length', () async {
      dio.interceptors.add( _UnknownLengthBody() );
      await probeWith().run( sink );

      final m = jsonDecode( sink.lines[ 20 ] ) as Map<String, dynamic>;
      expect( m[ 'kind' ], 'upload' );
      expect( m[ 'status' ], 200, reason: 'the request SUCCEEDED — only its send time is unmeasurable' );
      expect( m[ 'send_ms' ], isNull );
      expect(
        m[ 'send_ms_null_reason' ],
        'unknown_length',
        reason: 'not_fully_sent would blame the network for a body nobody could measure',
      );
    } );

    test( 'both clips are built once, before the first request is timed', () async {
      final builtBeforeFirstRequest = <int>[];
      final built                   = <int>[];
      adapter = _ProbeAdapter( onFetch: ( i ) {
        if ( i == 0 ) builtBeforeFirstRequest.addAll( built );
      } );
      dio.httpClientAdapter = adapter;

      await RoundTripProbe(
        dio         : dio,
        networkType : () async => 'wifi',
        clipFor     : ( rate ) async { built.add( rate ); return _tinyClip( rate ); },
      ).run( sink );

      expect( built, [ 44100, 16000 ] );
      expect( builtBeforeFirstRequest, [ 44100, 16000 ] );
    } );

    test( 'cancel between samples: no further requests, final line is kind=cancelled', () async {
      final token  = CancelToken();
      final result = await probeWith().run( sink, cancelToken: token, onProgress: ( done, _, __ ) {
        if ( done == 5 ) token.cancel( 'probe screen closed' );
      } );

      expect( adapter.requests.length, 5 );
      expect( result.cancelled, isTrue );
      expect( result.samples.length, 5 );
      expect( sink.lines.length, 6 );
      final last = jsonDecode( sink.lines.last ) as Map<String, dynamic>;
      expect( last[ 'kind' ], 'cancelled' );
      expect( last[ 'completed' ], 5 );
      expect( last[ 'total' ], 26 );
      expect( last[ 'reason' ], 'probe screen closed' );

      // Nothing trickles in afterwards.
      await Future<void>.delayed( const Duration( milliseconds: 20 ) );
      expect( adapter.requests.length, 5 );
      expect( sink.lines.length, 6 );
    } );

    test( 'cancel during an in-flight upload aborts it, discards its sample, and stops', () async {
      final token = CancelToken();
      adapter = _ProbeAdapter(
        hangOn  : { 21 },
        onFetch : ( i ) { if ( i == 21 ) Future<void>.microtask( () => token.cancel( 'closed' ) ); },
      );
      dio.httpClientAdapter = adapter;

      final result = await probeWith().run( sink, cancelToken: token );

      expect( adapter.requests.length, 22 );
      expect( result.cancelled, isTrue );
      expect( result.samples.length, 21 );
      expect( sink.lines.length, 22 );
      expect( ( jsonDecode( sink.lines.last ) as Map<String, dynamic> )[ 'kind' ], 'cancelled' );
    } );

    test( 'a token cancelled before the run starts makes no requests', () async {
      final token = CancelToken()..cancel();
      final result = await probeWith().run( sink, cancelToken: token );
      expect( adapter.requests, isEmpty );
      expect( result.cancelled, isTrue );
      expect( sink.lines.length, 1 );
      expect( ( jsonDecode( sink.lines.single ) as Map<String, dynamic> )[ 'kind' ], 'cancelled' );
    } );

    test( 'a run that finishes is not marked cancelled and has no cancelled line', () async {
      final result = await probeWith().run( sink, cancelToken: CancelToken() );
      expect( result.cancelled, isFalse );
      expect( sink.lines.map( ( l ) => ( jsonDecode( l ) as Map )[ 'kind' ] ), isNot( contains( 'cancelled' ) ) );
    } );
  } );

  test( 'ProbeSample.toJson: unknown body length is reported as send_ms_null_reason unknown_length', () {
    final m = ProbeSample(
      timestamp        : DateTime.utc( 2026 ),
      kind             : 'upload',
      sampleRate       : 16000,
      networkType      : 'mobile',
      totalMs          : 900,
      status           : 200,
      bytes            : 960044,
      sendMsNullReason : ProbeSample.sendNullUnknownLength,
    ).toJson();
    expect( m[ 'send_ms' ], isNull );
    expect( m[ 'send_ms_null_reason' ], 'unknown_length' );
    expect( m[ 'total_ms_includes_transcription' ], isTrue );
  } );

  test( 'summarise: percentiles exclude failures, max is the slowest ok sample', () {
    final t = DateTime.utc( 2026 );
    ProbeSample h( double ms, { int status = 200 } ) => ProbeSample(
      timestamp: t, kind: 'health', networkType: 'wifi', totalMs: ms, status: status,
    );
    final groups = RoundTripProbe.summarise( [ h( 10 ), h( 30 ), h( 20 ), h( 999, status: 503 ) ] );
    final health = groups.first;
    expect( health.n, 4 );
    expect( health.failures, 1 );
    expect( health.p50, 20 );
    expect( health.p90, 30 );
    expect( health.max, 30 );
    expect( groups[ 1 ].n, 0 );
    expect( groups[ 1 ].p50, isNull );
  } );
}
