import 'package:flutter/foundation.dart';

import '../../services/audio/podcast_cache.dart';
import '../../services/audio/podcast_link.dart';
import '../notifications/presentation/podcast_done_actions.dart';
import 'podcast_play.dart';

/// Downloads the podcasts a done card names, in the background, but only on Wi-Fi.
///
/// Mobile data is never spent here: on a metered or missing link it does nothing, and the
/// listener's own Play asks first.
class PodcastPrefetcher {
  final PodcastCache Function()        _cacheFactory;
  final Future<PodcastLink> Function() _linkProbe;

  /// Creates the prefetcher; both collaborators are looked up on first use.
  PodcastPrefetcher( {
    required PodcastCache Function()        cacheFactory,
    required Future<PodcastLink> Function() linkProbe,
  } ) : _cacheFactory = cacheFactory,
        _linkProbe    = linkProbe;

  /// Downloads every audio file linked in [abstractText] that is not on the phone yet.
  ///
  /// Requires:
  ///   - [abstractText] may be null, empty or hold no audio link
  ///
  /// Ensures:
  ///   - returns how many files finished downloading
  ///   - downloads only when the link is unmetered
  ///   - never throws; a failed download is skipped and the listener's Play retries it
  Future<int> prefetch( String? abstractText ) async {
    final audio = parsePodcastAudio( abstractText );
    if ( audio.isEmpty ) return 0;
    if ( await _linkProbe() != PodcastLink.unmetered ) return 0;
    final cache = _cacheFactory();
    var   done  = 0;
    for ( final item in audio ) {
      try {
        if ( await cache.lookup( podcastCacheName( item.url ) ) != null ) continue;
        await cache.fetch( audioPathOf( item.url ), podcastCacheName( item.url ) );
        done++;
      } catch ( e ) {
        debugPrint( "[PodcastPrefetcher] ${item.url} failed: $e" );
      }
    }
    return done;
  }
}
