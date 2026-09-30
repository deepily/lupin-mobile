/// Models for POST /api/deep-research/submit and GET /api/deep-research/report.
library;

T? _as<T>( dynamic v ) => v is T ? v : null;

// ─────────────────────────────────────────────
// Request
// ─────────────────────────────────────────────

class DeepResearchRequest {
  final String  query;
  final double? budget;
  final String? websocketId;
  final String? leadModel;
  final bool    dryRun;
  final String? audience;       // beginner | general | expert | academic
  final String? audienceContext;
  final String? scheduledAt;
  final bool    monopolize;

  const DeepResearchRequest( {
    required this.query,
    this.budget,
    this.websocketId,
    this.leadModel,
    this.dryRun       = false,
    this.audience,
    this.audienceContext,
    this.scheduledAt,
    this.monopolize   = false,
  } );

  /// v2 wave 2 — the `/api/v2/submit` spelling of this door (held until the
  /// server side merges; see src/rnd/2026.08.21-v2-cutover-wave-2-readiness.md).
  /// `scheduledAt` / `monopolize` are QUEUE DIRECTIVES and ride top-level on
  /// `SubmitRequest`, never inside `args`. `lead_model` is carried but the
  /// factory on b12174fc does not read it for deep research.
  static const submitCommand = 'agent router go to deep research';
  Map<String, dynamic> toSubmitArgs() => {
    'query'                            : query,
    if ( budget != null          ) 'budget'           : budget,
    if ( leadModel != null       ) 'lead_model'       : leadModel,
    if ( dryRun                  ) 'dry_run'          : dryRun,
    if ( audience != null        ) 'audience'         : audience,
    if ( audienceContext != null ) 'audience_context' : audienceContext,
  };

  Map<String, dynamic> toJson() => {
    'query'                            : query,
    if ( budget != null          ) 'budget'           : budget,
    if ( websocketId != null     ) 'websocket_id'     : websocketId,
    if ( leadModel != null       ) 'lead_model'       : leadModel,
    if ( dryRun                  ) 'dry_run'          : dryRun,
    if ( audience != null        ) 'audience'         : audience,
    if ( audienceContext != null ) 'audience_context' : audienceContext,
    if ( scheduledAt != null     ) 'scheduled_at'     : scheduledAt,
    if ( monopolize              ) 'monopolize'       : monopolize,
  };
}

// ─────────────────────────────────────────────
// Report response
// ─────────────────────────────────────────────

/// Fetched markdown report from GET /api/deep-research/report?job_id=...
class DeepResearchReport {
  final String  jobId;
  final String  markdownText;
  final String? title;
  final String? createdAt;

  const DeepResearchReport( {
    required this.jobId,
    required this.markdownText,
    this.title,
    this.createdAt,
  } );

  factory DeepResearchReport.fromJson( Map<String, dynamic> j ) =>
      DeepResearchReport(
        jobId        : ( j[ 'job_id' ] as String? ) ?? '',
        markdownText : ( j[ 'report' ] as String? ) ?? ( j[ 'content' ] as String? ) ?? '',
        title        : _as<String>( j[ 'title' ] ),
        createdAt    : _as<String>( j[ 'created_at' ] ),
      );
}
