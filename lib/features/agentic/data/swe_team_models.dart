/// Models for POST /api/swe-team/submit.
library;

// ─────────────────────────────────────────────
// Request
// ─────────────────────────────────────────────

/// Request to start a software-engineering team job on a task.
class SweTeamRequest {
  /// Description of the work the team should do.
  final String  task;
  /// Spending cap in dollars; null uses the server default.
  final double? budget;
  /// Wall-clock limit in seconds; null uses the server default.
  final int?    timeout;
  /// Autonomy level: disabled, shadow, suggest or active; null uses the server default.
  final String? trustMode;
  /// Model the lead agent uses; null uses the server default.
  final String? leadModel;
  /// Model the worker agents use; null uses the server default.
  final String? workerModel;
  /// Socket id the server pushes progress to; null for none.
  final String? websocketId;
  /// True asks the server to plan the job without running it.
  final bool    dryRun;
  /// Time to start the job, as an ISO timestamp; null starts it now.
  final String? scheduledAt;
  /// True asks the queue to run this job with nothing else running.
  final bool    monopolize;

  /// Creates a request from its parts.
  const SweTeamRequest( {
    required this.task,
    this.budget,
    this.timeout,
    this.trustMode,
    this.leadModel,
    this.workerModel,
    this.websocketId,
    this.dryRun      = false,
    this.scheduledAt,
    this.monopolize  = false,
  } );

  /// Spoken-command text that routes a `/api/v2/submit` call to this job.
  static const submitCommand = 'agent router go to swe team';
  /// Builds the `args` map of the `/api/v2/submit` body, without queue directives.
  Map<String, dynamic> toSubmitArgs() => {
    'task'                                 : task,
    if ( budget != null       ) 'budget'        : budget,
    if ( timeout != null      ) 'timeout'       : timeout,
    if ( trustMode != null    ) 'trust_mode'    : trustMode,
    if ( leadModel != null    ) 'lead_model'    : leadModel,
    if ( workerModel != null  ) 'worker_model'  : workerModel,
    if ( dryRun               ) 'dry_run'       : dryRun,
  };

  /// Builds the JSON body of this job's own submit endpoint.
  Map<String, dynamic> toJson() => {
    'task'                                 : task,
    if ( budget != null       ) 'budget'        : budget,
    if ( timeout != null      ) 'timeout'       : timeout,
    if ( trustMode != null    ) 'trust_mode'    : trustMode,
    if ( leadModel != null    ) 'lead_model'    : leadModel,
    if ( workerModel != null  ) 'worker_model'  : workerModel,
    if ( websocketId != null  ) 'websocket_id'  : websocketId,
    if ( dryRun               ) 'dry_run'       : dryRun,
    if ( scheduledAt != null  ) 'scheduled_at'  : scheduledAt,
    if ( monopolize           ) 'monopolize'    : monopolize,
  };
}
