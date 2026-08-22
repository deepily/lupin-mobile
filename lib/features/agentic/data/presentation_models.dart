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

  /// v2 wave 2 — `/api/v2/submit` args. `source_path` → `source` (the contract
  /// key; the alias is accepted too, the canonical one is sent).
  static const submitCommand = 'agent router go to presentation generator';
  Map<String, dynamic> toSubmitArgs() => {
    'source'                                                 : sourcePath,
    if ( targetDurationMinutes != null ) 'target_duration_minutes' : targetDurationMinutes,
    if ( audience != null              ) 'audience'                : audience,
    if ( theme != null                 ) 'theme'                   : theme,
    if ( contentModel != null          ) 'content_model'           : contentModel,
    if ( renderOnly                    ) 'render_only'             : renderOnly,
    if ( dryRun                        ) 'dry_run'                 : dryRun,
  };

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
