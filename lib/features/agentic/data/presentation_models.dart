/// Models for POST /api/presentation-generator/submit.
library;

// ─────────────────────────────────────────────
// Request
// ─────────────────────────────────────────────

/// Request to generate a presentation from a source document.
class PresentationGeneratorRequest {
  /// Path to the source document.
  final String  sourcePath;
  /// Target running time in minutes; null uses the server default.
  final int?    targetDurationMinutes;
  /// Reader level the output targets; null uses the server default.
  final String? audience;
  /// Visual theme of the output; null uses the server default.
  final String? theme;
  /// Model override for tests; null uses the server default.
  final String? contentModel;
  /// True skips the content phases and only re-renders the output.
  final bool    renderOnly;
  /// True asks the server to plan the job without running it.
  final bool    dryRun;
  /// Time to start the job, as an ISO timestamp; null starts it now.
  final String? scheduledAt;
  /// True asks the queue to run this job with nothing else running.
  final bool    monopolize;

  /// Creates a request from its parts.
  const PresentationGeneratorRequest( {
    required this.sourcePath,
    this.targetDurationMinutes,
    this.audience,
    this.theme,
    this.contentModel,
    this.renderOnly   = false,
    this.dryRun       = false,
    this.scheduledAt,
    this.monopolize   = false,
  } );

  /// Spoken-command text that routes a `/api/v2/submit` call to this job.
  ///
  /// The submit args send `source_path` under the contract key `source`.
  static const submitCommand = 'agent router go to presentation generator';
  /// Builds the `args` map of the `/api/v2/submit` body, without queue directives.
  Map<String, dynamic> toSubmitArgs() => {
    'source'                                                 : sourcePath,
    if ( targetDurationMinutes != null ) 'target_duration_minutes' : targetDurationMinutes,
    if ( audience != null              ) 'audience'                : audience,
    if ( theme != null                 ) 'theme'                   : theme,
    if ( contentModel != null          ) 'content_model'           : contentModel,
    if ( renderOnly                    ) 'render_only'             : renderOnly,
    if ( dryRun                        ) 'dry_run'                 : dryRun,
  };

  /// Builds the JSON body of this job's own submit endpoint.
  Map<String, dynamic> toJson() => {
    'source_path'                                    : sourcePath,
    if ( targetDurationMinutes != null ) 'target_duration_minutes' : targetDurationMinutes,
    if ( audience != null              ) 'audience'                : audience,
    if ( theme != null                 ) 'theme'                   : theme,
    if ( contentModel != null          ) 'content_model'           : contentModel,
    if ( renderOnly                    ) 'render_only'             : renderOnly,
    if ( dryRun                        ) 'dry_run'                 : dryRun,
    if ( scheduledAt != null           ) 'scheduled_at'            : scheduledAt,
    if ( monopolize                    ) 'monopolize'              : monopolize,
  };
}
