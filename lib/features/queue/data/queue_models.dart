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

/// Request body for POST /api/push (standard job via runtime-arg expediter).
class PushJobRequest {
  final String  question;
  final String  websocketId;

  const PushJobRequest( { required this.question, required this.websocketId } );

  Map<String, dynamic> toJson() => {
    'question'     : question,
    'websocket_id' : websocketId,
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

/// Response from POST /api/push and POST /api/push-agentic.
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

/// Response from POST /api/job-history/{job_id}/retry.
class RetryJobResponse {
  final String status;
  final String originalJobId;

  const RetryJobResponse( { required this.status, required this.originalJobId } );

  factory RetryJobResponse.fromJson( Map<String, dynamic> j ) => RetryJobResponse(
    status        : j[ 'status' ]           as String,
    originalJobId : j[ 'original_job_id' ]  as String,
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
