/// The two answers the doc viewer's podcast button reads from the server.
///
/// They match `GET /api/podcast-proxy/from-viewer/check` and `POST /api/podcast-proxy/from-viewer`.
/// The classes import neither Flutter nor IO, so they run without a widget harness.
library;

/// What the server says about a file it will accept for a podcast.
class DocPodcastFacts {
  /// The file's name, as the server measured it.
  final String name;

  /// The file's size in bytes.
  final int    size;

  /// Creates the facts of one acceptable file.
  const DocPodcastFacts( { required this.name, required this.size } );

  /// Parses the check's `{ ok, name, size }` body.
  ///
  /// Requires:
  ///   - [json] carries a string `name`; a missing or non-numeric `size` reads as 0
  factory DocPodcastFacts.fromJson( Map<String, dynamic> json ) => DocPodcastFacts(
    name : json[ "name" ] as String,
    size : ( json[ "size" ] as num? )?.toInt() ?? 0,
  );
}

/// The job a podcast click started, or the earlier job the same click already started.
class DocPodcastStarted {
  /// The queue job id.
  final String jobId;

  /// True when the server answered 409 `spent`: this file's bytes already have a job.
  final bool   alreadyStarted;

  /// Creates a start result.
  const DocPodcastStarted( { required this.jobId, this.alreadyStarted = false } );
}

/// The sentence for a podcast refusal, from the server's `{ detail: { code, message } }`.
///
/// Ensures:
///   - the server's own message when it sent one
///   - otherwise "Podcast failed (HTTP <status>)"
String podcastRefusalText( int status, Object? body ) {
  final detail = body is Map ? body[ "detail" ] : null;
  if ( detail is Map && detail[ "message" ] is String && ( detail[ "message" ] as String ).isNotEmpty ) {
    return detail[ "message" ] as String;
  }
  return "Podcast failed (HTTP $status)";
}
