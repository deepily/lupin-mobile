import 'dart:async';
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

import 'lupin_media_handler.dart';
import 'podcast_player_service.dart';

/// The real engine: `just_audio`, shown on the lock screen through [LupinMediaHandler].
///
/// The engine reports each player event to the handler, which draws the lock-screen card
/// and routes the earbud and lock-screen buttons back here.
class JustAudioPlaybackEngine implements PodcastPlaybackEngine, MediaTransport {
  final AudioPlayer       _player;
  final LupinMediaHandler _handler;
  MediaItem?              _item;

  /// Creates the engine and attaches it to [handler].
  ///
  /// [player] is a test seam; production passes nothing.
  JustAudioPlaybackEngine( { required LupinMediaHandler handler, AudioPlayer? player } )
      : _handler = handler,
        _player  = player ?? AudioPlayer() {
    _handler.attach( this );
    _player.playbackEventStream.listen( ( _ ) => _report(), onError: ( Object _ ) {} );
    _player.playingStream.listen( ( _ ) => _report() );
    _player.durationStream.listen( ( d ) {
      final item = _item;
      if ( item == null || d == null || d == item.duration ) return;
      _item = item.copyWith( duration: d );
      _handler.showTrack( _item! );
    } );
  }

  static const _states = {
    ProcessingState.idle      : AudioProcessingState.idle,
    ProcessingState.loading   : AudioProcessingState.loading,
    ProcessingState.buffering : AudioProcessingState.buffering,
    ProcessingState.ready     : AudioProcessingState.ready,
    ProcessingState.completed : AudioProcessingState.completed,
  };

  void _report() => _handler.reportPodcast(
    playing          : _player.playing,
    processingState  : _states[ _player.processingState ]!,
    position         : _player.position,
    bufferedPosition : _player.bufferedPosition,
  );

  @override
  Stream<Duration>  get onPosition => _player.positionStream;
  @override
  Stream<Duration?> get onDuration => _player.durationStream;
  @override
  Stream<bool>      get onPlaying  => _player.playingStream;
  @override
  Stream<void>      get onComplete => _player.processingStateStream.where( ( s ) => s == ProcessingState.completed );

  @override
  Duration get position => _player.position;

  @override
  Future<void> load( File file, String id, String title ) async {
    _item = MediaItem( id: id, title: title );
    _handler.showTrack( _item! );
    await _player.setAudioSource( AudioSource.file( file.path ) );
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> rewind() => _player.seek( Duration.zero );

  @override
  Future<void> seek( Duration position ) => _player.seek( position );

  @override
  Future<void> stop() => _player.stop();
}
