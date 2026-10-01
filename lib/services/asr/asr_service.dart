import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

/// Typed failure for every ASR error path.
///
/// The paths are a denied microphone permission, a recorder failure, an HTTP non-200, a network failure
/// and an empty transcript. An empty 200 must surface as an error, never as a blank review field.
/// Whisper can also hallucinate non-empty junk on silence, as captured in
/// `test/fixtures/asr/transcribe_endpoint_contract.json`.
class AsrException implements Exception {
  /// What failed, in words for the user or the log.
  final String message;
  /// HTTP status when the failure was a response, else null.
  final int?   statusCode;
  /// Creates an exception with [message] and an optional [statusCode].
  const AsrException( this.message, { this.statusCode } );
  @override
  String toString() => 'AsrException($statusCode): $message';
}

/// Push-to-talk record, upload and transcript for the focus-mode voice reply.
///
/// Bundles the recorder lifecycle, temp-file cleanup and typed [AsrException] mapping around the
/// multipart upload. That cohesion does not belong in the generic `HttpService` wrapper; the multipart
/// mechanics follow the pattern in `http_service.dart`.
///
/// Endpoint: `POST /api/v2/transcribe` (lupin `v2_ask.py`). It needs the bearer the injected [dio]
/// already carries and answers `{ transcription, trace: { stt_ms, upload_bytes } }`. A 422 means an empty
/// upload or no recognisable speech; a 503 carries Retry-After because the GPU is busy.
/// The MP3 sibling endpoint queues a multimodal job, the wrong tool for chat replies; see the
/// deprecation note on `HttpService.uploadAndTranscribe`.
/// Design: src/docs/decisions/README.md (R-ASR-v2-door)
class AsrService {
  final Dio           _dio;
  final AudioRecorder _recorder;
  final Future<Directory> Function() _tempDirProvider;

  /// Debug "Keep voice recordings" setting, read on every discard.
  ///
  /// A change in Settings therefore applies to the next recording without a restart.
  final bool Function()                                   _keepRecordings;
  final Future<Directory> Function()                      _keptDirProvider;
  final Future<void> Function( File source, String dest ) _copyFile;
  final DateTime Function()                               _clock;
  int           _keptCount = 0;
  Future<void>? _lastKeep;

  /// Path of the transcription endpoint.
  static const String endpointPath = '/api/v2/transcribe';

  /// The capture format: Ogg/Opus, mono, 32 kbps.
  ///
  /// Opus at 32 kbps passed an accuracy check. Nine real phone recordings sent as WAV and as Opus differed
  /// by one word in 176 (0.57% pooled, limit 5%), with files about 23x smaller. The rate is 48 kHz because
  /// Android's Opus encoder takes only 8, 12, 16, 24 or 48 kHz and silently rounds anything else.
  /// The server's upload doors keep the file's extension, so an `.ogg` name is what tells them.
  /// Design: src/docs/decisions/README.md (R-ASR-opus-32k)
  static const RecordConfig recordConfig = RecordConfig(
    encoder     : AudioEncoder.opus,
    sampleRate  : 48000,
    numChannels : 1,
    bitRate     : 32000,
  );

  /// Recording settings for a device without an Opus encoder: the WAV the app used before Opus.
  ///
  /// It is 16-bit PCM, mono, 44100 Hz, mirroring `lupin_client.py` (paInt16), and is known to transcribe.
  /// Android gained its Opus encoder and Ogg writer in API 29 and minSdk is 24, so this path is real.
  static const RecordConfig wavFallbackConfig = RecordConfig(
    encoder     : AudioEncoder.wav,
    sampleRate  : 44100,
    numChannels : 1,
  );

  /// File extension for [encoder]'s format: `ogg` for Opus, `wav` otherwise.
  static String fileExtensionFor( AudioEncoder encoder ) =>
      encoder == AudioEncoder.opus ? 'ogg' : 'wav';

  static String _extensionOf( String path ) {
    final dot = path.lastIndexOf( '.' );
    return dot < 0 ? 'wav' : path.substring( dot + 1 );
  }

  static bool _isWav( String path ) => _extensionOf( path ) == 'wav';

  /// Answers whether this device can record Opus; asked once, then cached.
  final Future<bool> Function() _opusSupported;
  bool? _opusAvailable;

  String? _activePath;

  /// Wall-clock start of the active capture.
  ///
  /// The capture log compares the file size with how long the microphone was open. A capture held for
  /// 3.0 s that yields 2.6 s of audio has dropped 0.4 s, and no single number shows that; the pair does.
  DateTime? _captureStartedAt;

  /// True while a capture is in flight on this recorder.
  ///
  /// The state lives on the service, not on a caller. The recorder and `_activePath` are singleton-scoped
  /// (`service_locator.dart`), and two components share the instance: focus mode's `VoiceReplyField` and
  /// Quick Ask's hold-to-talk button. A guard held by one caller cannot see a capture the other started.
  bool get isCapturing => _activePath != null;

  /// Told when a capture starts (true) and ends (false), whether stopped, failed or cancelled.
  ///
  /// Production wires it to `TtsOrchestrator.setCaptureHold`, so no notification is spoken over a
  /// recording. Null means nobody listens.
  final void Function( bool capturing )? _onCapturingChanged;

  void _setActivePath( String? path ) {
    final was   = _activePath != null;
    _activePath = path;
    final now   = path != null;
    if ( was != now ) _onCapturingChanged?.call( now );
  }

  /// Creates the service; every parameter except [dio] and [recorder] is a test seam.
  AsrService( {
    required Dio           dio,
    required AudioRecorder recorder,
    Future<Directory> Function()? tempDirProvider,
    bool Function()?              keepRecordings,
    Future<Directory> Function()? keptDirProvider,
    Future<void> Function( File source, String dest )? copyFile,
    DateTime Function()?          clock,
    Future<bool> Function()?      opusSupported,
    void Function( bool capturing )? onCapturingChanged,
  } ) : _dio             = dio,
        _onCapturingChanged = onCapturingChanged,
        _recorder        = recorder,
        _tempDirProvider = tempDirProvider ?? getTemporaryDirectory,
        _keepRecordings  = keepRecordings  ?? _never,
        _keptDirProvider = keptDirProvider ?? keptRecordingsDirectory,
        _copyFile        = copyFile        ?? _copy,
        _clock           = clock           ?? DateTime.now,
        _opusSupported   = opusSupported   ??
            ( () => recorder.isEncoderSupported( AudioEncoder.opus ) );

  static bool _never() => false;
  static Future<void> _copy( File source, String dest ) => source.copy( dest );

  // Capture diagnostics.
  //
  // The client logs how much audio it recorded, because the server cannot tell: it sees a valid WAV and
  // a plausible transcript either way, and deletes the upload before anyone can measure it. The log shows:
  //  - size at stop against how long the mic was open: a short file means the recorder lost audio,
  //    a full-length file means it did not
  //  - size again after a settle delay: growth means the encoder was still writing when the upload began
  //  - an exact-zero run after live signal: the input stopped delivering
  //  - the transcript paired with the seconds that produced it
  //
  // Findings so far: the recorder lost no audio. Truncation came from the input, an emulator mic that
  // injected mostly noise and then dropped to exact zeros. On noisy audio the server's Whisper decoding
  // can also stop at the first pause. Waiting before stop() does not help.

  /// PCM byte rate implied by [wavFallbackConfig]: 44100 Hz, 1 channel, 16-bit.
  ///
  /// Only a WAV's size says how long it is; an Opus file's size does not.
  static const int _bytesPerSecond = 44100 * 1 * 2;

  /// Canonical WAV header size for the 16-bit PCM the recorder writes.
  static const int _wavHeaderBytes = 44;

  /// How long to wait before the second size read.
  ///
  /// Long enough for a lagging encoder flush to land, short enough to sit inside the upload latency
  /// already paid.
  static const Duration _settleProbeDelay = Duration( milliseconds: 250 );

  /// Shortfall between microphone-open time and recorded audio that counts as a dropped tail.
  ///
  /// Below it, the gap is ordinary device open and close overhead; above it, words are going missing.
  static const double _droppedTailThresholdSeconds = 0.2;

  /// A sample louder than this counts as live input.
  ///
  /// Real microphone noise never sits at exactly zero, so the bar only has to clear rounding.
  static const int _liveSampleFloor = 64;

  /// Exact-zero run that counts as a dropout when it reaches the end of the capture.
  ///
  /// Short, because a dead input rarely comes back before the stop.
  static const double _dropoutTailSeconds = 0.10;

  /// Exact-zero run that counts as a dropout in mid-capture.
  ///
  /// Longer, so a codec or device glitch of a frame or two is not reported.
  static const double _dropoutMidSeconds = 0.25;

  /// The 16-bit little-endian PCM samples of a WAV file, header excluded.
  ///
  /// Walks the WAV chunks to find `data` instead of assuming a 44-byte header, because some encoders
  /// insert extra chunks before it.
  ///
  /// Requires:
  ///   - bytes is a WAV file holding 16-bit PCM
  ///
  /// Ensures:
  ///   - returns the samples of the `data` chunk, clamped to the bytes present
  ///   - returns an empty list when there is no `data` chunk
  @visibleForTesting
  static Int16List pcmFromWav( Uint8List bytes ) {
    final view = ByteData.sublistView( bytes );
    var offset = 12;
    while ( offset + 8 <= bytes.length ) {
      final id   = String.fromCharCodes( bytes.sublist( offset, offset + 4 ) );
      final size = view.getUint32( offset + 4, Endian.little );
      final body = offset + 8;
      if ( id == 'data' ) {
        final end   = ( body + size ).clamp( body, bytes.length );
        final count = ( end - body ) ~/ 2;
        final out   = Int16List( count );
        for ( var i = 0; i < count; i++ ) {
          out[ i ] = view.getInt16( body + i * 2, Endian.little );
        }
        return out;
      }
      offset = body + size + ( size.isOdd ? 1 : 0 );
    }
    return Int16List( 0 );
  }

  /// Where the audio input stopped delivering, if it did.
  ///
  /// The signature, measured on two emulator captures, is live signal that jumps mid-waveform to exact
  /// zeros (-7337 to 0, 1273 to 0) and stays there. The recorder keeps writing. A voice fading out never
  /// lands on exact zeros for tens of milliseconds, and neither does a quiet room.
  ///
  /// Requires:
  ///   - sampleRate is positive
  ///
  /// Ensures:
  ///   - returns null when no sample is live; a silent mic is a different fault, already reported as
  ///     header-only or empty
  ///   - otherwise returns the first run of exact zeros after live signal that is at least
  ///     [_dropoutMidSeconds] long, or that reaches the end and is at least [_dropoutTailSeconds] long
  ///   - returns null when no run qualifies
  @visibleForTesting
  static ( { double startSeconds, double lengthSeconds } )? findDropout( Int16List pcm, int sampleRate ) {
    var live = -1;
    for ( var i = 0; i < pcm.length; i++ ) {
      if ( pcm[ i ].abs() > _liveSampleFloor ) { live = i; break; }
    }
    if ( live < 0 ) return null;

    var runStart = -1;
    for ( var i = live; i <= pcm.length; i++ ) {
      final atEnd = i == pcm.length;
      if ( !atEnd && pcm[ i ] == 0 ) {
        if ( runStart < 0 ) runStart = i;
        continue;
      }
      if ( runStart >= 0 ) {
        final length = ( i - runStart ) / sampleRate;
        final bar    = atEnd ? _dropoutTailSeconds : _dropoutMidSeconds;
        if ( length >= bar ) {
          return ( startSeconds: runStart / sampleRate, lengthSeconds: length );
        }
        runStart = -1;
      }
    }
    return null;
  }

  /// Seconds of 16-bit mono PCM that [bytes] represents, header excluded.
  ///
  /// Requires:
  ///   - bytes is non-negative
  ///
  /// Ensures:
  ///   - returns 0.0 for a file at or below the header size, never a negative
  ///   - returns bytes beyond the header divided by the PCM frame rate
  @visibleForTesting
  static double wavSeconds( int bytes ) {
    final payload = bytes - _wavHeaderBytes;
    if ( payload <= 0 ) return 0.0;
    return payload / _bytesPerSecond;
  }

  /// Logs a just-stopped recording's size, then again after [_settleProbeDelay].
  ///
  /// A late encoder flush shows up as growth. Fire-and-forget: the caller does not await the settle read,
  /// so this never delays an upload. Every failure is swallowed, because a diagnostic that can break
  /// the capture path is worse than none.
  ///
  /// Requires:
  ///   - path names a file the recorder just finished writing
  ///
  /// Ensures:
  ///   - logs one line at stop and one line after the settle delay
  ///   - the second line names the delta in bytes and flags growth when positive
  ///   - never throws, whatever the file system does
  void _logCaptureSize( String path, Duration? heldFor ) {
    int first;
    try {
      first = File( path ).lengthSync();
    } catch ( e ) {
      debugPrint( 'AsrService: capture size unreadable at stop for $path: $e' );
      return;
    }
    if ( !_isWav( path ) ) {
      // Compressed audio: its size does not give its length, and the zero-run
      // dropout scan needs raw samples. Log what is still true.
      debugPrint( 'AsrService: capture stopped — ${first}B ${_extensionOf( path )} $path' );
      if ( heldFor != null ) {
        debugPrint( 'AsrService: held ${( heldFor.inMilliseconds / 1000.0 ).toStringAsFixed( 2 )}s' );
      }
      if ( first == 0 ) {
        debugPrint( 'AsrService: ⚠️ capture is empty — no audio was written. Check microphone permission.' );
      }
      return;
    }
    final recorded = wavSeconds( first );
    debugPrint(
      'AsrService: capture stopped — ${first}B '
      '(~${recorded.toStringAsFixed( 2 )}s) $path',
    );

    // File size alone cannot show audio that never reached the file; comparing it with how long the
    // microphone was open can. In one emulator capture this line cleared the recorder: held 5.61 s,
    // recorded 5.56 s, yet the transcript was one word, so the missing speech was never in the audio
    // the device delivered.
    if ( heldFor != null ) {
      final held    = heldFor.inMilliseconds / 1000.0;
      final missing = held - recorded;
      debugPrint(
        'AsrService: held ${held.toStringAsFixed( 2 )}s, recorded '
        '${recorded.toStringAsFixed( 2 )}s',
      );
      if ( missing > _droppedTailThresholdSeconds ) {
        debugPrint(
          'AsrService: ⚠️ SHORT CAPTURE — the file holds '
          '${missing.toStringAsFixed( 2 )}s less audio than the microphone was open.',
        );
      }
    }
    if ( first <= _wavHeaderBytes ) {
      debugPrint(
        'AsrService: ⚠️ capture is header-only or empty — no audio was written. '
        'Check microphone permission and, on an emulator, that host audio input is enabled.',
      );
    }
    // Scan for an input dropout on the next event-loop turn so the upload is never held up.
    // The file is deleted once the upload finishes, so a miss here is expected and silent.
    Future( () {
      try {
        final pcm     = pcmFromWav( File( path ).readAsBytesSync() );
        final dropout = findDropout( pcm, wavFallbackConfig.sampleRate );
        if ( dropout != null ) {
          debugPrint(
            'AsrService: ⚠️ INPUT DROPOUT — audio went silent (exact zeros) at '
            '${dropout.startSeconds.toStringAsFixed( 2 )}s for '
            '${dropout.lengthSeconds.toStringAsFixed( 2 )}s; the microphone '
            'stopped delivering, not the app.',
          );
        }
      } catch ( _ ) {}
    } );
    Future.delayed( _settleProbeDelay, () {
      try {
        final second = File( path ).lengthSync();
        final delta  = second - first;
        if ( delta > 0 ) {
          debugPrint(
            'AsrService: ⚠️ FLUSH RACE — file GREW by ${delta}B '
            '(~${wavSeconds( delta ).toStringAsFixed( 2 )}s) in the '
            '${_settleProbeDelay.inMilliseconds}ms after stop() returned. '
            'Audio uploaded before this point was TRUNCATED.',
          );
        } else {
          debugPrint(
            'AsrService: capture settled — still ${second}B after '
            '${_settleProbeDelay.inMilliseconds}ms, no late flush.',
          );
        }
      } catch ( _ ) {
        // The file is normally deleted right after upload; a miss here is
        // expected and says nothing.
      }
    } );
  }

  /// The shell command that copies one kept recording off a debug build.
  static const String keptRecordingPullHint =
      'adb exec-out run-as ai.deepily.lupin_mobile cat files/recordings/<name>.ogg > <name>.ogg';

  /// Where kept recordings go: `<app support dir>/recordings`, in internal storage.
  ///
  /// On Android that is `/data/user/0/<applicationId>/files/recordings/`, not the external app folder.
  /// Since Android 11 the external folder denies `adb pull` and `run-as`. Internal storage is
  /// readable by `run-as` on a debuggable build, so [keptRecordingPullHint] works as written.
  ///
  /// Requires:
  ///   - baseDir, when given, resolves to an existing directory
  ///
  /// Ensures:
  ///   - returns `<baseDir>/recordings` without creating it
  ///   - baseDir defaults to the app support directory (internal storage)
  static Future<Directory> keptRecordingsDirectory( {
    Future<Directory> Function() baseDir = getApplicationSupportDirectory,
  } ) async {
    final base = await baseDir();
    return Directory( '${base.path}/recordings' );
  }

  /// Names a kept recording `rec-<yyyyMMdd-HHmmssSSS>Z-<n>.<extension>`, stamped in UTC.
  ///
  /// The extension is the recording's own, so a kept Opus file stays `.ogg`.
  /// [n] restarts at 1 on every app launch. The milliseconds make the name unique, not [n].
  /// UTC keeps names sortable across a DST change. Local time repeats a whole hour then.
  ///
  /// Requires:
  ///   - n is positive
  ///
  /// Ensures:
  ///   - the name is fixed-width and zero-padded, so a plain sort is chronological
  ///   - two instants a millisecond apart never yield the same name, whatever [n] is
  @visibleForTesting
  static String keptFileNameFor( DateTime t, int n, { String extension = 'wav' } ) {
    final u = t.toUtc();
    String two( int v ) => v.toString().padLeft( 2, '0' );
    final stamp = '${u.year.toString().padLeft( 4, '0' )}${two( u.month )}${two( u.day )}'
                  '-${two( u.hour )}${two( u.minute )}${two( u.second )}'
                  '${u.millisecond.toString().padLeft( 3, '0' )}Z';
    return 'rec-$stamp-$n.$extension';
  }

  /// The most recent keep-then-delete, so a test can await it.
  ///
  /// Null until a discard ran with keeping on.
  @visibleForTesting
  Future<void>? get lastKeep => _lastKeep;

  /// The format this device records in: Opus when supported, else the WAV fallback.
  ///
  /// Returns [recordConfig] or [wavFallbackConfig]. A failed check counts as "cannot", because WAV is the format known to work.
  Future<RecordConfig> _captureConfig() async {
    var ok = _opusAvailable;
    if ( ok == null ) {
      try {
        ok = await _opusSupported();
      } catch ( e ) {
        debugPrint( 'AsrService: Opus support check failed ($e) — recording WAV' );
        ok = false;
      }
      _opusAvailable = ok;
      if ( !ok ) debugPrint( 'AsrService: no Opus encoder on this device — recording WAV' );
    }
    return ok ? recordConfig : wavFallbackConfig;
  }

  /// Begins a push-to-talk capture to a temp file under the app cache dir.
  ///
  /// Records Ogg/Opus where the device supports it and WAV where it does not.
  ///
  /// Raises:
  ///   - [AsrException] if a recording is already in progress, mic permission is denied or the recorder fails
  Future<void> startRecording() async {
    // Refuse a second concurrent capture, and say so. Thrown before the recorder is touched:
    // `_activePath` is written unconditionally at the end of this method, so a second start would
    // overwrite the first capture's path and orphan it, and whichever stop fired first would consume the
    // other's file. Ordinary navigation reaches it: start a voice reply in focus mode, open the drawer,
    // hold the Quick Ask button.
    //
    // This is a guard, not a feature: concurrent capture stays out of scope. It makes the collision
    // impossible and legible instead of silent and lossy.
    if ( isCapturing ) {
      throw const AsrException( 'A recording is already in progress' );
    }
    if ( !await _recorder.hasPermission() ) {
      throw const AsrException( 'Microphone permission denied' );
    }
    final config = await _captureConfig();
    final dir    = await _tempDirProvider();
    final path   = '${dir.path}/asr-reply-${DateTime.now().microsecondsSinceEpoch}'
                   '.${fileExtensionFor( config.encoder )}';
    try {
      await _recorder.start( config, path: path );
      // Name the config in the log, so a transcript that reads wrong can be checked against the format
      // that produced it without guessing at the defaults.
      debugPrint(
        'AsrService: capture started — ${config.encoder.name} '
        '${config.sampleRate}Hz ${config.numChannels}ch ${config.bitRate}bps $path',
      );
    } catch ( e ) {
      // A start() that throws can leave a zero-byte orphan at the target path on some platforms; clean up best-effort.
      _deleteQuietly( File( path ) );
      throw AsrException( 'Recorder failed to start: $e' );
    }
    _setActivePath( path );
    _captureStartedAt = _clock();
  }

  /// Recordings handed out by [stopToFile] and not yet discarded.
  ///
  /// A set, not one path. Two spoken asks can be unresolved at once, so a single field would let the
  /// second stop overwrite the first and orphan it. The first stream's disposal would then delete the
  /// second recording mid-upload.
  final Set<String> _pendingUploadPaths = {};

  /// Stops the capture and returns the recording's path without uploading.
  ///
  /// The service keeps ownership of the file: the caller uploads it however it likes and then must call
  /// [discardPendingUpload] with the returned path. `_activePath` is cleared here, so [cancelRecording]
  /// can no longer reach this file.
  ///
  /// Raises:
  ///   - [AsrException] if the recorder fails to stop or produced no file
  Future<String> stopToFile() async {
    String? stopped;
    try {
      stopped = await _recorder.stop();
    } catch ( e ) {
      // Recorder failure surfaces as a typed [AsrException], never a raw platform error. Clean up the active capture.
      final orphan = _activePath;
      _setActivePath( null );
      _captureStartedAt = null;
      if ( orphan != null ) _deleteQuietly( File( orphan ) );
      throw AsrException( 'Recorder failed to stop: $e' );
    }
    final filePath = stopped ?? _activePath;
    _setActivePath( null );
    if ( filePath == null ) {
      throw const AsrException( 'Recorder produced no file' );
    }
    _pendingUploadPaths.add( filePath );
    final startedAt = _captureStartedAt;
    _captureStartedAt = null;
    _logCaptureSize(
      filePath,
      startedAt == null ? null : _clock().difference( startedAt ),
    );
    return filePath;
  }

  /// Deletes a recording [stopToFile] handed out, once its upload is over, on every outcome.
  ///
  /// That includes a stream that was never listened to. Only paths this service handed out are deleted;
  /// any other path, or a second call for the same one, does nothing.
  ///
  /// With "Keep voice recordings" on, a copy goes to [keptRecordingsDirectory] first and the delete follows
  /// once the copy settles. A copy failure is logged and swallowed: the original is deleted regardless.
  /// With it off, the delete is plain, synchronous and does no extra I/O.
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
      final dest = '${dir.path}/${keptFileNameFor( _clock(), _keptCount, extension: _extensionOf( source.path ) )}';
      await _copyFile( source, dest );
      debugPrint( 'AsrService: kept recording at $dest' );
    } catch ( e ) {
      debugPrint( 'AsrService: could not keep recording ${source.path}: $e' );
    } finally {
      _deleteQuietly( source );
    }
  }

  /// Stops the capture, uploads the recording and returns the transcript.
  ///
  /// The temp file is deleted afterwards, on success or failure.
  ///
  /// Raises:
  ///   - [AsrException] for recorder-no-file, HTTP or network failure, an unexpected response shape,
  ///     or an empty transcript
  Future<String> stopAndTranscribe() async {
    final filePath = await stopToFile();

    final file = File( filePath );
    try {
      if ( !file.existsSync() ) {
        throw const AsrException( 'Recording file missing before upload' );
      }
      // The size as uploaded is the number that matters: the stop-time reading is what the recorder had
      // written, this is what Whisper actually received. A gap between them is the truncation.
      final uploadBytes = file.lengthSync();
      final extension   = _extensionOf( filePath );
      final seconds     = _isWav( filePath )
          ? '~${wavSeconds( uploadBytes ).toStringAsFixed( 2 )}s'
          : extension;
      debugPrint( 'AsrService: uploading ${uploadBytes}B ($seconds) to $endpointPath' );
      final form = FormData.fromMap( {
        'file': await MultipartFile.fromFile( filePath, filename: 'voice-reply.$extension' ),
      } );
      final res = await _dio.post<dynamic>(
        endpointPath,
        data    : form,
        options : Options(
          // Generous budgets: cellular upload plus Whisper inference.
          sendTimeout    : const Duration( seconds: 60 ),
          receiveTimeout : const Duration( seconds: 120 ),
        ),
      );

      final transcript = transcriptFrom( res.data ).trim();
      // Pairing the transcript with the seconds that produced it makes truncation legible. "What's two"
      // off 2.9 s of audio is a transcription problem; off 0.8 s it is a capture problem, and the log line
      // says which without anyone pulling the file.
      debugPrint(
        'AsrService: transcript (${transcript.length} chars) from $seconds: [$transcript]',
      );
      if ( transcript.isEmpty ) {
        throw const AsrException( 'Transcription came back empty' );
      }
      return transcript;
    } on DioException catch ( e ) {
      final status = e.response?.statusCode;
      // The v2 endpoint says "nothing was heard" with a 422 rather than an empty 200, and "GPU busy, try
      // again" with a 503; both read better to a user than a raw transport message.
      if ( status == 422 ) {
        throw const AsrException( 'Transcription came back empty', statusCode: 422 );
      }
      if ( status == 503 ) {
        throw const AsrException( 'The server is busy transcribing. Try again in a few seconds.', statusCode: 503 );
      }
      throw AsrException(
        'Transcription upload failed: ${e.message ?? e.type.name}',
        statusCode: status,
      );
    } finally {
      discardPendingUpload( filePath );
    }
  }

  /// The transcript out of a `/api/v2/transcribe` 200 body.
  ///
  /// Requires:
  ///   - data is the decoded response body
  ///
  /// Ensures:
  ///   - returns `data['transcription']` when data is a map holding a string there
  ///
  /// Raises:
  ///   - [AsrException] for any other shape, naming what arrived
  @visibleForTesting
  static String transcriptFrom( Object? data ) {
    if ( data is Map && data[ 'transcription' ] is String ) {
      return data[ 'transcription' ] as String;
    }
    throw AsrException( 'Unexpected transcription response shape: ${data.runtimeType}' );
  }

  /// Discards the in-progress capture without uploading, and removes the temp file.
  ///
  /// The recorder's own cancel() deletes it too; this is a second guard.
  Future<void> cancelRecording() async {
    final path = _activePath;
    _setActivePath( null );
    _captureStartedAt = null;
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
