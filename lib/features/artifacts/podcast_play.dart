import 'package:flutter/material.dart';

import 'audio_artifact_player.dart';

/// Plays a podcast from its audio [url], showing [title].
///
/// This is the shape the app-wide player service will expose.
/// Repointing is then one line.
typedef PodcastPlay = Future<void> Function( String url, String title );

/// The one place a podcast card's Play goes.
/// Today it opens [AudioArtifactPlayer] as a page.
///
/// To repoint it, make the returned closure call the app-wide player service's `play( url, title )`.
/// No card needs to change.
///
/// Requires:
///   - [context] stays mounted until the returned function is called
///
/// Ensures:
///   - the returned function pushes the player page for the audio the [url] names
///   - [url] is a bare server path; a link with a `path` query also works
PodcastPlay podcastPlayFor( BuildContext context ) {
  final navigator = Navigator.of( context );
  return ( url, title ) async {
    await navigator.push( MaterialPageRoute<void>(
      builder: ( _ ) => AudioArtifactPlayer( jobId: podcastCacheName( url ), audioPath: audioPathOf( url ) ),
    ) );
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

/// The cache file name for the audio at [url], one per server path.
///
/// The player appends `.mp3`, so a trailing `.mp3` is dropped here.
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
