import 'dart:async';

import 'package:audio_service/audio_service.dart';

/// What the media session's play, pause and seek controls act on: the podcast player.
abstract interface class MediaTransport {
  /// Where the loaded track is now.
  Duration get position;
  /// Starts or continues playback.
  Future<void> play();
  /// Pauses playback, keeping the position.
  Future<void> pause();
  /// Moves to [position] in the loaded track.
  Future<void> seek( Duration position );
  /// Stops playback.
  Future<void> stop();
}

/// A screen that takes the earbud presses for itself while it holds them.
abstract interface class MediaButtonClaimant {
  /// Called for each earbud or headset press while this claimant holds the presses.
  void onMediaButton( MediaButton button );
}

/// The app's one media session: the lock-screen card, and where earbud presses go.
///
/// By default a press drives the podcast, as a media player's should.
/// While a claimant holds the presses (Quick Ask's hands-free mode), every press goes to it instead.
/// The session then shows the claimant's card in place of the podcast's.
class LupinMediaHandler extends BaseAudioHandler {
  /// How far the media rewind key backs up.
  final Duration rewindInterval;
  /// How far the media fast-forward key jumps ahead.
  final Duration fastForwardInterval;

  MediaTransport?      _transport;
  MediaButtonClaimant? _claimant;
  MediaItem?           _podcastItem;
  PlaybackState        _podcastState = PlaybackState();

  /// Creates the handler; the app makes exactly one, through `AudioService.init`.
  LupinMediaHandler( {
    required this.rewindInterval,
    this.fastForwardInterval = const Duration( seconds: 10 ),
  } );

  /// Whether a claimant holds the earbud presses.
  bool get isClaimed => _claimant != null;

  /// Connects the podcast player that play, pause and seek act on.
  void attach( MediaTransport transport ) => _transport = transport;

  /// Shows [item] as the podcast's card, unless a claimant's card is showing.
  void showTrack( MediaItem item ) {
    _podcastItem = item;
    if ( _claimant == null ) mediaItem.add( item );
  }

  /// Records the podcast player's state, and shows it unless a claimant holds the session.
  ///
  /// Ensures:
  ///   - the reported state is not "playing" once the track is idle or finished
  void reportPodcast( {
    required bool                 playing,
    required AudioProcessingState processingState,
    required Duration             position,
    Duration                      bufferedPosition = Duration.zero,
  } ) {
    final stopped  = processingState == AudioProcessingState.idle
        || processingState == AudioProcessingState.completed;
    final controls = [ playing ? MediaControl.pause : MediaControl.play, MediaControl.stop ];
    _podcastState  = PlaybackState(
      controls                   : controls,
      systemActions              : const { MediaAction.seek, MediaAction.seekForward, MediaAction.seekBackward },
      androidCompactActionIndices: const [ 0 ],
      processingState            : processingState,
      playing                    : playing && !stopped,
      updatePosition             : position,
      bufferedPosition           : bufferedPosition,
    );
    if ( _claimant == null ) playbackState.add( _podcastState );
  }

  /// Gives every earbud press to [claimant] until [release], and shows [card].
  ///
  /// A playing podcast pauses, so one tap means one thing.
  /// The session reports itself as playing while claimed. That keeps it the session Android sends presses to.
  ///
  /// Ensures:
  ///   - [isClaimed] is true
  ///   - a later claim replaces this one
  Future<void> claim( MediaButtonClaimant claimant, { required MediaItem card } ) async {
    _claimant = claimant;
    mediaItem.add( card );
    playbackState.add( PlaybackState( processingState: AudioProcessingState.ready, playing: true ) );
    if ( _podcastState.playing ) await _transport?.pause();
  }

  /// Gives the presses back to the podcast, if [claimant] still holds them.
  ///
  /// A release by a claimant that was already replaced does nothing.
  /// So a screen closing late can't take the presses from the screen that replaced it.
  void release( MediaButtonClaimant claimant ) {
    if ( !identical( _claimant, claimant ) ) return;
    _claimant = null;
    mediaItem.add( _podcastItem );
    playbackState.add( _podcastState );
  }

  @override
  Future<void> click( [ MediaButton button = MediaButton.media ] ) async {
    final claimant = _claimant;
    if ( claimant != null ) {
      claimant.onMediaButton( button );
      return;
    }
    await super.click( button );
  }

  @override
  Future<void> play() async => _transport?.play();

  @override
  Future<void> pause() async => _transport?.pause();

  @override
  Future<void> seek( Duration position ) async => _transport?.seek( position );

  @override
  Future<void> rewind() async {
    final transport = _transport;
    if ( transport == null ) return;
    final back = transport.position - rewindInterval;
    await transport.seek( back.isNegative ? Duration.zero : back );
  }

  @override
  Future<void> fastForward() async {
    final transport = _transport;
    if ( transport == null ) return;
    await transport.seek( transport.position + fastForwardInterval );
  }

  @override
  Future<void> stop() async {
    await _transport?.stop();
    await super.stop();
  }
}
