import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Typed failure for every ASR error path (S4 §4.1): denied mic permission,
/// recorder failure, HTTP non-200, network failure, EMPTY transcript
/// (AC-S4.2 extended — an empty 200 must surface as an error, never as a
/// blank review field; note Whisper can also HALLUCINATE on silence and
/// return non-empty junk, per the Phase-0 capture
/// `test/fixtures/asr/transcribe_endpoint_contract.json`).
class AsrException implements Exception {
  final String message;
  final int?   statusCode;
  const AsrException( this.message, { this.statusCode } );
  @override
  String toString() => 'AsrException($statusCode): $message';
}

/// Push-to-talk record → upload → transcript for the focus-mode voice reply
/// (S4 §4.1). Bundles recorder lifecycle + temp-file hygiene + typed
/// [AsrException] mapping around the multipart upload — cohesion that does
/// not belong in the generic `HttpService` wrapper (F-S4-2 divergence
/// justification; the multipart mechanics themselves follow the existing
/// `http_service.dart:197-198` pattern).
///
/// Endpoint (OSQ-1, Phase-0 wire-grounded): `POST /api/upload-and-transcribe-wav`
/// — NO auth required (`speech.py:646-653`); the injected [dio] is the app's
/// SHARED auth-wired instance and its bearer is harmless. Response is a JSON
/// string literal of the transcript. The MP3 sibling endpoint queues a
/// multimodal JOB — wrong tool for chat replies (F-S4-2 trap; see the
/// deprecation note on `HttpService.uploadAndTranscribe`).
class AsrService {
  final Dio           _dio;
  final AudioRecorder _recorder;
  final Future<Directory> Function() _tempDirProvider;

  /// Debug "Keep voice recordings" (row 9b1f7701): read on every discard, so
  /// a flip in Settings applies to the next recording without a restart.
  final bool Function()                                   _keepRecordings;
  final Future<Directory> Function()                      _keptDirProvider;
  final Future<void> Function( File source, String dest ) _copyFile;
  final DateTime Function()                               _clock;
  int           _keptCount = 0;
  Future<void>? _lastKeep;

  static const String endpointPath = '/api/upload-and-transcribe-wav';

  /// OSQ-2 RATIFIED-AS-AMENDED params, mirrored from the parent GUI client
  /// (`lupin_client.py:79-81` — paInt16 / mono / 44100 Hz).
  static const RecordConfig recordConfig = RecordConfig(
    encoder     : AudioEncoder.wav,
    sampleRate  : 44100,
    numChannels : 1,
  );

  String? _activePath;

  /// AC-S2.2c — true iff a capture is in flight on THIS recorder.
  ///
  /// The state lives on the service, not on a caller, because the recorder and
  /// `_activePath` are singleton-scoped (`service_locator.dart:327`) and TWO
  /// components share the instance: focus mode's `VoiceReplyField` and Quick
  /// Ask's hold-to-talk button. A guard held by one caller is structurally
  /// blind to the other — `QuickAskBloc` knowing what IT started says nothing
  /// about a reply already recording on the same recorder.
  bool get isCapturing => _activePath != null;

  AsrService( {
    required Dio           dio,
    required AudioRecorder recorder,
    Future<Directory> Function()? tempDirProvider,
    bool Function()?              keepRecordings,
    Future<Directory> Function()? keptDirProvider,
    Future<void> Function( File source, String dest )? copyFile,
    DateTime Function()?          clock,
  } ) : _dio             = dio,
        _recorder        = recorder,
        _tempDirProvider = tempDirProvider ?? getTemporaryDirectory,
        _keepRecordings  = keepRecordings  ?? _never,
        _keptDirProvider = keptDirProvider ?? keptRecordingsDirectory,
        _copyFile        = copyFile        ?? _copy,
        _clock           = clock           ?? DateTime.now;

  static bool _never() => false;
  static Future<void> _copy( File source, String dest ) => source.copy( dest );

  /// Where kept recordings go: `<external files dir>/recordings`, pullable
  /// from `/sdcard/Android/data/<applicationId>/files/recordings/`; the app
  /// documents directory when there is no external one.
  ///
  /// Ensures:
  ///   - returns the directory path; does NOT create it
  static Future<Directory> keptRecordingsDirectory() async {
    Directory? base;
    try {
      base = await getExternalStorageDirectory();
    } catch ( _ ) {
      // Not supported on this platform (e.g. iOS) — fall through.
      base = null;
    }
    base ??= await getApplicationDocumentsDirectory();
    return Directory( '${base.path}/recordings' );
  }

  /// `rec-<yyyyMMdd-HHmmssSSS>Z-<n>.wav`, stamped in UTC.
  ///
  /// [n] restarts at 1 on every app launch, so it is NOT what makes the name
  /// unique: two runs that record in the same second used to produce the same
  /// name, and the second run's copy silently overwrote the first run's. The
  /// milliseconds carry the uniqueness; UTC keeps the names sortable across a
  /// DST change, where local time repeats a whole hour.
  ///
  /// Requires:
  ///   - n is positive
  ///
  /// Ensures:
  ///   - the name is fixed-width and zero-padded, so a plain sort is
  ///     chronological
  ///   - two instants a millisecond apart never yield the same name, whatever
  ///     [n] is
  @visibleForTesting
  static String keptFileNameFor( DateTime t, int n ) {
    final u = t.toUtc();
    String two( int v ) => v.toString().padLeft( 2, '0' );
    final stamp = '${u.year.toString().padLeft( 4, '0' )}${two( u.month )}${two( u.day )}'
                  '-${two( u.hour )}${two( u.minute )}${two( u.second )}'
                  '${u.millisecond.toString().padLeft( 3, '0' )}Z';
    return 'rec-$stamp-$n.wav';
  }

  /// The most recent keep-then-delete, so a test can await it. Null until a
  /// discard ran with keeping ON.
  @visibleForTesting
  Future<void>? get lastKeep => _lastKeep;

  /// Begin a push-to-talk capture to a temp WAV under the app cache dir.
  ///
  /// Raises:
  ///   - [AsrException] if mic permission is denied or the recorder fails
  Future<void> startRecording() async {
    // AC-S2.2c — refuse a SECOND concurrent capture, and say so. Thrown BEFORE
    // the recorder is touched: `_activePath` is written unconditionally at the
    // end of this method, so a second start would overwrite the first
    // capture's path and orphan it, and whichever stop fired first would
    // consume the other's file. Reachable by ordinary navigation — start a
    // voice reply in focus mode, open the drawer, hold the Quick Ask button.
    //
    // This is a GUARD, not a feature: concurrent capture stays out of scope.
    // It makes the collision impossible and legible instead of silent and
    // lossy.
    if ( isCapturing ) {
      throw const AsrException( 'A recording is already in progress' );
    }
    if ( !await _recorder.hasPermission() ) {
      throw const AsrException( 'Microphone permission denied' );
    }
    final dir  = await _tempDirProvider();
    final path = '${dir.path}/asr-reply-${DateTime.now().microsecondsSinceEpoch}.wav';
    try {
      await _recorder.start( recordConfig, path: path );
    } catch ( e ) {
      // F-S4-IMPL-1 (optional half): a start()-throw can leave a zero-byte
      // orphan at the target path on some platforms — best-effort cleanup.
      _deleteQuietly( File( path ) );
      throw AsrException( 'Recorder failed to start: $e' );
    }
    _activePath = path;
  }

  /// Recordings handed out by [stopToFile] and not yet discarded.
  ///
  /// 🔴 A SET, not one path (plan rev 14 §3.2 SB2/CB3, amended): two spoken
  /// asks can be unresolved at once (§3.3 CC2), so a single field would let
  /// the second stop overwrite the first — orphaning it — and the first
  /// stream's disposal would then delete the second recording mid-upload.
  final Set<String> _pendingUploadPaths = {};

  /// Stop the capture and hand back the recording's path, WITHOUT uploading.
  ///
  /// The service keeps ownership of the file: the caller uploads it however
  /// it likes and then MUST call [discardPendingUpload] with the returned
  /// path. `_activePath` is cleared here, so [cancelRecording] can no longer
  /// reach this file.
  ///
  /// Raises:
  ///   - [AsrException] if the recorder fails to stop or produced no file
  Future<String> stopToFile() async {
    String? stopped;
    try {
      stopped = await _recorder.stop();
    } catch ( e ) {
      // F-S4-IMPL-1: recorder failure surfaces as the §4.1-promised typed
      // exception, never a raw platform error. Clean up the active capture.
      final orphan = _activePath;
      _activePath = null;
      if ( orphan != null ) _deleteQuietly( File( orphan ) );
      throw AsrException( 'Recorder failed to stop: $e' );
    }
    final filePath = stopped ?? _activePath;
    _activePath = null;
    if ( filePath == null ) {
      throw const AsrException( 'Recorder produced no file' );
    }
    _pendingUploadPaths.add( filePath );
    return filePath;
  }

  /// Delete a recording [stopToFile] handed out, once its upload is over —
  /// on every outcome, including a stream that was never listened to.
  ///
  /// Only paths this service handed out are deleted; any other path, or a
  /// second call for the same one, does nothing.
  ///
  /// With "Keep voice recordings" ON, a copy goes to [keptRecordingsDirectory]
  /// first and the delete follows once the copy settles. A copy failure is
  /// logged and swallowed: the original is deleted regardless. OFF is the
  /// plain synchronous delete, with no extra I/O.
  void discardPendingUpload( String path ) {
    if ( !_pendingUploadPaths.remove( path ) ) return;
    if ( !_keepRecordings() ) {
      _deleteQuietly( File( path ) );
      return;
    }
    _lastKeep = _keepThenDelete( File( path ) );
  }

  Future<void> _keepThenDelete( File source ) async {
    try {
      final dir = await _keptDirProvider();
      await dir.create( recursive: true );
      _keptCount++;
      final dest = '${dir.path}/${keptFileNameFor( _clock(), _keptCount )}';
      await _copyFile( source, dest );
      debugPrint( 'AsrService: kept recording at $dest' );
    } catch ( e ) {
      debugPrint( 'AsrService: could not keep recording ${source.path}: $e' );
    } finally {
      _deleteQuietly( source );
    }
  }

  /// Stop the capture, upload the WAV, return the transcript. The temp file
  /// is deleted afterwards — success or failure.
  ///
  /// Raises:
  ///   - [AsrException] for recorder-no-file, HTTP/network failure, an
  ///     unexpected response shape, or an EMPTY transcript
  Future<String> stopAndTranscribe() async {
    final filePath = await stopToFile();

    final file = File( filePath );
    try {
      if ( !file.existsSync() ) {
        throw const AsrException( 'Recording file missing before upload' );
      }
      final form = FormData.fromMap( {
        'file': await MultipartFile.fromFile( filePath, filename: 'voice-reply.wav' ),
      } );
      final res = await _dio.post<dynamic>(
        endpointPath,
        data    : form,
        options : Options(
          // Generous budgets — cellular upload + Whisper inference.
          sendTimeout    : const Duration( seconds: 60 ),
          receiveTimeout : const Duration( seconds: 120 ),
        ),
      );

      final data = res.data;
      if ( data is! String ) {
        throw AsrException( 'Unexpected transcription response shape: ${data.runtimeType}' );
      }
      final transcript = data.trim();
      if ( transcript.isEmpty ) {
        throw const AsrException( 'Transcription came back empty' );
      }
      return transcript;
    } on DioException catch ( e ) {
      throw AsrException(
        'Transcription upload failed: ${e.message ?? e.type.name}',
        statusCode: e.response?.statusCode,
      );
    } finally {
      discardPendingUpload( filePath );
    }
  }

  /// Discard the in-progress capture; no upload fires. The temp file is
  /// removed (the recorder's own cancel() deletes it too — this is the belt).
  Future<void> cancelRecording() async {
    final path = _activePath;
    _activePath = null;
    await _recorder.cancel();
    if ( path != null ) _deleteQuietly( File( path ) );
  }

  void _deleteQuietly( File f ) {
    try {
      if ( f.existsSync() ) f.deleteSync();
    } on FileSystemException {
      // Temp-file cleanup is best-effort; the OS cache dir reaps leftovers.
    }
  }
}
