/// Models for POST /api/bug-fix-expediter/submit.
///
/// The job detail screen opens the form for a dead job with the dead job id filled in.
library;

// ─────────────────────────────────────────────
// Request
// ─────────────────────────────────────────────

/// Request to start a job that fixes the bug behind a dead job.
class BugFixExpediterRequest {
  /// Id hash of the failed job to fix.
  final String  deadJobId;
  /// Extra hints for the fixer; null for none.
  final String? extraContext;
  /// True asks the server to plan the job without running it.
  final bool    dryRun;
  /// Socket id the server pushes progress to; null for none.
  final String? websocketId;
  /// Time to start the job, as an ISO timestamp; null starts it now.
  final String? scheduledAt;
  /// True asks the queue to run this job with nothing else running.
  final bool    monopolize;

  /// Creates a request from its parts.
  const BugFixExpediterRequest( {
    required this.deadJobId,
    this.extraContext,
    this.dryRun      = false,
    this.websocketId,
    this.scheduledAt,
    this.monopolize  = false,
  } );

  /// Spoken-command text that routes a `/api/v2/submit` call to this job.
  static const submitCommand = 'agent router go to bug fix expediter';
  /// Builds the `args` map of the `/api/v2/submit` body, without queue directives.
  Map<String, dynamic> toSubmitArgs() => {
    'dead_job_id'                          : deadJobId,
    if ( extraContext != null ) 'extra_context' : extraContext,
    if ( dryRun               ) 'dry_run'       : dryRun,
  };

  /// Builds the JSON body of this job's own submit endpoint.
  Map<String, dynamic> toJson() => {
    'dead_job_id'                          : deadJobId,
    if ( extraContext != null ) 'extra_context' : extraContext,
    if ( dryRun               ) 'dry_run'       : dryRun,
    if ( websocketId != null  ) 'websocket_id'  : websocketId,
    if ( scheduledAt != null  ) 'scheduled_at'  : scheduledAt,
    if ( monopolize           ) 'monopolize'    : monopolize,
  };
}
