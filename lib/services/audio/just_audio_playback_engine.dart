import 'dart:io';

import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'podcast_player_service.dart';

/// The real engine: `just_audio` with a `just_audio_background` media session.
///
/// Each track carries a `MediaItem`, which is what the lock screen and the
/// foreground-service notification display.
class JustAudioPlaybackEngine implements PodcastPlaybackEngine {
  final AudioPlayer _player;

  /// Creates the engine; [player] is a test seam, production passes nothing.
  JustAudioPlaybackEngine( {AudioPlayer? player} ) : _player = player ?? AudioPlayer();

  @override
  Stream<Duration>  get onPosition => _player.positionStream;
  @override
  Stream<Duration?> get onDuration => _player.durationStream;
  @override
  Stream<bool>      get onPlaying  => _player.playingStream;
  @override
  Stream<void>      get onComplete => _player.processingStateStream.where( ( s ) => s == ProcessingState.completed );

  @override
  Future<void> load( File file, String id, String title ) =>
      _player.setAudioSource( AudioSource.file( file.path, tag: MediaItem( id: id, title: title ) ) );

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> rewind() => _player.seek( Duration.zero );

  @override
  Future<void> stop() => _player.stop();
}
