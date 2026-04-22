import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../../core/di/service_locator.dart';
import '../../core/testing/test_keys.dart';
import '../../services/artifacts/io_file_service.dart';
import '../../services/tts/tts_orchestrator.dart';

/// Thin wrapper around `audioplayers.AudioPlayer` so the widget can be
/// widget-tested without invoking platform channels (which `audioplayers`
/// requires and which the Flutter test runner cannot satisfy).
///
/// Tests inject a Mocktail-driven implementation; production builds use
/// [_RealAudioPlaybackController].
abstract class AudioPlaybackController {
  Stream<Duration> get onPosition;
  Stream<Duration> get onDuration;
  Stream<void>     get onComplete;
  Future<void> play( File file );
  Future<void> pause();
  Future<void> resume();
  Future<void> stop();
  Future<void> dispose();
}

class _RealAudioPlaybackController implements AudioPlaybackController {
  final AudioPlayer _p = AudioPlayer();

  @override Stream<Duration> get onPosition => _p.onPositionChanged;
  @override Stream<Duration> get onDuration => _p.onDurationChanged;
  @override Stream<void>     get onComplete => _p.onPlayerComplete;

  @override
  Future<void> play( File file ) => _p.play( DeviceFileSource( file.path ) );

  @override
  Future<void> pause() => _p.pause();

  @override
  Future<void> resume() => _p.resume();

  @override
  Future<void> stop() async {
    try { await _p.stop(); } catch ( _ ) {
      // audioplayers can throw on stop of an already-stopped player; ignore.
    }
  }

  @override
  Future<void> dispose() => _p.dispose();
}

enum _PlaybackState { idle, loading, ready, playing, paused, error }

/// In-app audio playback for podcast / research-podcast artifacts.
///
/// Downloads the MP3 once via [IoFileService.downloadToCache], then plays
/// in-app via `audioplayers` + `DeviceFileSource`. Stops any active TTS
/// utterance via [TtsOrchestrator.stopAll] before starting playback so the
/// device only emits one audio stream at a time. The original
/// download-and-share flow remains accessible as a Share overflow action.
class AudioArtifactPlayer extends StatefulWidget {
  final String jobId;
  final String audioPath;

  /// Test seam — production code passes nothing and gets a real controller.
  final AudioPlaybackController? controller;

  /// Test seam — production code resolves [IoFileService] from the locator.
  final IoFileService? ioFileService;

  /// Test seam — production code resolves [TtsOrchestrator] from the locator.
  final TtsOrchestrator? ttsOrchestrator;

  const AudioArtifactPlayer( {
    super.key,
    required this.jobId,
    required this.audioPath,
    this.controller,
    this.ioFileService,
    this.ttsOrchestrator,
  } );

  @override
  State<AudioArtifactPlayer> createState() => _AudioArtifactPlayerState();
}

class _AudioArtifactPlayerState extends State<AudioArtifactPlayer> {
  late final AudioPlaybackController _ctrl;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  StreamSubscription<void>?     _completeSub;

  _PlaybackState _state    = _PlaybackState.idle;
  Duration       _position = Duration.zero;
  Duration       _duration = Duration.zero;
  File?          _file;
  String?        _errorMsg;

  @override
  void initState() {
    super.initState();
    _ctrl = widget.controller ?? _RealAudioPlaybackController();
    _posSub      = _ctrl.onPosition.listen( ( p ) {
      if ( mounted ) setState( () => _position = p );
    } );
    _durSub      = _ctrl.onDuration.listen( ( d ) {
      if ( mounted ) setState( () => _duration = d );
    } );
    _completeSub = _ctrl.onComplete.listen( ( _ ) {
      if ( mounted ) {
        setState( () {
          _state    = _PlaybackState.ready;
          _position = Duration.zero;
        } );
      }
    } );
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _durSub?.cancel();
    _completeSub?.cancel();
    _ctrl.stop();
    _ctrl.dispose();
    super.dispose();
  }

  IoFileService get _io   => widget.ioFileService    ?? ServiceLocator.instance<IoFileService>();
  TtsOrchestrator get _tts => widget.ttsOrchestrator ?? ServiceLocator.instance<TtsOrchestrator>();

  Future<void> _download() async {
    if ( widget.audioPath.isEmpty ) {
      setState( () {
        _state    = _PlaybackState.error;
        _errorMsg = "No audio path available for this job.";
      } );
      return;
    }
    setState( () => _state = _PlaybackState.loading );
    try {
      final file = await _io.downloadToCache( widget.audioPath, '${widget.jobId}.mp3' );
      if ( !mounted ) return;
      setState( () {
        _file  = file;
        _state = _PlaybackState.ready;
      } );
    } catch ( e ) {
      if ( !mounted ) return;
      setState( () {
        _state    = _PlaybackState.error;
        _errorMsg = "Download failed: $e";
      } );
    }
  }

  Future<void> _play() async {
    if ( _file == null ) return;
    // Stop any concurrent TTS first so device emits a single audio stream.
    await _tts.stopAll();
    if ( !mounted ) return;
    if ( _state == _PlaybackState.paused ) {
      await _ctrl.resume();
    } else {
      await _ctrl.play( _file! );
    }
    if ( mounted ) setState( () => _state = _PlaybackState.playing );
  }

  Future<void> _pause() async {
    await _ctrl.pause();
    if ( mounted ) setState( () => _state = _PlaybackState.paused );
  }

  Future<void> _stop() async {
    await _ctrl.stop();
    if ( mounted ) {
      setState( () {
        _state    = _PlaybackState.ready;
        _position = Duration.zero;
      } );
    }
  }

  Future<void> _share() async {
    if ( _file == null ) return;
    try {
      await _io.shareToExternalApp( _file! );
    } catch ( e ) {
      if ( !mounted ) return;
      ScaffoldMessenger.of( context ).showSnackBar(
        SnackBar( content: Text( "Share failed: $e" ), backgroundColor: Colors.red ),
      );
    }
  }

  String _fmt( Duration d ) {
    final m = d.inMinutes.toString().padLeft( 2, '0' );
    final s = ( d.inSeconds % 60 ).toString().padLeft( 2, '0' );
    return "$m:$s";
  }

  @override
  Widget build( BuildContext context ) {
    return Scaffold(
      appBar: AppBar(
        title: Text( 'Audio — ${widget.jobId}' ),
        actions: [
          if ( _file != null )
            IconButton(
              key      : const Key( TestKeys.audioPlayerShareButton ),
              tooltip  : "Share",
              icon     : const Icon( Icons.share_outlined ),
              onPressed: _share,
            ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all( 24 ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon( Icons.audiotrack_outlined, size: 80 ),
            const SizedBox( height: 16 ),
            Text(
              widget.jobId,
              style: Theme.of( context ).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox( height: 32 ),
            if ( _state == _PlaybackState.idle ) _buildDownload(),
            if ( _state == _PlaybackState.loading )
              const CircularProgressIndicator(),
            if ( _state == _PlaybackState.error )
              _buildError(),
            if ( _state == _PlaybackState.ready   ||
                 _state == _PlaybackState.playing ||
                 _state == _PlaybackState.paused )
              _buildTransport(),
          ],
        ),
      ),
    );
  }

  Widget _buildDownload() {
    return FilledButton.icon(
      key      : const Key( TestKeys.audioPlayerDownloadButton ),
      onPressed: _download,
      icon     : const Icon( Icons.download_outlined ),
      label    : const Text( "Download" ),
    );
  }

  Widget _buildError() {
    return Column(
      children: [
        Text(
          _errorMsg ?? "Playback error",
          style: TextStyle( color: Theme.of( context ).colorScheme.error ),
          textAlign: TextAlign.center,
        ),
        const SizedBox( height: 16 ),
        OutlinedButton.icon(
          key      : const Key( TestKeys.audioPlayerDownloadButton ),
          onPressed: _download,
          icon     : const Icon( Icons.refresh ),
          label    : const Text( "Retry" ),
        ),
      ],
    );
  }

  Widget _buildTransport() {
    final isPlaying = _state == _PlaybackState.playing;
    return Column(
      children: [
        Slider(
          key       : const Key( TestKeys.audioPlayerSlider ),
          min       : 0,
          max       : ( _duration.inMilliseconds == 0 ? 1 : _duration.inMilliseconds ).toDouble(),
          value     : _position.inMilliseconds.clamp( 0, _duration.inMilliseconds ).toDouble(),
          onChanged : null, // Seek is intentionally read-only in this iteration.
        ),
        Padding(
          padding: const EdgeInsets.symmetric( horizontal: 8 ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text( _fmt( _position ) ),
              Text( _fmt( _duration ) ),
            ],
          ),
        ),
        const SizedBox( height: 16 ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if ( !isPlaying )
              IconButton.filled(
                key      : const Key( TestKeys.audioPlayerPlayButton ),
                tooltip  : "Play",
                iconSize : 32,
                icon     : const Icon( Icons.play_arrow ),
                onPressed: _play,
              ),
            if ( isPlaying )
              IconButton.filled(
                key      : const Key( TestKeys.audioPlayerPauseButton ),
                tooltip  : "Pause",
                iconSize : 32,
                icon     : const Icon( Icons.pause ),
                onPressed: _pause,
              ),
            const SizedBox( width: 16 ),
            IconButton(
              key      : const Key( TestKeys.audioPlayerStopButton ),
              tooltip  : "Stop",
              iconSize : 32,
              icon     : const Icon( Icons.stop ),
              onPressed: _stop,
            ),
          ],
        ),
      ],
    );
  }
}
