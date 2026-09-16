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

/// The shell command that copies one probe log off a debug build.
const String probeLogPullHint =
    'adb exec-out run-as ai.deepily.lupin_mobile cat files/<name>.jsonl > <name>.jsonl';

/// Open the probe's JSONL file for a run starting at [now].
///
/// Why INTERNAL storage (row 7ef8f124). This used to write to
/// `getExternalStorageDirectory()`, i.e. `/sdcard/Android/data/<package>/files/`,
/// on the belief that it was pullable. Since Android 11 it is not: `adb pull`
/// and `adb exec-out run-as … cat` are both refused there. Measured
/// 2026-09-16 for kept recordings (row 4be8fe63), which lived in the same
/// place. The app support directory (`/data/user/0/<package>/files/` on
/// Android) is readable by `run-as` on any debuggable build, and run-as starts
/// in the app data directory, so [probeLogPullHint] works as written.
///
/// Requires:
///   - baseDir, when given, resolves to an existing directory
///
/// Ensures:
///   - the file lives directly in baseDir, which defaults to the app support
///     directory (internal storage)
///   - the file is named round-trip-probe-<yyyyMMdd-HHmmss>.jsonl
Future<FileProbeSink> openProbeFileSink(
  DateTime now, {
  Future<Directory> Function() baseDir = getApplicationSupportDirectory,
} ) async {
  final dir = await baseDir();
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

  /// Uploads only, and only when [sendMs] is null: why it could not be timed.
  final String?  sendMsNullReason;

  /// The body's total length was unknown, so "fully sent" cannot be detected.
  static const String sendNullUnknownLength = 'unknown_length';

  /// Send progress never reached the body's full length (e.g. the request failed mid-send).
  static const String sendNullNotFullySent  = 'not_fully_sent';

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
    this.sendMsNullReason,
  } );

  /// True when the request got a 2xx response and raised no error.
  bool get ok => error == null && status != null && status! >= 200 && status! < 300;

  /// One JSONL record.
  ///
  /// Ensures:
  ///   - uploads carry `total_ms_includes_transcription: true` (the endpoint
  ///     transcribes before it answers) and `send_ms`
  ///   - an upload with a null `send_ms` also carries `send_ms_null_reason`
  Map<String, dynamic> toJson() => {
    'timestamp'    : timestamp.toUtc().toIso8601String(),
    'kind'         : kind,
    if ( sampleRate != null ) 'sample_rate' : sampleRate,
    'network_type' : networkType,
    if ( bytes != null ) 'bytes' : bytes,
    'total_ms'     : totalMs,
    if ( kind == 'upload' ) 'total_ms_includes_transcription' : true,
    if ( kind == 'upload' ) 'send_ms' : sendMs,
    if ( kind == 'upload' && sendMs == null ) 'send_ms_null_reason' : sendMsNullReason ?? sendNullNotFullySent,
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

  /// True when the run was cancelled before every request was made.
  final bool                    cancelled;

  const ProbeResult( {
    required this.samples,
    required this.groups,
    required this.networkTypes,
    required this.outputPath,
    this.cancelled = false,
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
  final Future<Uint8List> Function( int sampleRate ) _clipFor;

  /// [clipFor] builds the upload clip for a sample rate; the default builds
  /// the 30 s sweep on a background isolate.
  RoundTripProbe( {
    required Dio dio,
    NetworkTypeProvider? networkType,
    Stopwatch Function()? stopwatchFactory,
    DateTime Function()? clock,
    Future<Uint8List> Function( int sampleRate )? clipFor,
  } ) : _dio          = dio,
        _networkType  = networkType      ?? connectivityNetworkType,
        _newStopwatch = stopwatchFactory ?? Stopwatch.new,
        _now          = clock            ?? DateTime.now,
        _clipFor      = clipFor          ?? ( ( rate ) => ProbeWav.generateInBackground( sampleRate: rate ) );

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
  ///   - both upload clips are built once, before any request is timed
  ///   - exactly [healthCount] health requests and
  ///     uploadRepeats × uploadSampleRates.length uploads are attempted, in
  ///     sequence, on the injected Dio — unless [cancelToken] is cancelled
  ///   - a failed request becomes a sample with its error and the run goes on
  ///   - [onProgress] is called after every sample with (done, total, sample)
  ///   - on cancel: [cancelToken] is checked between samples and handed to the
  ///     in-flight request; no further request is made, the interrupted
  ///     request's sample is discarded, a final `{"kind":"cancelled",...}`
  ///     line is written, and the result has cancelled = true
  ///   - returns every recorded sample, the summary, and the network types seen
  Future<ProbeResult> run(
    ProbeSink sink, {
    void Function( int done, int total, ProbeSample sample )? onProgress,
    CancelToken? cancelToken,
  } ) async {
    final samples = <ProbeSample>[];
    final total   = totalRequests;
    bool isCancelled() => cancelToken?.isCancelled ?? false;

    Future<void> record( ProbeSample s ) async {
      samples.add( s );
      await sink.writeLine( jsonEncode( s.toJson() ) );
      onProgress?.call( samples.length, total, s );
    }

    // Build the ~2.6 MB and ~1 MB clips up front, off the UI isolate, so
    // neither the generation nor its jank lands inside a timed request.
    final clips = <int, Uint8List>{};
    for ( final rate in uploadSampleRates ) {
      if ( isCancelled() ) break;
      clips[ rate ] = await _clipFor( rate );
    }

    final steps = <Future<ProbeSample> Function()>[
      for ( var i = 0; i < healthCount; i++ ) () => _health( cancelToken ),
      for ( var i = 0; i < uploadRepeats; i++ )
        for ( final rate in uploadSampleRates ) () => _upload( rate, clips[ rate ]!, cancelToken ),
    ];

    var cancelled = false;
    for ( final step in steps ) {
      if ( isCancelled() ) { cancelled = true; break; }
      final sample = await step();
      if ( isCancelled() ) { cancelled = true; break; }   // interrupted mid-request: not a real timing
      await record( sample );
    }

    if ( cancelled ) {
      await sink.writeLine( jsonEncode( {
        'timestamp' : _now().toUtc().toIso8601String(),
        'kind'      : 'cancelled',
        'completed' : samples.length,
        'total'     : total,
        'reason'    : cancelToken?.cancelError?.error?.toString(),
      } ) );
    }

    return ProbeResult(
      samples      : samples,
      groups       : summarise( samples ),
      networkTypes : samples.map( ( s ) => s.networkType ).toSet(),
      outputPath   : sink.path,
      cancelled    : cancelled,
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

  Future<ProbeSample> _health( CancelToken? cancelToken ) async {
    final network   = await _safeNetworkType();
    final timestamp = _now();
    final sw        = _newStopwatch()..start();
    int?    status;
    String? error;
    try {
      final res = await _dio.get<dynamic>( healthPath, cancelToken: cancelToken );
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

  Future<ProbeSample> _upload( int sampleRate, Uint8List clip, CancelToken? cancelToken ) async {
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
    var     lengthUnknown = false;
    int?    status;
    String? error;
    try {
      final res = await _dio.post<dynamic>(
        AsrService.endpointPath,
        data           : form,
        cancelToken    : cancelToken,
        options        : Options(
          // Same budgets as AsrService: cellular upload + Whisper inference.
          sendTimeout    : const Duration( seconds: 60 ),
          receiveTimeout : const Duration( seconds: 120 ),
        ),
        onSendProgress : ( sent, totalBytes ) {
          if ( totalBytes <= 0 ) lengthUnknown = true;
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
      timestamp        : timestamp,
      kind             : 'upload',
      sampleRate       : sampleRate,
      networkType      : network,
      totalMs          : _ms( sw ),
      status           : status,
      error            : error,
      bytes            : clip.length,
      sendMs           : sendMs,
      sendMsNullReason : sendMs != null
          ? null
          : ( lengthUnknown ? ProbeSample.sendNullUnknownLength : ProbeSample.sendNullNotFullySent ),
    );
  }

  static String _describe( DioException e ) =>
      e.message == null ? e.type.name : '${e.type.name}: ${e.message}';
}
