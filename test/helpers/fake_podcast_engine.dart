import 'dart:async';
import 'dart:io';

import 'package:lupin_mobile/services/audio/podcast_player_service.dart';

/// Records calls and lets a test push engine events, as the lock screen would.
class FakeEngine implements PodcastPlaybackEngine {
  final pos      = StreamController<Duration>.broadcast();
  final dur      = StreamController<Duration?>.broadcast();
  final playing  = StreamController<bool>.broadcast();
  final complete = StreamController<void>.broadcast();
  final calls    = <String>[];
  bool  failLoad = false;

  @override Stream<Duration>  get onPosition => pos.stream;
  @override Stream<Duration?> get onDuration => dur.stream;
  @override Stream<bool>      get onPlaying  => playing.stream;
  @override Stream<void>      get onComplete => complete.stream;

  @override
  Future<void> load( File file, String id, String title ) async {
    calls.add( "load:$id:$title:${file.path}" );
    if ( failLoad ) throw StateError( "bad codec" );
  }
  @override Future<void> play()   async => calls.add( "play" );
  @override Future<void> pause()  async => calls.add( "pause" );
  @override Future<void> rewind() async => calls.add( "rewind" );
  @override Future<void> stop()   async => calls.add( "stop" );
}
