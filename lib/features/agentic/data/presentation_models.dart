/// Models for POST /api/presentation-generator/submit.
library;

// ─────────────────────────────────────────────
// Request
// ─────────────────────────────────────────────

class PresentationGeneratorRequest {
  final String  sourcePath;
  final int?    targetDurationMinutes;
  final String? audience;
  final String? theme;
  final String? contentModel;   // model override for tests
  final bool    renderOnly;     // skip phases 1-5, re-render only
  final bool    dryRun;
  final String? scheduledAt;
  final bool    monopolize;

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
