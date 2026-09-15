import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';

import '../asr/asr_service.dart';
import 'probe_wav.dart';

/// Returns the current network type: `wifi`, `mobile`, `other` or `none`.
typedef NetworkTypeProvider = Future<String> Function();

/// Destination for probe samples, one JSON object per line.
abstract class ProbeSink {
  /// Where the lines end up, shown to the user (a file path for the real sink).
  String get path;

  /// Append one line (no trailing newline in [line]).
  Future<void> writeLine( String line );

  /// Flush and release the destination.
  Future<void> close();
}

/// [ProbeSink] that appends to a file.
class FileProbeSink implements ProbeSink {
  final File    _file;
  final IOSink  _out;

  FileProbeSink( File file ) : _file = file, _out = file.openWrite();

  @override
  String get path => _file.path;

  @override
  Future<void> writeLine( String line ) async => _out.writeln( line );

  @override
  Future<void> close() async {
    await _out.flush();
    await _out.close();
  }
}

/// Open the probe's JSONL file for a run starting at [now].
///
/// Requires:
///   - running on a device where path_provider is available
///
/// Ensures:
///   - the file lives in the app's external files directory when there is one
///     (pullable from /sdcard/Android/data/<package>/files/), else in the
///     app documents directory
///   - the file is named round-trip-probe-<yyyyMMdd-HHmmss>.jsonl
Future<FileProbeSink> openProbeFileSink( DateTime now ) async {
  Directory? dir;
  try {
    dir = await getExternalStorageDirectory();
  } catch ( _ ) {
    // Not supported on this platform (e.g. iOS) — fall through.
    dir = null;
  }
  dir ??= await getApplicationDocumentsDirectory();
  return FileProbeSink( File( '${dir.path}/${RoundTripProbe.fileNameFor( now )}' ) );
}

/// Map a connectivity_plus result to the probe's four network types.
///
/// Ensures:
///   - wifi → `wifi`, mobile → `mobile`, none → `none`, anything else → `other`
String networkTypeName( ConnectivityResult result ) {
  switch ( result ) {
    case ConnectivityResult.wifi   : return 'wifi';
    case ConnectivityResult.mobile : return 'mobile';
    case ConnectivityResult.none   : return 'none';
    default                        : return 'other';
  }
}

/// Default [NetworkTypeProvider], backed by connectivity_plus.
Future<String> connectivityNetworkType() async =>
    networkTypeName( await Connectivity().checkConnectivity() );

/// One measured request.
class ProbeSample {
  final DateTime timestamp;
  final String   kind;          // 'health' | 'upload'
  final int?     sampleRate;    // uploads only
  final String   networkType;
  final double   totalMs;
  final int?     status;
  final String?  error;
  final int?     bytes;         // uploads only: WAV size
  final double?  sendMs;        // uploads only: until the body finished sending

  const ProbeSample( {
    required this.timestamp,
    required this.kind,
    required this.networkType,
    required this.totalMs,
    this.sampleRate,
    this.status,
    this.error,
    this.bytes,
    this.sendMs,
  } );

  /// True when the request got a 2xx response and raised no error.
  bool get ok => error == null && status != null && status! >= 200 && status! < 300;

  Map<String, dynamic> toJson() => {
    'timestamp'    : timestamp.toUtc().toIso8601String(),
    'kind'         : kind,
    if ( sampleRate != null ) 'sample_rate' : sampleRate,
    'network_type' : networkType,
    if ( bytes != null ) 'bytes' : bytes,
    'total_ms'     : totalMs,
    if ( kind == 'upload' ) 'send_ms' : sendMs,
    'status'       : status,
    'error'        : error,
  };
}

/// Latency summary for one group of samples.
class ProbeGroupSummary {
  final String  label;
  final int     n;
  final double? p50;
  final double? p90;
  final double? max;
  final int     failures;

  const ProbeGroupSummary( {
    required this.label,
    required this.n,
    required this.p50,
    required this.p90,
    required this.max,
    required this.failures,
  } );
}

/// What a finished run produced.
class ProbeResult {
  final List<ProbeSample>       samples;
  final List<ProbeGroupSummary> groups;
  final Set<String>             networkTypes;
  final String                  outputPath;

  const ProbeResult( {
    required this.samples,
    required this.groups,
    required this.networkTypes,
    required this.outputPath,
  } );
}

/// Measures how long real requests take through the app's own HTTP stack.
///
/// Runs [healthCount] sequential `GET /health` calls, then [uploadRepeats]
/// timed WAV uploads at each of [uploadSampleRates] (interleaved), all on
/// the injected [Dio] — which in the app is the SHARED instance, so the auth
/// interceptor and HttpService interceptors are part of what is measured.
///
/// The upload goes to [AsrService.endpointPath], the transcription endpoint
/// the app's own speech-to-text path uses; it does not submit a job.
class RoundTripProbe {
  static const String healthPath         = '/health';
  static const int    healthCount        = 20;
  static const int    uploadRepeats      = 3;
  static const List<int> uploadSampleRates = [ 44100, 16000 ];

  final Dio                      _dio;
  final NetworkTypeProvider      _networkType;
  final Stopwatch Function()     _newStopwatch;
  final DateTime Function()      _now;
  final Uint8List Function( int sampleRate ) _clipFor;

  RoundTripProbe( {
    required Dio dio,
    NetworkTypeProvider? networkType,
    Stopwatch Function()? stopwatchFactory,
    DateTime Function()? clock,
    Uint8List Function( int sampleRate )? clipFor,
  } ) : _dio          = dio,
        _networkType  = networkType      ?? connectivityNetworkType,
        _newStopwatch = stopwatchFactory ?? Stopwatch.new,
        _now          = clock            ?? DateTime.now,
        _clipFor      = clipFor          ?? ( ( rate ) => ProbeWav.generate( sampleRate: rate ) );

  /// Total number of requests one run makes.
  static int get totalRequests => healthCount + uploadRepeats * uploadSampleRates.length;

  /// `round-trip-probe-<yyyyMMdd-HHmmss>.jsonl` for [t] (local time fields).
  static String fileNameFor( DateTime t ) {
    String two( int v ) => v.toString().padLeft( 2, '0' );
    final date = '${t.year.toString().padLeft( 4, '0' )}${two( t.month )}${two( t.day )}';
    final time = '${two( t.hour )}${two( t.minute )}${two( t.second )}';
    return 'round-trip-probe-$date-$time.jsonl';
  }

  /// Nearest-rank percentile of [values].
  ///
  /// Requires:
  ///   - 0 < p <= 100
  ///
  /// Ensures:
  ///   - returns null for an empty list
  ///   - otherwise returns the element at rank ceil(p/100 * n) of the sorted
  ///     values, so the result is always one of the inputs
  static double? percentile( List<double> values, double p ) {
    if ( values.isEmpty ) return null;
    final sorted = [ ...values ]..sort();
    final rank   = ( p / 100.0 * sorted.length ).ceil().clamp( 1, sorted.length );
    return sorted[ rank - 1 ];
  }

  /// Summarise [samples] into health, then one group per upload sample rate.
  ///
  /// Ensures:
  ///   - n counts every sample in the group; failures counts the non-ok ones
  ///   - p50 / p90 / max are over the ok samples' total_ms (null if none)
  static List<ProbeGroupSummary> summarise( List<ProbeSample> samples ) {
    ProbeGroupSummary group( String label, Iterable<ProbeSample> members ) {
      final list = members.toList();
      final ms   = list.where( ( s ) => s.ok ).map( ( s ) => s.totalMs ).toList();
      return ProbeGroupSummary(
        label    : label,
        n        : list.length,
        p50      : percentile( ms, 50 ),
        p90      : percentile( ms, 90 ),
        max      : ms.isEmpty ? null : ms.reduce( math.max ),
        failures : list.where( ( s ) => !s.ok ).length,
      );
    }

    return [
      group( 'health', samples.where( ( s ) => s.kind == 'health' ) ),
      for ( final rate in uploadSampleRates )
        group( 'upload ${_khz( rate )} kHz',
            samples.where( ( s ) => s.kind == 'upload' && s.sampleRate == rate ) ),
    ];
  }

  /// Run the whole probe, writing each sample to [sink] as it completes.
  ///
  /// Requires:
  ///   - [sink] is open; the caller owns closing it
  ///
  /// Ensures:
  ///   - exactly [healthCount] health requests and
  ///     uploadRepeats × uploadSampleRates.length uploads are attempted, in
  ///     sequence, on the injected Dio
  ///   - a failed request becomes a sample with its error and the run goes on
  ///   - [onProgress] is called after every sample with (done, total, sample)
  ///   - returns every sample, the summary, and the network types seen
  Future<ProbeResult> run(
    ProbeSink sink, {
    void Function( int done, int total, ProbeSample sample )? onProgress,
  } ) async {
    final samples = <ProbeSample>[];
    final total   = totalRequests;

    Future<void> record( ProbeSample s ) async {
      samples.add( s );
      await sink.writeLine( jsonEncode( s.toJson() ) );
      onProgress?.call( samples.length, total, s );
    }

    for ( var i = 0; i < healthCount; i++ ) {
      await record( await _health() );
    }

    final clips = { for ( final rate in uploadSampleRates ) rate: _clipFor( rate ) };
    for ( var i = 0; i < uploadRepeats; i++ ) {
      for ( final rate in uploadSampleRates ) {
        await record( await _upload( rate, clips[ rate ]! ) );
      }
    }

    return ProbeResult(
      samples      : samples,
      groups       : summarise( samples ),
      networkTypes : samples.map( ( s ) => s.networkType ).toSet(),
      outputPath   : sink.path,
    );
  }

  Future<String> _safeNetworkType() async {
    // A lookup that throws or never answers must not stall the run.
    try {
      return await _networkType().timeout( const Duration( seconds: 2 ) );
    } catch ( _ ) {
      return 'other';
    }
  }

  /// 44100 → "44.1", 16000 → "16".
  static String _khz( int rate ) =>
      rate % 1000 == 0 ? '${rate ~/ 1000}' : ( rate / 1000 ).toString();

  static double _ms( Stopwatch sw ) => sw.elapsedMicroseconds / 1000.0;

  Future<ProbeSample> _health() async {
    final network   = await _safeNetworkType();
    final timestamp = _now();
    final sw        = _newStopwatch()..start();
    int?    status;
    String? error;
    try {
      final res = await _dio.get<dynamic>( healthPath );
      status = res.statusCode;
    } on DioException catch ( e ) {
      status = e.response?.statusCode;
      error  = _describe( e );
    } catch ( e ) {
      error  = e.toString();
    }
    sw.stop();
    return ProbeSample(
      timestamp   : timestamp,
      kind        : 'health',
      networkType : network,
      totalMs     : _ms( sw ),
      status      : status,
      error       : error,
    );
  }

  Future<ProbeSample> _upload( int sampleRate, Uint8List clip ) async {
    final network   = await _safeNetworkType();
    final timestamp = _now();
    final form      = FormData.fromMap( {
      'file': MultipartFile.fromBytes(
        clip,
        filename    : 'round-trip-probe-$sampleRate.wav',
        contentType : DioMediaType( 'audio', 'wav' ),
      ),
    } );
    final sw = _newStopwatch()..start();
    double? sendMs;
    int?    status;
    String? error;
    try {
      final res = await _dio.post<dynamic>(
        AsrService.endpointPath,
        data           : form,
        options        : Options(
          // Same budgets as AsrService: cellular upload + Whisper inference.
          sendTimeout    : const Duration( seconds: 60 ),
          receiveTimeout : const Duration( seconds: 120 ),
        ),
        onSendProgress : ( sent, totalBytes ) {
          if ( sendMs == null && totalBytes > 0 && sent >= totalBytes ) sendMs = _ms( sw );
        },
      );
      status = res.statusCode;
    } on DioException catch ( e ) {
      status = e.response?.statusCode;
      error  = _describe( e );
    } catch ( e ) {
      error  = e.toString();
    }
    sw.stop();
    return ProbeSample(
      timestamp   : timestamp,
      kind        : 'upload',
      sampleRate  : sampleRate,
      networkType : network,
      totalMs     : _ms( sw ),
      status      : status,
      error       : error,
      bytes       : clip.length,
      sendMs      : sendMs,
    );
  }

  static String _describe( DioException e ) =>
      e.message == null ? e.type.name : '${e.type.name}: ${e.message}';
}
