import 'dart:async';

import '../permissions/mic_permission.dart' as mic;
import 'asr_service.dart';

/// The one record → transcribe → review core, shared by every voice composer
/// (row 0b40272e).
///
/// Rick asked whether focus mode runs a SECOND recording implementation, and
/// whether to yank it and reuse Quick Ask's. The answer was in between: both
/// already drive the same [AsrService] with the same two calls, and Quick
/// Ask's own cancel guard is a copy of the focus widget's
/// (`quick_ask_bloc.dart:155` says so). What existed twice was the WRAPPER —
/// permission request, cancel epoch, error text, and whether a blank
/// transcript is caught — and the two copies had drifted: only Quick Ask told
/// the user when nothing was heard.
///
/// So the wrapper lives here once, and both composers call it. The pieces that
/// are genuinely Quick Ask's own — send-immediately's spoken stream, job
/// tracking, retries — stay in its bloc.
class VoiceCaptureSession {
  final AsrService _asr;

  /// Test seam for the runtime permission request. Defaults to the one shared
  /// requester; the composers pass their own only in tests.
  final Future<bool> Function() _requestPermission;

  VoiceCaptureSession( {
    required AsrService asr,
    Future<bool> Function()? requestPermission,
  } ) : _asr = asr,
        _requestPermission = requestPermission ?? mic.requestMicPermission;

  /// Cancel guard. A cancel bumps it, so a result from an earlier attempt is
  /// dropped instead of resurrecting a cancelled review. Callers that key
  /// their own bookkeeping by attempt (Quick Ask's spoken streams) read it.
  int _epoch = 0;
  int get epoch => _epoch;

  /// True while the recorder is running, straight from the service.
  bool get isCapturing => _asr.isCapturing;

  /// The message shown when the microphone was refused. One string, so both
  /// composers say the same thing.
  static const String permissionDeniedMessage =
      'Microphone permission needed — enable it in system settings.';

  /// The message shown when a capture transcribed to nothing. Quick Ask had
  /// this and the focus composer did not, which is how a silent capture used
  /// to open an empty review box with a live Send button behind it.
  static const String nothingHeardMessage =
      'Did not catch anything — tap the microphone and try again.';

  /// Ask for the microphone, then start recording.
  ///
  /// Ensures:
  ///   - [VoiceCaptureStart.started] is true only when the recorder is running
  ///   - [VoiceCaptureStart.errorMessage] carries the refusal or the
  ///     recorder's message, and nothing is recording
  ///   - [VoiceCaptureStart.isStale] is true when a cancel landed while the
  ///     permission request was open: nothing was started and the caller must
  ///     change nothing
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

  /// Stop, upload, and hand back what the server heard.
  ///
  /// Ensures:
  ///   - [VoiceCapture.transcript] carries non-blank speech
  ///   - [VoiceCapture.errorMessage] carries the recorder's or server's
  ///     message, or [nothingHeardMessage] for a blank transcript
  ///   - [VoiceCapture.isStale] is true when a cancel landed while the upload
  ///     was in flight; the caller must then change nothing
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

  /// Abandon the attempt: bump the epoch so an in-flight result is dropped,
  /// and discard the recording if one is still running.
  ///
  /// `cancelRecording()` is deliberately NOT awaited — the UI returns to idle
  /// on the same frame as the tap, and the recorder's teardown is nothing the
  /// user waits for.
  void cancel() {
    _epoch++;
    unawaited( _asr.cancelRecording() );
  }

  /// [cancel], but awaiting the recorder's teardown — for a caller that
  /// reports `isCapturing` in the same breath (Quick Ask emits it on the state
  /// it returns, so a fire-and-forget teardown would report the old value).
  Future<void> cancelAwaiting() async {
    _epoch++;
    await _asr.cancelRecording();
  }

  /// Bump the epoch WITHOUT touching the recorder: everything in flight
  /// becomes stale, but nothing is recording to stop. This is what throwing a
  /// held draft away means.
  void invalidate() => _epoch++;
}

/// The outcome of one [VoiceCaptureSession.stopAndTranscribe].
class VoiceCapture {
  /// What the server heard. Non-null and non-blank only on success.
  final String? transcript;

  /// Why there is no transcript. Null on success.
  final String? errorMessage;

  /// A cancel overtook this attempt: not a success and not an error, and the
  /// caller must leave its state exactly as the cancel left it.
  final bool isStale;

  const VoiceCapture.heard( String this.transcript )
      : errorMessage = null, isStale = false;

  const VoiceCapture.failed( String this.errorMessage )
      : transcript = null, isStale = false;

  const VoiceCapture.stale()
      : transcript = null, errorMessage = null, isStale = true;

  bool get wasHeard => transcript != null;
}

/// The outcome of one [VoiceCaptureSession.start].
class VoiceCaptureStart {
  /// Why nothing is recording. Null when the recorder started.
  final String? errorMessage;

  /// A cancel overtook the attempt — neither started nor an error.
  final bool isStale;

  const VoiceCaptureStart.started()  : errorMessage = null, isStale = false;
  const VoiceCaptureStart.refused( String this.errorMessage ) : isStale = false;
  const VoiceCaptureStart.stale()    : errorMessage = null, isStale = true;

  bool get started => errorMessage == null && !isStale;
}
