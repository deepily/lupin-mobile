/// Data models for the Lupin CJ Flow queue API (14 endpoints).
///
/// Field names match backend JSON exactly per
/// `cosa/rest/routers/queues.py` and `cosa/rest/job_persistence.py`.
library;

DateTime? _parseDt( dynamic v ) =>
    v == null ? null : DateTime.tryParse( v.toString() );

T? _as<T>( dynamic v ) => v is T ? v : null;

// ─────────────────────────────────────────────
// Submission requests
// ─────────────────────────────────────────────

/// Request body for POST /api/v2/ask — the CJ Flow v2 question door.
///
/// Replaces POST /api/push (410 tombstone since 2026-08-21; REMOVE BY 2026-12-31).
/// Field names match `cosa/rest/routers/v2_ask.py::AskRequest`.
class AskRequest {
  final String  question;
  final String? websocketId;
  final bool    speak;        // dispatch the answer as a TTS notification
  final bool    interactive;  // park + resume on a missing argument (else needs_input)

  const AskRequest( {
    required this.question,
    this.websocketId,
    this.speak       = true,
    this.interactive = true,
  } );

  Map<String, dynamic> toJson() => {
    'question'     : question,
    if ( websocketId != null ) 'websocket_id' : websocketId,
    'speak'        : speak,
    'interactive'  : interactive,
  };
}

/// Request body for POST /api/v2/submit — work whose COMMAND is already
/// decided (the door beside `ask`; Rick's two-door ruling, 2026-08-21). The
/// caller names the routing command and hands over every argument it needs;
/// the server skips routing + extraction. `question` is optional and only
/// carried for the record; a submit NEVER parks — missing args come back as
/// `status == 'needs_input'` with `argsMissing` filled in. Wave 2 of the
/// v2 cutover routes the eleven submit-shaped doors through this one body.
/// `scheduledAt` / `monopolize` ride TOP-LEVEL, not inside `args`: `args` is
/// contract-validated against `JOB_ARG_CONTRACTS` and these two are queue
/// directives, not agent arguments (Rachel's recommendation 2026-08-21; the
/// server-side ruling is pending — see
/// `src/rnd/2026.08.21-v2-cutover-wave-2-readiness.md` § Rachel's answers).
/// They are serialized ONLY when set, so bodies stay byte-identical until the
/// server accepts them.
class SubmitRequest {
  final String               command;
  final Map<String, dynamic> args;
  final String?              question;
  final String?              websocketId;
  final bool                 speak;
  final String?              scheduledAt;
  final bool?                monopolize;

  const SubmitRequest( {
    required this.command,
    this.args        = const {},
    this.question,
    this.websocketId,
    this.speak       = true,
    this.scheduledAt,
    this.monopolize,
  } );

  Map<String, dynamic> toJson() => {
    'command'      : command,
    'args'         : args,
    if ( question    != null ) 'question'     : question,
    if ( websocketId != null ) 'websocket_id' : websocketId,
    'speak'        : speak,
    if ( scheduledAt != null ) 'scheduled_at' : scheduledAt,
    if ( monopolize  != null ) 'monopolize'   : monopolize,
  };
}

/// Request body for POST /api/push-agentic (agentic job, bypasses expediter).
class PushAgenticRequest {
  final String               routingCommand;
  final String               websocketId;
  final Map<String, dynamic> args;
  final String?              question;
  final String?              scheduledAt;
  final bool                 monopolize;

  const PushAgenticRequest( {
    required this.routingCommand,
    required this.websocketId,
    this.args       = const {},
    this.question,
    this.scheduledAt,
    this.monopolize = false,
  } );

  /// v2 wave 2 — the same submission as a `SubmitRequest` (door 10 is 1:1:
  /// `routing_command` → `command`; `args`/`question` carry over verbatim; the
  /// queue directives stay top-level).
  SubmitRequest toSubmitRequest( { bool speak = true } ) => SubmitRequest(
    command     : routingCommand,
    args        : args,
    question    : question,
    websocketId : websocketId,
    speak       : speak,
    scheduledAt : scheduledAt,
    monopolize  : monopolize ? true : null,
  );

  Map<String, dynamic> toJson() => {
    'routing_command' : routingCommand,
    'websocket_id'    : websocketId,
    if ( args.isNotEmpty ) 'args' : args,
    if ( question != null ) 'question' : question,
    if ( scheduledAt != null ) 'scheduled_at' : scheduledAt,
    if ( monopolize ) 'monopolize' : monopolize,
  };
}

// ─────────────────────────────────────────────
// Submission response
// ─────────────────────────────────────────────

/// Response from POST /api/push-agentic (queue-and-poll).
/// (POST /api/push is gone — see [AskResponse] for the synchronous v2 reply.)
class PushJobResponse {
  final String  status;
  final String  websocketId;
  final String  userId;
  final String? jobId;
  final String? result;
  final String? routingCommand;  // agentic only

  const PushJobResponse( {
    required this.status,
    required this.websocketId,
    required this.userId,
    this.jobId,
    this.result,
    this.routingCommand,
  } );

  /// v2 wave 2: door 10 (`/api/push-agentic`) now rides `/api/v2/submit`; the
  /// synchronous body is adapted back to the queue-and-poll shape the dashboard
  /// already renders ("Job queued: <id>"). `user_id` is not in the v2 body.
  factory PushJobResponse.fromAsk( AskResponse ask, { required String websocketId } ) => PushJobResponse(
    status         : ask.status,
    websocketId    : websocketId,
    userId         : '',
    jobId          : ask.jobId,
    result         : ask.answer,
    routingCommand : ask.command,
  );

  factory PushJobResponse.fromJson( Map<String, dynamic> j ) => PushJobResponse(
    status         : j[ 'status' ]       as String,
    websocketId    : j[ 'websocket_id' ] as String,
    userId         : j[ 'user_id' ]      as String,
    jobId          : _as<String>( j[ 'job_id' ] ),
    result         : _as<String>( j[ 'result' ] ),
    routingCommand : _as<String>( j[ 'routing_command' ] ),
  );
}

// ─────────────────────────────────────────────
// v2 ask response (§8 result dict)
// ─────────────────────────────────────────────

/// Response from POST /api/v2/ask — SYNCHRONOUS: the answer (or the first
/// clarifying question) comes back in the body; nothing is queued for polling.
/// Field names match `cosa/rest/routers/v2_ask.py::AskResponse`.
class AskResponse {
  final String        path;          // replay | agent | needs_input | receptionist
  final String        status;        // done | parked | needs_input | failed
  final String        routeReason;
  final String?       answer;
  final String?       answerRaw;
  final String?       command;
  final List<String>  argsKnown;
  final List<String>  argsMissing;
  final String?       pendingId;     // set when interactive + needs_input (resume with /api/v2/resume)
  final String?       jobId;
  final String?       snapshotId;
  final double?       similarity;
  final bool          wroteSnapshot;
  final bool          cacheHit;
  final bool          spoke;
  final Map<String, dynamic> timingsMs;
  final String        traceId;
  final String?       error;

  const AskResponse( {
    required this.path,
    required this.status,
    required this.routeReason,
    required this.traceId,
    this.answer,
    this.answerRaw,
    this.command,
    this.argsKnown     = const [],
    this.argsMissing   = const [],
    this.pendingId,
    this.jobId,
    this.snapshotId,
    this.similarity,
    this.wroteSnapshot = false,
    this.cacheHit      = false,
    this.spoke         = false,
    this.timingsMs     = const {},
    this.error,
  } );

  bool get isDone     => status == 'done';
  bool get needsInput => status == 'needs_input' || status == 'parked';
  bool get isFailed   => status == 'failed';

  /// One-line summary for snackbars / toasts.
  String get summary {
    if ( needsInput ) return answer ?? 'Needs input: ${argsMissing.join( ", " )}';
    if ( isFailed )   return error ?? 'Request failed';
    return answer ?? 'Done ($path)';
  }

  static List<String> _strList( dynamic v ) =>
      v is List ? v.map( ( e ) => e.toString() ).toList() : const [];

  factory AskResponse.fromJson( Map<String, dynamic> j ) => AskResponse(
    path          : j[ 'path' ]         as String,
    status        : j[ 'status' ]       as String,
    routeReason   : _as<String>( j[ 'route_reason' ] ) ?? '',
    traceId       : _as<String>( j[ 'trace_id' ] ) ?? '',
    answer        : _as<String>( j[ 'answer' ] ),
    answerRaw     : _as<String>( j[ 'answer_raw' ] ),
    command       : _as<String>( j[ 'command' ] ),
    argsKnown     : _strList( j[ 'args_known' ] ),
    argsMissing   : _strList( j[ 'args_missing' ] ),
    pendingId     : _as<String>( j[ 'pending_id' ] ),
    jobId         : _as<String>( j[ 'job_id' ] ),
    snapshotId    : _as<String>( j[ 'snapshot_id' ] ),
    similarity    : ( j[ 'similarity' ] as num? )?.toDouble(),
    wroteSnapshot : _as<bool>( j[ 'wrote_snapshot' ] ) ?? false,
    cacheHit      : _as<bool>( j[ 'cache_hit' ] ) ?? false,
    spoke         : _as<bool>( j[ 'spoke' ] ) ?? false,
    timingsMs     : _as<Map<String, dynamic>>( j[ 'timings_ms' ] ) ?? const {},
    error         : _as<String>( j[ 'error' ] ),
  );
}

// ─────────────────────────────────────────────
// Queue snapshot
// ─────────────────────────────────────────────

/// A single job summary entry in any queue (todo / run / done / dead).
/// Backend returns these under the `{queue_name}_jobs_metadata` key.
class JobSummary {
  final String   jobId;        // id_hash
  final String?  questionText;
  final String?  timestamp;
  final String?  userId;
  final String?  userEmail;
  final String?  sessionId;
  final String?  agentType;    // job_type
  final String   status;       // queued | running | paused | completed | failed | stalled
  final String?  startedAt;
  final String?  completedAt;
  final String?  error;
  final String?  scheduledAt;
  final bool     monopolize;
  final bool     paused;
  // done/dead only
  final String?  responseText;
  final bool     hasInteractions;
  final bool     isCacheHit;
  final double?  durationSeconds;
  // done artifacts
  final String?  reportPath;
  final String?  pptxPath;
  final String?  yamlPath;
  final String?  abstract;
  final Map<String, dynamic>? costSummary;
  // dead forensics
  final String?  planPath;
  final String?  remediationSnapshotPath;

  const JobSummary( {
    required this.jobId,
    this.questionText,
    this.timestamp,
    this.userId,
    this.userEmail,
    this.sessionId,
    this.agentType,
    required this.status,
    this.startedAt,
    this.completedAt,
    this.error,
    this.scheduledAt,
    this.monopolize           = false,
    this.paused               = false,
    this.responseText,
    this.hasInteractions      = false,
    this.isCacheHit           = false,
    this.durationSeconds,
    this.reportPath,
    this.pptxPath,
    this.yamlPath,
    this.abstract,
    this.costSummary,
    this.planPath,
    this.remediationSnapshotPath,
  } );

  factory JobSummary.fromJson( Map<String, dynamic> j ) => JobSummary(
    jobId                   : j[ 'job_id' ]       as String,
    questionText            : _as<String>( j[ 'question_text' ] ),
    timestamp               : _as<String>( j[ 'timestamp' ] ),
    userId                  : _as<String>( j[ 'user_id' ] ),
    userEmail               : _as<String>( j[ 'user_email' ] ),
    sessionId               : _as<String>( j[ 'session_id' ] ),
    agentType               : _as<String>( j[ 'agent_type' ] ),
    status                  : ( j[ 'status' ] as String? ) ?? 'queued',
    startedAt               : _as<String>( j[ 'started_at' ] ),
    completedAt             : _as<String>( j[ 'completed_at' ] ),
    error                   : _as<String>( j[ 'error' ] ),
    scheduledAt             : _as<String>( j[ 'scheduled_at' ] ),
    monopolize              : ( j[ 'monopolize' ] as bool? ) ?? false,
    paused                  : ( j[ 'paused' ] as bool? ) ?? false,
    responseText            : _as<String>( j[ 'response_text' ] ),
    hasInteractions         : ( j[ 'has_interactions' ] as bool? ) ?? false,
    isCacheHit              : ( j[ 'is_cache_hit' ] as bool? ) ?? false,
    durationSeconds         : ( j[ 'duration_seconds' ] as num? )?.toDouble(),
    reportPath              : _as<String>( j[ 'report_path' ] ),
    pptxPath                : _as<String>( j[ 'pptx_path' ] ),
    yamlPath                : _as<String>( j[ 'yaml_path' ] ),
    abstract                : _as<String>( j[ 'abstract' ] ),
    costSummary             : j[ 'cost_summary' ] as Map<String, dynamic>?,
    planPath                : _as<String>( j[ 'plan_path' ] ),
    remediationSnapshotPath : _as<String>( j[ 'remediation_snapshot_path' ] ),
  );
}

/// Response from GET /api/get-queue/{queue_name}.
class QueueResponse {
  final String         queueName;
  final List<JobSummary> jobs;
  final String         filteredBy;
  final bool           isAdminView;
  final int            totalJobs;

  const QueueResponse( {
    required this.queueName,
    required this.jobs,
    required this.filteredBy,
    required this.isAdminView,
    required this.totalJobs,
  } );

  factory QueueResponse.fromJson( String queueName, Map<String, dynamic> j ) {
    final key  = '${queueName}_jobs_metadata';
    final list = ( j[ key ] as List<dynamic>? ) ?? [];
    return QueueResponse(
      queueName   : queueName,
      jobs        : list.map( ( e ) => JobSummary.fromJson( e as Map<String, dynamic> ) ).toList(),
      filteredBy  : ( j[ 'filtered_by' ] as String? ) ?? '',
      isAdminView : ( j[ 'is_admin_view' ] as bool? ) ?? false,
      totalJobs   : ( j[ 'total_jobs' ] as int? ) ?? 0,
    );
  }
}

// ─────────────────────────────────────────────
// Job history
// ─────────────────────────────────────────────

/// A single job history record from PostgreSQL persistence.
/// Returned by GET /api/job-history and GET /api/job-history/{job_id}.
class JobHistoryEntry {
  final String   idHash;
  final String?  jobType;
  final String?  userId;
  final String?  userEmail;
  final String?  sessionId;
  final String?  routingCommand;
  final String   status;     // pending | running | completed | failed | interrupted | stalled
  final String?  questionText;
  final String?  error;
  final bool     isCacheHit;
  final double?  durationSeconds;
  final String? metadataJson;
  final String?  createdAt;
  final String?  startedAt;
  final String?  completedAt;
  final String?  updatedAt;

  const JobHistoryEntry( {
    required this.idHash,
    this.jobType,
    this.userId,
    this.userEmail,
    this.sessionId,
    this.routingCommand,
    required this.status,
    this.questionText,
    this.error,
    this.isCacheHit    = false,
    this.durationSeconds,
    this.metadataJson,
    this.createdAt,
    this.startedAt,
    this.completedAt,
    this.updatedAt,
  } );

  factory JobHistoryEntry.fromJson( Map<String, dynamic> j ) => JobHistoryEntry(
    idHash          : j[ 'id_hash' ]         as String,
    jobType         : _as<String>( j[ 'job_type' ] ),
    userId          : _as<String>( j[ 'user_id' ] ),
    userEmail       : _as<String>( j[ 'user_email' ] ),
    sessionId       : _as<String>( j[ 'session_id' ] ),
    routingCommand  : _as<String>( j[ 'routing_command' ] ),
    status          : ( j[ 'status' ] as String? ) ?? 'unknown',
    questionText    : _as<String>( j[ 'question_text' ] ),
    error           : _as<String>( j[ 'error' ] ),
    isCacheHit      : ( j[ 'is_cache_hit' ] as bool? ) ?? false,
    durationSeconds : ( j[ 'duration_seconds' ] as num? )?.toDouble(),
    metadataJson    : _as<String>( j[ 'metadata_json' ] ),
    createdAt       : _as<String>( j[ 'created_at' ] ),
    startedAt       : _as<String>( j[ 'started_at' ] ),
    completedAt     : _as<String>( j[ 'completed_at' ] ),
    updatedAt       : _as<String>( j[ 'updated_at' ] ),
  );
}

/// Paginated list response from GET /api/job-history.
class JobHistoryPage {
  final List<JobHistoryEntry> jobs;
  final int                   total;
  final String                filteredBy;
  final int                   limit;
  final int                   offset;

  const JobHistoryPage( {
    required this.jobs,
    required this.total,
    required this.filteredBy,
    required this.limit,
    required this.offset,
  } );

  factory JobHistoryPage.fromJson( Map<String, dynamic> j ) => JobHistoryPage(
    jobs       : ( ( j[ 'jobs' ] as List<dynamic>? ) ?? [] )
        .map( ( e ) => JobHistoryEntry.fromJson( e as Map<String, dynamic> ) )
        .toList(),
    total      : ( j[ 'total' ] as int? ) ?? 0,
    filteredBy : ( j[ 'filtered_by' ] as String? ) ?? '',
    limit      : ( j[ 'limit' ] as int? ) ?? 20,
    offset     : ( j[ 'offset' ] as int? ) ?? 0,
  );
}

// ─────────────────────────────────────────────
// Job interactions
// ─────────────────────────────────────────────

/// A single notification interaction record for a job.
class JobInteraction {
  final String  id;
  final String? type;
  final String  message;
  final String  timestamp;
  final bool    responseRequested;
  final String? responseValue;
  final String? priority;
  final String? abstract;

  const JobInteraction( {
    required this.id,
    this.type,
    required this.message,
    required this.timestamp,
    this.responseRequested = false,
    this.responseValue,
    this.priority,
    this.abstract,
  } );

  factory JobInteraction.fromJson( Map<String, dynamic> j ) => JobInteraction(
    id                : j[ 'id' ]        as String,
    type              : _as<String>( j[ 'type' ] ),
    message           : ( j[ 'message' ] as String? ) ?? '',
    timestamp         : ( j[ 'timestamp' ] as String? ) ?? '',
    responseRequested : ( j[ 'response_requested' ] as bool? ) ?? false,
    responseValue     : _as<String>( j[ 'response_value' ] ),
    priority          : _as<String>( j[ 'priority' ] ),
    abstract          : _as<String>( j[ 'abstract' ] ),
  );
}

/// Full response from GET /api/get-job-interactions/{job_id}.
class JobInteractionsResponse {
  final String              jobId;
  final String?             sessionId;
  final Map<String, dynamic>? jobMetadata;
  final List<JobInteraction>  interactions;
  final int                   interactionCount;

  const JobInteractionsResponse( {
    required this.jobId,
    this.sessionId,
    this.jobMetadata,
    required this.interactions,
    required this.interactionCount,
  } );

  factory JobInteractionsResponse.fromJson( Map<String, dynamic> j ) =>
      JobInteractionsResponse(
        jobId            : j[ 'job_id' ]    as String,
        sessionId        : _as<String>( j[ 'session_id' ] ),
        jobMetadata      : j[ 'job_metadata' ] as Map<String, dynamic>?,
        interactions     : ( ( j[ 'interactions' ] as List<dynamic>? ) ?? [] )
            .map( ( e ) => JobInteraction.fromJson( e as Map<String, dynamic> ) )
            .toList(),
        interactionCount : ( j[ 'interaction_count' ] as int? ) ?? 0,
      );
}

// ─────────────────────────────────────────────
// Simple action responses
// ─────────────────────────────────────────────

/// Response from POST /api/jobs/{job_id}/message.
class MessageDeliveredResponse {
  final String status;
  final String notificationId;
  final String jobId;

  const MessageDeliveredResponse( {
    required this.status,
    required this.notificationId,
    required this.jobId,
  } );

  factory MessageDeliveredResponse.fromJson( Map<String, dynamic> j ) =>
      MessageDeliveredResponse(
        status         : j[ 'status' ]          as String,
        notificationId : j[ 'notification_id' ] as String,
        jobId          : j[ 'job_id' ]          as String,
      );
}

/// Response from POST /api/jobs/{id_hash}/resume-from-checkpoint.
class ResumeCheckpointResponse {
  final String  status;
  final String  resumedJobId;
  final String  originalJobId;
  final int?    resumeFromPhase;
  final String? phaseName;
  final int     resumeCount;

  const ResumeCheckpointResponse( {
    required this.status,
    required this.resumedJobId,
    required this.originalJobId,
    this.resumeFromPhase,
    this.phaseName,
    this.resumeCount = 1,
  } );

  factory ResumeCheckpointResponse.fromJson( Map<String, dynamic> j ) =>
      ResumeCheckpointResponse(
        status          : j[ 'status' ]          as String,
        resumedJobId    : j[ 'resumed_job_id' ]  as String,
        originalJobId   : j[ 'original_job_id' ] as String,
        resumeFromPhase : j[ 'resume_from_phase' ] as int?,
        phaseName       : _as<String>( j[ 'phase_name' ] ),
        resumeCount     : ( j[ 'resume_count' ] as int? ) ?? 1,
      );
}

// ─────────────────────────────────────────────
// Error
// ─────────────────────────────────────────────

class QueueApiException implements Exception {
  final String  message;
  final int?    statusCode;

  const QueueApiException( this.message, { this.statusCode } );

  @override
  String toString() => 'QueueApiException($statusCode): $message';
}
