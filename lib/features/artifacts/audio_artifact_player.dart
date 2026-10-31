import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/di/service_locator.dart';
import '../../core/testing/test_keys.dart';
import '../../services/artifacts/io_file_service.dart';
import '../../services/audio/podcast_player_service.dart';

enum _PlaybackState { idle, loading, ready, error }

/// In-app audio playback for podcast / research-podcast artifacts.
///
/// Downloads the MP3 once via [IoFileService.downloadToCache], then plays
/// in-app through the app-wide [PodcastPlayerService], which keeps playing after this
/// screen is popped and owns the lock-screen media session. The original
/// download-and-share flow remains accessible as a Share overflow action.
class AudioArtifactPlayer extends StatefulWidget {
  /// The id of the job that produced the audio.
  final String jobId;
  /// The server-side path of the MP3 file.
  final String audioPath;

  /// Test seam — production code resolves [PodcastPlayerService] from the locator.
  final PodcastPlayerService? playerService;

  /// Test seam — production code resolves [IoFileService] from the locator.
  final IoFileService? ioFileService;


  /// Creates the player; the job id and audio path are required.
  const AudioArtifactPlayer( {
    super.key,
    required this.jobId,
    required this.audioPath,
    this.playerService,
    this.ioFileService,
  } );

  @override
  State<AudioArtifactPlayer> createState() => _AudioArtifactPlayerState();
}

class _AudioArtifactPlayerState extends State<AudioArtifactPlayer> {
  _PlaybackState _state = _PlaybackState.idle;
  File?          _file;
  String?        _errorMsg;

  @override
  void initState() {
    super.initState();
    // Coming back to a track that is still loaded: show its controls at once.
    if ( _player.trackId == widget.jobId ) {
      _file  = _player.file;
      _state = _PlaybackState.ready;
    }
  }

  PodcastPlayerService get _player => widget.playerService ?? ServiceLocator.instance<PodcastPlayerService>();
  IoFileService        get _io     => widget.ioFileService ?? ServiceLocator.instance<IoFileService>();

  bool get _isCurrent => _player.trackId == widget.jobId;

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
    await _player.playFile( _file!, widget.jobId, id: widget.jobId );
  }

  Future<void> _pause() => _player.pause();

  Future<void> _stop() async {
    if ( _isCurrent ) await _player.stop();
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
    return ListenableBuilder( listenable: _player, builder: _buildScaffold );
  }

  Widget _buildScaffold( BuildContext context, Widget? _ ) {
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
            if ( _state == _PlaybackState.ready ) _buildTransport(),
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
    final isPlaying = _isCurrent && _player.isPlaying;
    final position  = _isCurrent ? _player.position : Duration.zero;
    final duration  = _isCurrent ? _player.duration : Duration.zero;
    return Column(
      children: [
        Slider(
          key       : const Key( TestKeys.audioPlayerSlider ),
          min       : 0,
          max       : ( duration.inMilliseconds == 0 ? 1 : duration.inMilliseconds ).toDouble(),
          value     : position.inMilliseconds.clamp( 0, duration.inMilliseconds ).toDouble(),
          onChanged : null, // Seek is intentionally read-only in this iteration.
        ),
        Padding(
          padding: const EdgeInsets.symmetric( horizontal: 8 ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text( _fmt( position ) ),
              Text( _fmt( duration ) ),
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
