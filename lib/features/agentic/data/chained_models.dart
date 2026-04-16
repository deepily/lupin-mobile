/// Models for chained agentic jobs:
///   POST /api/deep-research-to-podcast/submit       (job_id prefix: rp-)
///   POST /api/deep-research-to-presentation/submit  (job_id prefix: rx-)
library;

// ─────────────────────────────────────────────
// Research → Podcast
// ─────────────────────────────────────────────

class ResearchToPodcastRequest {
  final String       query;
  final double?      budget;
  final List<String> targetLanguages;
  final int?         maxSegments;
  final bool         dryRun;

  const ResearchToPodcastRequest( {
    required this.query,
    this.budget,
    this.targetLanguages = const [],
    this.maxSegments,
    this.dryRun          = false,
  } );

  Map<String, dynamic> toJson() => {
    'query'                                          : query,
    if ( budget != null                ) 'budget'           : budget,
    if ( targetLanguages.isNotEmpty    ) 'target_languages' : targetLanguages,
    if ( maxSegments != null           ) 'max_segments'     : maxSegments,
    if ( dryRun                        ) 'dry_run'          : dryRun,
  };
}

// ─────────────────────────────────────────────
// Research → Presentation
// ─────────────────────────────────────────────

class ResearchToPresentationRequest {
  final String  query;
  final double? budget;
  final int?    targetDurationMinutes;
  final String? theme;
  final String? audience;
  final String? audienceContext;
  final String? leadModel;
  final bool    dryRun;

  const ResearchToPresentationRequest( {
    required this.query,
    this.budget,
    this.targetDurationMinutes,
    this.theme,
    this.audience,
    this.audienceContext,
    this.leadModel,
    this.dryRun = false,
  } );

  Map<String, dynamic> toJson() => {
    'query'                                              : query,
    if ( budget != null                  ) 'budget'                   : budget,
    if ( targetDurationMinutes != null   ) 'target_duration_minutes'  : targetDurationMinutes,
    if ( theme != null                   ) 'theme'                    : theme,
    if ( audience != null                ) 'audience'                 : audience,
    if ( audienceContext != null         ) 'audience_context'         : audienceContext,
    if ( leadModel != null               ) 'lead_model'               : leadModel,
    if ( dryRun                          ) 'dry_run'                  : dryRun,
  };
}
