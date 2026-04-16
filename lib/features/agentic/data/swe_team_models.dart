/// Models for POST /api/swe-team/submit.
library;

// ─────────────────────────────────────────────
// Request
// ─────────────────────────────────────────────

class SweTeamRequest {
  final String  task;
  final double? budget;
  final int?    timeout;         // wall-clock seconds
  final String? trustMode;       // disabled | shadow | suggest | active
  final String? leadModel;
  final String? workerModel;
  final String? websocketId;
  final bool    dryRun;
  final String? scheduledAt;
  final bool    monopolize;

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
