import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../tts/tts_orchestrator.dart';
import 'podcast_cache.dart';
import 'podcast_link.dart';

/// Thin seam over the platform audio player so the service can be unit-tested.
///
/// Production uses `JustAudioPlaybackEngine`; tests inject a fake.
abstract class PodcastPlaybackEngine {
  /// Emits the current playback position.
  Stream<Duration> get onPosition;
  /// Emits the total length of the loaded audio, when known.
  Stream<Duration?> get onDuration;
  /// Emits whether the engine is playing, including lock-screen and earbud presses.
  Stream<bool> get onPlaying;
  /// Emits once each time playback reaches the end.
  Stream<void> get onComplete;
  /// Loads [file] and labels it with [id] and [title] for the media session.
  Future<void> load( File file, String id, String title );
  /// Starts or continues playback.
  Future<void> play();
  /// Pauses playback, keeping the position.
  Future<void> pause();
  /// Moves to the start of the loaded audio.
  Future<void> rewind();
  /// Stops playback and releases the media session.
  Future<void> stop();
}

/// What the service is doing with its current track.
enum PodcastPlayerStatus {
  /// Nothing loaded.
  idle,
  /// Downloading the file.
  loading,
  /// Audio is coming out.
  playing,
  /// A track is loaded and held.
  paused,
  /// The last load or download failed.
  error,
}

/// The one app-wide podcast player.
///
/// Lives for the life of the app, not of a screen, so audio keeps playing when the
/// screen that started it is popped. The media session (lock screen, earbuds) is the
/// engine's job; this class owns what the app shows and which track is current.
class PodcastPlayerService extends ChangeNotifier {
  final PodcastPlaybackEngine Function() _engineFactory;
  final PodcastCache Function()           _cacheFactory;
  final Future<PodcastLink> Function()    _linkProbe;
  final TtsOrchestrator Function()        _ttsFactory;

  PodcastPlaybackEngine? _engine;
  final List<StreamSubscription<dynamic>> _subs = [];
  StreamSubscription<bool>? _speechSub;

  PodcastPlayerStatus _status   = PodcastPlayerStatus.idle;
  String?             _trackId;
  String?             _title;
  String?             _error;
  File?               _file;
  bool                _heldForSpeech = false;
  Duration            _position = Duration.zero;
  Duration            _duration = Duration.zero;

  /// Creates the service; every collaborator is built on first use.
  PodcastPlayerService( {
    required PodcastPlaybackEngine Function() engineFactory,
    required PodcastCache Function()          cacheFactory,
    required Future<PodcastLink> Function()   linkProbe,
    required TtsOrchestrator Function()       ttsFactory,
  } ) : _engineFactory = engineFactory,
        _cacheFactory  = cacheFactory,
        _linkProbe     = linkProbe,
        _ttsFactory    = ttsFactory;

  /// What the player is doing now.
  PodcastPlayerStatus get status   => _status;
  /// Id of the loaded track (the job id), or null when idle.
  String?             get trackId  => _trackId;
  /// Title shown in the mini-player, or null when idle.
  String?             get title    => _title;
  /// The loaded audio file, or null when idle.
  File?               get file     => _file;
  /// Why the last load failed, or null.
  String?             get error    => _error;
  /// Current playback position.
  Duration            get position => _position;
  /// Length of the loaded track; zero until known.
  Duration            get duration => _duration;
  /// True while a track is loaded, playing or paused.
  bool                get hasTrack => _status == PodcastPlayerStatus.playing || _status == PodcastPlayerStatus.paused;
  /// True while audio is coming out.
  bool                get isPlaying => _status == PodcastPlayerStatus.playing;

  /// True when the loaded track is a download kept on the phone.
  bool                get trackDownloaded => _trackId != null && _cacheFactory().isCached( _trackId! );

  /// Plays the server file at [audioPath], from the phone's downloads when it is there.
  ///
  /// A downloaded file plays with no network call. Otherwise the file is downloaded and kept under
  /// [id]: at once on Wi-Fi, and on mobile data only after [confirmMobileData] returns true.
  ///
  /// Requires [audioPath] non-empty. Sets [status] to error with a message otherwise, when
  /// there is no connection, or when the download fails. Plays nothing and changes nothing if [id] is
  /// already loaded and playing, or if the listener declines mobile data (a null [confirmMobileData] declines).
  Future<void> play( String audioPath, String title, {required String id, Future<bool> Function()? confirmMobileData} ) async {
    if ( audioPath.isEmpty ) {
      _fail( "No audio path available for this job." );
      return;
    }
    if ( id == _trackId && hasTrack ) {
      await resume();
      return;
    }
    final cache = _cacheFactory();
    File? file  = await cache.lookup( id );
    if ( file == null ) {
      final link = await _linkProbe();
      if ( link == PodcastLink.offline ) {
        _fail( "Not downloaded, and there is no connection." );
        return;
      }
      if ( link == PodcastLink.metered && !( await ( confirmMobileData?.call() ?? Future.value( false ) ) ) ) return;
    }
    _status = PodcastPlayerStatus.loading;
    _title  = title;
    notifyListeners();
    try {
      file ??= await cache.fetch( audioPath, id );
    } catch ( e ) {
      _fail( "Download failed: $e" );
      return;
    }
    await playFile( file, title, id: id );
  }

  /// Plays an already-downloaded [file], replacing any current track.
  Future<void> playFile( File file, String title, {required String id} ) async {
    if ( id == _trackId && hasTrack ) {
      await resume();
      return;
    }
    await _ttsFactory().stopAll();
    _heldForSpeech = false;
    final engine = _ensureEngine();
    _trackId  = id;
    _title    = title;
    _file     = file;
    _position = Duration.zero;
    _duration = Duration.zero;
    _error    = null;
    try {
      await engine.load( file, id, title );
      await engine.play();
    } catch ( e ) {
      _fail( "Playback failed: $e" );
      return;
    }
    _status = PodcastPlayerStatus.playing;
    notifyListeners();
  }

  /// Pauses the current track, keeping its position.
  Future<void> pause() async {
    if ( !isPlaying ) return;
    await _engine!.pause();
    _status = PodcastPlayerStatus.paused;
    notifyListeners();
  }

  /// Continues a paused track.
  Future<void> resume() async {
    _heldForSpeech = false;
    if ( _status != PodcastPlayerStatus.paused ) return;
    await _ttsFactory().stopAll();
    await _engine!.play();
    _status = PodcastPlayerStatus.playing;
    notifyListeners();
  }

  /// Pauses the podcast whenever [speaking] emits true and resumes it when it emits false.
  ///
  /// Call once at startup with the TTS orchestrator's `speakingStream`. A second call replaces the first.
  void followSpeech( Stream<bool> speaking ) {
    _speechSub?.cancel();
    _speechSub = speaking.listen( ( on ) => on ? pauseForSpeech() : resumeAfterSpeech() );
  }

  /// Pauses the podcast so spoken TTS or a wake item can be heard.
  ///
  /// This is the audio-focus ruling: the podcast never talks over speech.
  ///
  /// Does nothing unless a track is playing. [resumeAfterSpeech] undoes exactly this pause.
  Future<void> pauseForSpeech() async {
    if ( !isPlaying ) return;
    await pause();
    _heldForSpeech = true;
  }

  /// Continues a podcast that [pauseForSpeech] paused.
  ///
  /// Does not stop any speech that is still playing.
  ///
  /// Does nothing if the listener paused, stopped or switched tracks in the meantime.
  Future<void> resumeAfterSpeech() async {
    if ( !_heldForSpeech ) return;
    _heldForSpeech = false;
    if ( _status != PodcastPlayerStatus.paused ) return;
    await _engine!.play();
    _status = PodcastPlayerStatus.playing;
    notifyListeners();
  }

  /// Stops the track and clears the mini-player.
  Future<void> stop() async {
    _heldForSpeech = false;
    if ( _engine != null ) await _engine!.stop();
    _status   = PodcastPlayerStatus.idle;
    _trackId  = null;
    _title    = null;
    _file     = null;
    _position = Duration.zero;
    _duration = Duration.zero;
    notifyListeners();
  }

  void _fail( String message ) {
    _status = PodcastPlayerStatus.error;
    _error  = message;
    notifyListeners();
  }

  PodcastPlaybackEngine _ensureEngine() {
    if ( _engine != null ) return _engine!;
    final engine = _engineFactory();
    _engine = engine;
    _subs.add( engine.onPosition.listen( ( p ) {
      _position = p;
      notifyListeners();
    } ) );
    _subs.add( engine.onDuration.listen( ( d ) {
      _duration = d ?? Duration.zero;
      notifyListeners();
    } ) );
    // Lock-screen and earbud presses reach the engine, not this class; follow them.
    _subs.add( engine.onPlaying.listen( ( playing ) {
      if ( !hasTrack ) return;
      _status = playing ? PodcastPlayerStatus.playing : PodcastPlayerStatus.paused;
      notifyListeners();
    } ) );
    _subs.add( engine.onComplete.listen( ( _ ) async {
      await engine.pause();
      await engine.rewind();
      _status   = PodcastPlayerStatus.paused;
      _position = Duration.zero;
      notifyListeners();
    } ) );
    return engine;
  }

  @override
  void dispose() {
    for ( final s in _subs ) { s.cancel(); }
    _speechSub?.cancel();
    super.dispose();
  }
}
