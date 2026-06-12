import 'dart:io';

import 'package:dio/dio.dart';
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

  static const String endpointPath = '/api/upload-and-transcribe-wav';

  /// OSQ-2 RATIFIED-AS-AMENDED params, mirrored from the parent GUI client
  /// (`lupin_client.py:79-81` — paInt16 / mono / 44100 Hz).
  static const RecordConfig recordConfig = RecordConfig(
    encoder     : AudioEncoder.wav,
    sampleRate  : 44100,
    numChannels : 1,
  );

  String? _activePath;

  AsrService( {
    required Dio           dio,
    required AudioRecorder recorder,
    Future<Directory> Function()? tempDirProvider,
  } ) : _dio             = dio,
        _recorder        = recorder,
        _tempDirProvider = tempDirProvider ?? getTemporaryDirectory;

  /// Begin a push-to-talk capture to a temp WAV under the app cache dir.
  ///
  /// Raises:
  ///   - [AsrException] if mic permission is denied or the recorder fails
  Future<void> startRecording() async {
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

  /// Stop the capture, upload the WAV, return the transcript. The temp file
  /// is deleted afterwards — success or failure.
  ///
  /// Raises:
  ///   - [AsrException] for recorder-no-file, HTTP/network failure, an
  ///     unexpected response shape, or an EMPTY transcript
  Future<String> stopAndTranscribe() async {
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
      _deleteQuietly( file );
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
