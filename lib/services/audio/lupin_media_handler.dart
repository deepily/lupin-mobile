import 'dart:async';

import 'package:audio_service/audio_service.dart';

import '../../core/logging/logger.dart';

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

/// Real media audio that plays while a claimant holds the earbud presses.
///
/// Android gives an earbud press to the app that played audio last, not to the session that reports "playing".
/// On a Pixel with Android 17, this session was active and playing, yet a tap went to another app.
/// That app's session was stopped, but it had played audio more recently.
abstract interface class ClaimKeepAlive {
  /// Starts the stream.
  ///
  /// Ensures:
  ///   - a call while it is already running does nothing
  Future<void> start();

  /// Stops the stream.
  ///
  /// Ensures:
  ///   - a call while it is stopped does nothing
  Future<void> stop();
}

/// The app's one media session: the lock-screen card, and where earbud presses go.
///
/// By default a press drives the podcast, as a media player's should.
/// While a claimant holds the presses (Quick Ask's hands-free mode), presses go to it instead.
/// The session then shows the claimant's card in place of the podcast's.
///
/// A playing podcast always wins: while one plays, a press pauses it and the session shows it.
/// A podcast can start under a claim, from the mini-player or after the app finishes speaking.
/// It can still be paused from the earbuds and the lock screen.
class LupinMediaHandler extends BaseAudioHandler {
  /// The log tag of the earbud diagnostics: claim, release, each press and where it went.
  static const String logTag = 'EarbudTrace';

  /// How far the media rewind key backs up.
  final Duration rewindInterval;
  /// How far the media fast-forward key jumps ahead.
  final Duration fastForwardInterval;
  /// Plays while the claimant's card shows, so presses come to this app.
  ///
  /// Null in tests that don't need it.
  final ClaimKeepAlive? keepAlive;

  MediaTransport?      _transport;
  MediaButtonClaimant? _claimant;
  MediaItem?           _card;
  MediaItem?           _podcastItem;
  PlaybackState        _podcastState = PlaybackState();
  bool                 _keepAliveOn  = false;

  /// Creates the handler; the app makes exactly one, through `AudioService.init`.
  LupinMediaHandler( {
    required this.rewindInterval,
    this.fastForwardInterval = const Duration( seconds: 10 ),
    this.keepAlive,
  } );

  /// Whether a claimant holds the earbud presses.
  bool get isClaimed => _claimant != null;

  /// Connects the podcast player that play, pause and seek act on.
  void attach( MediaTransport transport ) => _transport = transport;

  /// Whether presses go to the claimant: one holds them and no podcast is playing.
  bool get _claimantActs => _claimant != null && !_podcastState.playing;

  /// Shows the claimant's card, or the podcast's.
  ///
  /// The claimant's card is shown as playing, and [keepAlive] plays under it.
  /// Together they keep this the session Android sends presses to.
  void _show() {
    final claimantActs = _claimantActs;
    if ( claimantActs ) {
      mediaItem.add( _card );
      playbackState.add( PlaybackState( processingState: AudioProcessingState.ready, playing: true ) );
    } else {
      mediaItem.add( _podcastItem );
      playbackState.add( _podcastState );
    }
    _syncKeepAlive( claimantActs );
  }

  /// Runs [keepAlive] exactly while the claimant's card shows.
  ///
  /// A playing podcast is real media already, so the stream stops under it and resumes when it pauses.
  ///
  /// Ensures:
  ///   - start and stop are called only on a change, and each change is logged
  ///   - a failure to start or stop is logged, never thrown into the caller
  void _syncKeepAlive( bool on ) {
    if ( on == _keepAliveOn ) return;
    _keepAliveOn = on;
    Logger.info( 'keepAlive: ${ on ? "on" : "off" }', tag: logTag );
    final stream = keepAlive;
    if ( stream == null ) return;
    unawaited( ( on ? stream.start() : stream.stop() ).catchError( ( Object e, StackTrace s ) {
      Logger.warning( 'keepAlive: ${ on ? "start" : "stop" } failed: $e', tag: logTag, error: e, stackTrace: s );
    } ) );
  }

  /// Records [item] as the podcast's card, and shows it unless the claimant's card is showing.
  void showTrack( MediaItem item ) {
    _podcastItem = item;
    _show();
  }

  /// Records the podcast player's state, and shows it unless the claimant's card is showing.
  ///
  /// Ensures:
  ///   - the reported state is not "playing" once the track is idle, finished or failed
  void reportPodcast( {
    required bool                 playing,
    required AudioProcessingState processingState,
    required Duration             position,
    Duration                      bufferedPosition = Duration.zero,
  } ) {
    final stopped  = processingState == AudioProcessingState.idle
        || processingState == AudioProcessingState.completed
        || processingState == AudioProcessingState.error;
    final controls = [ playing ? MediaControl.pause : MediaControl.play, MediaControl.stop ];
    _podcastState  = PlaybackState(
      controls                   : controls,
      systemActions              : const { MediaAction.seek },
      androidCompactActionIndices: const [ 0 ],
      processingState            : processingState,
      playing                    : playing && !stopped,
      updatePosition             : position,
      bufferedPosition           : bufferedPosition,
    );
    _show();
  }

  /// Gives the earbud presses to [claimant] until [release], and shows [card].
  ///
  /// A playing podcast pauses, so one tap means one thing.
  ///
  /// Ensures:
  ///   - [isClaimed] is true
  ///   - a later claim replaces this one
  Future<void> claim( MediaButtonClaimant claimant, { required MediaItem card } ) async {
    _claimant = claimant;
    _card     = card;
    final playing = _podcastState.playing;
    Logger.info( 'claim: podcastPlaying=$playing', tag: logTag );
    _show();
    if ( playing ) await _transport?.pause();
  }

  /// Gives the presses back to the podcast, if [claimant] still holds them.
  ///
  /// A release by a claimant that was already replaced does nothing.
  /// So a screen closing late can't take the presses from the screen that replaced it.
  void release( MediaButtonClaimant claimant ) {
    if ( !identical( _claimant, claimant ) ) return;
    Logger.info( 'release', tag: logTag );
    _claimant = null;
    _card     = null;
    _show();
  }

  @override
  Future<void> click( [ MediaButton button = MediaButton.media ] ) async {
    final claimant = _claimant;
    final toClaimant = claimant != null && _claimantActs;
    Logger.info( 'click: button=${ button.name } claimed=${ claimant != null } podcastPlaying=${ _podcastState.playing } '
        'to=${ toClaimant ? "quick-ask" : "podcast" }', tag: logTag );
    if ( toClaimant ) {
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
