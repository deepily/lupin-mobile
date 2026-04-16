/// Models for POST /api/bug-fix-expediter/submit.
///
/// Entry point: JobDetailScreen on a dead job — deadJobId is pre-filled.
library;

// ─────────────────────────────────────────────
// Request
// ─────────────────────────────────────────────

class BugFixExpediterRequest {
  final String  deadJobId;      // id_hash of the failed job
  final String? extraContext;
  final bool    dryRun;
  final String? websocketId;
  final String? scheduledAt;
  final bool    monopolize;

  const BugFixExpediterRequest( {
    required this.deadJobId,
    this.extraContext,
    this.dryRun      = false,
    this.websocketId,
    this.scheduledAt,
    this.monopolize  = false,
  } );

  Map<String, dynamic> toJson() => {
    'dead_job_id'                          : deadJobId,
    if ( extraContext != null ) 'extra_context' : extraContext,
    if ( dryRun               ) 'dry_run'       : dryRun,
    if ( websocketId != null  ) 'websocket_id'  : websocketId,
    if ( scheduledAt != null  ) 'scheduled_at'  : scheduledAt,
    if ( monopolize           ) 'monopolize'    : monopolize,
  };
}
