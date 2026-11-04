import 'dart:async';

import '../permissions/mic_permission.dart' as mic;
import 'asr_service.dart';

/// One record, transcribe and review core, shared by every voice composer.
///
/// Focus mode and Quick Ask drive the same [AsrService] with the same two calls.
/// The wrapper (permission request, cancel epoch, error text, blank-transcript check) lives here once.
/// What is Quick Ask's own, such as send-immediately's spoken stream, job tracking and retries, stays in its bloc.
/// Design: src/docs/decisions/README.md (R-ASR-shared-capture)
class VoiceCaptureSession {
  final AsrService _asr;

  /// Test seam for the runtime permission request.
  ///
  /// Defaults to the one shared requester; the composers pass their own only in tests.
  final Future<bool> Function() _requestPermission;

  /// Creates a session on [asr]; [requestPermission] is a test seam.
  VoiceCaptureSession( {
    required AsrService asr,
    Future<bool> Function()? requestPermission,
  } ) : _asr = asr,
        _requestPermission = requestPermission ?? mic.requestMicPermission;

  /// Cancel guard. A cancel bumps it, so a result from an earlier attempt is dropped.
  ///
  /// Otherwise it would resurrect a cancelled review. Callers that key their own bookkeeping by
  /// attempt, such as Quick Ask's spoken streams, read it.
  int _epoch = 0;
  /// Number of cancels and invalidations so far.
  int get epoch => _epoch;

  /// True while the recorder is running, straight from the service.
  bool get isCapturing => _asr.isCapturing;

  /// The message shown when the microphone was refused.
  ///
  /// One string, so both composers say the same thing.
  static const String permissionDeniedMessage =
      'Microphone permission needed — enable it in system settings.';

  /// The message shown when a capture transcribed to nothing.
  ///
  /// Without it a silent capture opens an empty review box with a live Send button behind it.
  static const String nothingHeardMessage =
      'Did not catch anything — tap the microphone and try again.';

  /// Asks for the microphone, then starts recording.
  ///
  /// Ensures:
  ///   - [VoiceCaptureStart.started] is true only when the recorder is running
  ///   - [VoiceCaptureStart.errorMessage] carries the refusal or the recorder's message, and nothing is recording
  ///   - [VoiceCaptureStart.isStale] is true when a cancel landed while the permission request was open:
  ///     nothing was started and the caller must change nothing
  Future<VoiceCaptureStart> start() async {
    final attempt = ++_epoch;
    final granted = await _requestPermission();
    if ( attempt != _epoch ) return const VoiceCaptureStart.stale();
    if ( !granted ) return const VoiceCaptureStart.refused( permissionDeniedMessage );

    try {
      await _asr.startRecording();
      if ( attempt != _epoch ) return const VoiceCaptureStart.stale();
      return const VoiceCaptureStart.started();
    } on AsrException catch ( e ) {
      if ( attempt != _epoch ) return const VoiceCaptureStart.stale();
      return VoiceCaptureStart.refused( e.message );
    }
  }

  /// Stops, uploads and returns what the server heard.
  ///
  /// Ensures:
  ///   - [VoiceCapture.transcript] carries non-blank speech
  ///   - [VoiceCapture.errorMessage] carries the recorder's or server's message, or [nothingHeardMessage]
  ///     for a blank transcript
  ///   - [VoiceCapture.isStale] is true when a cancel landed while the upload was in flight; the caller
  ///     must then change nothing
  Future<VoiceCapture> stopAndTranscribe() async {
    final attempt = _epoch;
    try {
      final transcript = await _asr.stopAndTranscribe();
      if ( attempt != _epoch ) return const VoiceCapture.stale();
      if ( transcript.trim().isEmpty ) {
        return const VoiceCapture.failed( nothingHeardMessage );
      }
      return VoiceCapture.heard( transcript );
    } on AsrException catch ( e ) {
      if ( attempt != _epoch ) return const VoiceCapture.stale();
      return VoiceCapture.failed( e.message );
    }
  }

  /// Abandons the attempt: drops any in-flight result and discards the recording.
  ///
  /// Bumps the epoch, so the in-flight result is stale.
  ///
  /// `cancelRecording()` is not awaited. The UI returns to idle on the same frame as the tap, and the
  /// recorder's teardown is nothing the user waits for.
  void cancel() {
    _epoch++;
    unawaited( _asr.cancelRecording() );
  }

  /// [cancel] that awaits the recorder's teardown.
  ///
  /// For a caller that reports `isCapturing` at once.
  ///
  /// Quick Ask emits it on the state it returns, so a fire-and-forget teardown would report the old value.
  Future<void> cancelAwaiting() async {
    _epoch++;
    await _asr.cancelRecording();
  }

  /// Bumps the epoch without touching the recorder.
  ///
  /// Everything in flight becomes stale, and nothing is recording to stop. This is what throwing a held
  /// draft away means.
  void invalidate() => _epoch++;
}

/// The outcome of one [VoiceCaptureSession.stopAndTranscribe].
class VoiceCapture {
  /// What the server heard. Non-null and non-blank only on success.
  final String? transcript;

  /// Why there is no transcript. Null on success.
  final String? errorMessage;

  /// A cancel overtook this attempt: not a success and not an error.
  ///
  /// The caller must leave its state exactly as the cancel left it.
  final bool isStale;

  /// The server heard [transcript].
  const VoiceCapture.heard( String this.transcript )
      : errorMessage = null, isStale = false;

  /// The capture failed with [errorMessage].
  const VoiceCapture.failed( String this.errorMessage )
      : transcript = null, isStale = false;

  /// A cancel overtook the attempt.
  const VoiceCapture.stale()
      : transcript = null, errorMessage = null, isStale = true;

  /// True when there is a transcript.
  bool get wasHeard => transcript != null;
}

/// The outcome of one [VoiceCaptureSession.start].
class VoiceCaptureStart {
  /// Why nothing is recording. Null when the recorder started.
  final String? errorMessage;

  /// A cancel overtook the attempt: neither started nor an error.
  final bool isStale;

  /// The recorder started.
  const VoiceCaptureStart.started()  : errorMessage = null, isStale = false;
  /// The recorder did not start, for the reason in [errorMessage].
  const VoiceCaptureStart.refused( String this.errorMessage ) : isStale = false;
  /// A cancel overtook the attempt.
  const VoiceCaptureStart.stale()    : errorMessage = null, isStale = true;

  /// True when the recorder started.
  bool get started => errorMessage == null && !isStale;
}
