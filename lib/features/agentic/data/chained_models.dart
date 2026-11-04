/// Models for the chained jobs that run deep research and then build an artifact.
///
/// The research-to-podcast endpoint creates ids with prefix rp-, the presentation one with rx-.
library;

// ─────────────────────────────────────────────
// Research → Podcast
// ─────────────────────────────────────────────

/// Request to research a query and turn the result into a podcast.
class ResearchToPodcastRequest {
  /// Research question the job answers first.
  final String       query;
  /// Spending cap in dollars; null uses the server default.
  final double?      budget;
  /// Languages to produce; empty means the server default.
  final List<String> targetLanguages;
  /// Cap on podcast segments; null uses the server default.
  final int?         maxSegments;
  /// True asks the server to plan the job without running it.
  final bool         dryRun;

  /// Creates a request from its parts.
  const ResearchToPodcastRequest( {
    required this.query,
    this.budget,
    this.targetLanguages = const [],
    this.maxSegments,
    this.dryRun          = false,
  } );

  /// Spoken-command text that routes a `/api/v2/submit` call to this job.
  ///
  /// The submit args rename `target_languages` to `languages`; `max_segments` is sent but unread.
  static const submitCommand = 'agent router go to research to podcast';
  /// Builds the `args` map of the `/api/v2/submit` body, without queue directives.
  Map<String, dynamic> toSubmitArgs() => {
    'query'                                          : query,
    if ( budget != null                ) 'budget'       : budget,
    if ( targetLanguages.isNotEmpty    ) 'languages'    : targetLanguages,
    if ( maxSegments != null           ) 'max_segments' : maxSegments,
    if ( dryRun                        ) 'dry_run'      : dryRun,
  };

  /// Builds the JSON body of this job's own submit endpoint.
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

/// Request to research a query and turn the result into a presentation.
class ResearchToPresentationRequest {
  /// Research question the job answers first.
  final String  query;
  /// Spending cap in dollars; null uses the server default.
  final double? budget;
  /// Target running time in minutes; null uses the server default.
  final int?    targetDurationMinutes;
  /// Visual theme of the output; null uses the server default.
  final String? theme;
  /// Reader level the output targets; null uses the server default.
  final String? audience;
  /// Free-text detail about the audience; null for none.
  final String? audienceContext;
  /// Model the lead agent uses; null uses the server default.
  final String? leadModel;
  /// True asks the server to plan the job without running it.
  final bool    dryRun;

  /// Creates a request from its parts.
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

  /// Spoken-command text that routes a `/api/v2/submit` call to this job.
  static const submitCommand = 'agent router go to research to presentation';
  /// Builds the `args` map of the `/api/v2/submit` body, without queue directives.
  Map<String, dynamic> toSubmitArgs() => {
    'query'                                              : query,
    if ( budget != null                  ) 'budget'                   : budget,
    if ( targetDurationMinutes != null   ) 'target_duration_minutes'  : targetDurationMinutes,
    if ( theme != null                   ) 'theme'                    : theme,
    if ( audience != null                ) 'audience'                 : audience,
    if ( audienceContext != null         ) 'audience_context'         : audienceContext,
    if ( leadModel != null               ) 'lead_model'               : leadModel,
    if ( dryRun                          ) 'dry_run'                  : dryRun,
  };

  /// Builds the JSON body of this job's own submit endpoint.
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
