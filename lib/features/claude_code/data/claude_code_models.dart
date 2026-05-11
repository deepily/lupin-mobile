/// Data models for the Lupin Claude Code submission API.
///
/// Field names match backend JSON exactly per
/// `cosa/rest/routers/claude_code_queue.py`.
///
/// Retired endpoints: see <lupin>/src/rnd/v0.1.7/2026.05.05-claude-code-dispatch-retirement/01-plan.md
/// Mobile-side breadcrumbs: src/rnd/v0.1.6-migration/2026.04.15-{tier-3-queue-and-claude-code-plan,resync-mobile-with-lupin-api-v0.1.6}.md
/// Canonical successor: POST /api/claude-code/submit (this file)
library;

/// Request body for POST /api/claude-code/submit.
class ClaudeCodeSubmitRequest {
  final String  prompt;
  final String  project;
  final String  taskType;
  final int     maxTurns;
  final String? websocketId;
  final bool    dryRun;
  final String? scheduledAt;
  final bool    monopolize;

  const ClaudeCodeSubmitRequest( {
    required this.prompt,
    this.project     = "lupin",
    this.taskType    = "BOUNDED",
    this.maxTurns    = 50,
    this.websocketId,
    this.dryRun      = false,
    this.scheduledAt,
    this.monopolize  = false,
  } );

  Map<String, dynamic> toJson() => {
    "prompt"     : prompt,
    "project"    : project,
    "task_type"  : taskType,
    "max_turns"  : maxTurns,
    if ( websocketId != null ) "websocket_id" : websocketId,
    "dry_run"    : dryRun,
    if ( scheduledAt != null ) "scheduled_at" : scheduledAt,
    "monopolize" : monopolize,
  };
}

/// Response from POST /api/claude-code/submit.
class ClaudeCodeSubmitResponse {
  final String status;
  final String jobId;
  final int    queuePosition;
  final String message;

  const ClaudeCodeSubmitResponse( {
    required this.status,
    required this.jobId,
    required this.queuePosition,
    required this.message,
  } );

  factory ClaudeCodeSubmitResponse.fromJson( Map<String, dynamic> j ) =>
      ClaudeCodeSubmitResponse(
        status        : j[ "status" ]         as String,
        jobId         : j[ "job_id" ]         as String,
        queuePosition : ( j[ "queue_position" ] as int? ) ?? 0,
        message       : ( j[ "message" ] as String? ) ?? "",
      );
}

class ClaudeCodeApiException implements Exception {
  final String  message;
  final int?    statusCode;

  const ClaudeCodeApiException( this.message, { this.statusCode } );

  @override
  String toString() => "ClaudeCodeApiException($statusCode): $message";
}
