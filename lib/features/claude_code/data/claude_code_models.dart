/// Data models for the Lupin Claude Code session API (6 endpoints).
///
/// Field names match backend JSON exactly per
/// `cosa/rest/routers/claude_code.py` and
/// `cosa/rest/routers/claude_code_queue.py`.
library;

T? _as<T>( dynamic v ) => v is T ? v : null;

// ─────────────────────────────────────────────
// Dispatch request
// ─────────────────────────────────────────────

/// Task type for POST /api/claude-code/dispatch.
enum ClaudeCodeTaskType { bounded, interactive }

/// Request body for POST /api/claude-code/dispatch.
class ClaudeCodeDispatchRequest {
  final String?            project;
  final String             prompt;
  final ClaudeCodeTaskType taskType;

  const ClaudeCodeDispatchRequest( {
    this.project,
    required this.prompt,
    this.taskType = ClaudeCodeTaskType.bounded,
  } );

  Map<String, dynamic> toJson() {
    final j = <String, dynamic>{
      'prompt'    : prompt,
      'task_type' : taskType == ClaudeCodeTaskType.bounded ? 'BOUNDED' : 'INTERACTIVE',
    };
    if ( project != null ) j[ 'project' ] = project;
    return j;
  }
}

// ─────────────────────────────────────────────
// Dispatch response
// ─────────────────────────────────────────────

/// Response from POST /api/claude-code/dispatch.
/// Backend returns {task_id, status, websocket_url}.
class ClaudeCodeSession {
  final String  taskId;
  final String  status;       // dispatched | running | complete | failed | error | interrupted | ended
  final String? websocketUrl;
  final double? costUsd;
  final String? error;

  const ClaudeCodeSession( {
    required this.taskId,
    required this.status,
    this.websocketUrl,
    this.costUsd,
    this.error,
  } );

  factory ClaudeCodeSession.fromJson( Map<String, dynamic> j ) => ClaudeCodeSession(
    taskId       : j[ 'task_id' ]      as String,
    status       : ( j[ 'status' ] as String? ) ?? 'unknown',
    websocketUrl : _as<String>( j[ 'websocket_url' ] ),
    costUsd      : ( j[ 'cost_usd' ] as num? )?.toDouble(),
    error        : _as<String>( j[ 'error' ] ),
  );

  ClaudeCodeSession copyWith( { String? status, double? costUsd, String? error } ) =>
      ClaudeCodeSession(
        taskId       : taskId,
        status       : status ?? this.status,
        websocketUrl : websocketUrl,
        costUsd      : costUsd ?? this.costUsd,
        error        : error ?? this.error,
      );
}

// ─────────────────────────────────────────────
// Queue submit (BOUNDED via CJ Flow)
// ─────────────────────────────────────────────

/// Request body for POST /api/claude-code/queue/submit.
class ClaudeCodeQueueRequest {
  final String  prompt;
  final String  project;
  final String  taskType;
  final int     maxTurns;
  final String? websocketId;
  final bool    dryRun;
  final String? scheduledAt;
  final bool    monopolize;

  const ClaudeCodeQueueRequest( {
    required this.prompt,
    this.project     = 'lupin',
    this.taskType    = 'BOUNDED',
    this.maxTurns    = 50,
    this.websocketId,
    this.dryRun      = false,
    this.scheduledAt,
    this.monopolize  = false,
  } );

  Map<String, dynamic> toJson() => {
    'prompt'    : prompt,
    'project'   : project,
    'task_type' : taskType,
    'max_turns' : maxTurns,
    if ( websocketId != null ) 'websocket_id' : websocketId,
    'dry_run'   : dryRun,
    if ( scheduledAt != null ) 'scheduled_at' : scheduledAt,
    'monopolize' : monopolize,
  };
}

/// Response from POST /api/claude-code/queue/submit.
class ClaudeCodeQueueResponse {
  final String status;
  final String jobId;
  final int    queuePosition;
  final String message;

  const ClaudeCodeQueueResponse( {
    required this.status,
    required this.jobId,
    required this.queuePosition,
    required this.message,
  } );

  factory ClaudeCodeQueueResponse.fromJson( Map<String, dynamic> j ) =>
      ClaudeCodeQueueResponse(
        status        : j[ 'status' ]         as String,
        jobId         : j[ 'job_id' ]         as String,
        queuePosition : ( j[ 'queue_position' ] as int? ) ?? 0,
        message       : ( j[ 'message' ] as String? ) ?? '',
      );
}

// ─────────────────────────────────────────────
// Inject / simple action responses
// ─────────────────────────────────────────────

/// Response from POST /api/claude-code/{task_id}/inject.
class ClaudeCodeInjectResponse {
  final String status;
  final String taskId;

  const ClaudeCodeInjectResponse( { required this.status, required this.taskId } );

  factory ClaudeCodeInjectResponse.fromJson( Map<String, dynamic> j ) =>
      ClaudeCodeInjectResponse(
        status : j[ 'status' ]  as String,
        taskId : j[ 'task_id' ] as String,
      );
}

// ─────────────────────────────────────────────
// Error
// ─────────────────────────────────────────────

class ClaudeCodeApiException implements Exception {
  final String  message;
  final int?    statusCode;

  const ClaudeCodeApiException( this.message, { this.statusCode } );

  @override
  String toString() => 'ClaudeCodeApiException($statusCode): $message';
}
