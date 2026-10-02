/// Models for POST /api/podcast-generator/submit.
library;

// ─────────────────────────────────────────────
// Request
// ─────────────────────────────────────────────

/// Request to generate a podcast from a research source.
class PodcastGeneratorRequest {
  /// Path to a source document, or a plain description of the topic.
  final String       researchSource;
  /// Languages to produce; empty means the server default.
  final List<String> targetLanguages;
  /// Cap on podcast segments; null uses the server default.
  final int?         maxSegments;
  /// True asks the server to plan the job without running it.
  final bool         dryRun;
  /// Time to start the job, as an ISO timestamp; null starts it now.
  final String?      scheduledAt;
  /// True asks the queue to run this job with nothing else running.
  final bool         monopolize;

  /// Creates a request from its parts.
  const PodcastGeneratorRequest( {
    required this.researchSource,
    this.targetLanguages = const [],
    this.maxSegments,
    this.dryRun          = false,
    this.scheduledAt,
    this.monopolize      = false,
  } );

  /// Spoken-command text that routes a `/api/v2/submit` call to this job.
  ///
  /// The submit args rename `research_source` to `research` and `target_languages` to `languages`.
  static const submitCommand = 'agent router go to podcast generator';
  /// Builds the `args` map of the `/api/v2/submit` body, without queue directives.
  Map<String, dynamic> toSubmitArgs() => {
    'research'                                       : researchSource,
    if ( targetLanguages.isNotEmpty ) 'languages'    : targetLanguages,
    if ( maxSegments != null        ) 'max_segments' : maxSegments,
    if ( dryRun                     ) 'dry_run'      : dryRun,
  };

  /// Builds the JSON body of this job's own submit endpoint.
  Map<String, dynamic> toJson() => {
    'research_source'                          : researchSource,
    if ( targetLanguages.isNotEmpty ) 'target_languages' : targetLanguages,
    if ( maxSegments != null        ) 'max_segments'     : maxSegments,
    if ( dryRun                     ) 'dry_run'          : dryRun,
    if ( scheduledAt != null        ) 'scheduled_at'     : scheduledAt,
    if ( monopolize                 ) 'monopolize'       : monopolize,
  };
}
