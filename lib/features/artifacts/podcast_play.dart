import '../../core/di/service_locator.dart';
import '../../services/audio/podcast_player_service.dart';

/// Plays a podcast from its audio [url], showing [title].
///
/// This is the shape the app-wide player service exposes.
typedef PodcastPlay = Future<void> Function( String url, String title );

/// The one place a podcast card's Play goes: the app-wide [PodcastPlayerService].
///
/// The track id is the audio's server path, made filename-safe.
/// The service uses the id as the cache file name, and a label is not unique.
/// Playing the same path again resumes it; a different path replaces it.
///
/// Requires:
///   - [service] is null in production, which resolves the registered service
///
/// Ensures:
///   - the returned function plays the audio the [url] names under [title]
///   - [url] is a bare server path; a link with a `path` query also works
PodcastPlay podcastPlayFor( { PodcastPlayerService? service } ) {
  return ( url, title ) {
    final player = service ?? ServiceLocator.instance<PodcastPlayerService>();
    return player.play( audioPathOf( url ), title, id: podcastCacheName( url ) );
  };
}

/// The server path of the audio a card link points at.
///
/// Ensures:
///   - the decoded `path` query value when [url] has one
///   - otherwise [url] unchanged, as a bare server path
String audioPathOf( String url ) {
  final path = Uri.tryParse( url )?.queryParameters[ "path" ];
  return path ?? url;
}

/// The track id and cache file name for the audio at [url], one per server path.
///
/// The service appends `.mp3`, so a trailing `.mp3` is dropped here.
///
/// Ensures:
///   - two different server paths never share a name for the same extension
///   - the name holds only letters, digits, dot, underscore and dash
///   - a path with nothing usable yields "podcast"
String podcastCacheName( String url ) {
  final path = audioPathOf( url ).replaceAll( RegExp( r'\.mp3$' ), "" );
  final name = path.replaceAll( RegExp( r'[^A-Za-z0-9._-]+' ), "-" );
  return name.isEmpty ? "podcast" : name;
}
