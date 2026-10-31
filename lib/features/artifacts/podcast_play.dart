import 'package:flutter/widgets.dart';

import '../../core/di/service_locator.dart';
import '../../services/audio/podcast_player_service.dart';
import 'podcast_download_sheet.dart';

/// Plays a podcast from its audio [url], showing [title].
///
/// This is the shape the app-wide player service exposes.
typedef PodcastPlay = Future<void> Function( String url, String title );

/// The one place a podcast card's Play goes: the app-wide [PodcastPlayerService].
///
/// The track id is the audio's server path, percent-encoded to be filename-safe.
/// The service uses the id as the cache file name, and a label is not unique.
/// Playing the same path again resumes it; a different path replaces it.
///
/// Requires:
///   - [service] is null in production, which resolves the registered service
///   - [context] is the screen that asks; null means a download on mobile data is declined, not asked
///
/// Ensures:
///   - the returned function plays the audio the [url] names under [title]
///   - [url] is a bare server path; a link with a `path` query also works
///   - audio that is not downloaded and would need mobile data asks first in an in-app sheet
PodcastPlay podcastPlayFor( { PodcastPlayerService? service, BuildContext? context } ) {
  return ( url, title ) {
    final player = service ?? ServiceLocator.instance<PodcastPlayerService>();
    return player.play(
      audioPathOf( url ), title,
      id               : podcastCacheName( url ),
      confirmMobileData: context == null ? null : () async => context.mounted && await showPodcastDataSheet( context, title ),
    );
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
/// The service appends `.mp3` to it.
///
/// Ensures:
///   - two different server paths never share a name
///   - the name is the percent-encoded path, so it holds no slash
///   - a path with nothing in it yields "podcast"
String podcastCacheName( String url ) {
  final name = Uri.encodeComponent( audioPathOf( url ) );
  return name.isEmpty ? "podcast" : name;
}
