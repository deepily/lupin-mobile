/// Models for POST /api/podcast-generator/submit.
library;

// ─────────────────────────────────────────────
// Request
// ─────────────────────────────────────────────

class PodcastGeneratorRequest {
  final String       researchSource;   // path to source doc or description
  final List<String> targetLanguages;
  final int?         maxSegments;
  final bool         dryRun;
  final String?      scheduledAt;
  final bool         monopolize;

  const PodcastGeneratorRequest( {
    required this.researchSource,
    this.targetLanguages = const [],
    this.maxSegments,
    this.dryRun          = false,
    this.scheduledAt,
    this.monopolize      = false,
  } );

  Map<String, dynamic> toJson() => {
    'research_source'                          : researchSource,
    if ( targetLanguages.isNotEmpty ) 'target_languages' : targetLanguages,
    if ( maxSegments != null        ) 'max_segments'     : maxSegments,
    if ( dryRun                     ) 'dry_run'          : dryRun,
    if ( scheduledAt != null        ) 'scheduled_at'     : scheduledAt,
    if ( monopolize                 ) 'monopolize'       : monopolize,
  };
}
