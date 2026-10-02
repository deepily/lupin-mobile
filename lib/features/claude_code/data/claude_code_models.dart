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
  /// The task text sent to Claude Code.
  final String  prompt;
  /// The project the job runs in.
  final String  project;
  /// The task type, such as `BOUNDED`.
  final String  taskType;
  /// The most turns the job may take.
  final int     maxTurns;
  /// The websocket id that receives progress; omitted from the JSON when null.
  final String? websocketId;
  /// True to ask for a dry run.
  final bool    dryRun;
  /// When to run the job; omitted from the JSON when null.
  final String? scheduledAt;
  /// True to ask that the job run alone.
  final bool    monopolize;

  /// Creates the request; only the prompt is required.
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

  /// The request body, using the backend's snake_case field names.
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
  /// The server's status word for the submission.
  final String status;
  /// The id of the new job.
  final String jobId;
  /// The job's place in the queue; 0 when the server omits it.
  final int    queuePosition;
  /// The server's message; empty when omitted.
  final String message;

  /// Creates the response.
  const ClaudeCodeSubmitResponse( {
    required this.status,
    required this.jobId,
    required this.queuePosition,
    required this.message,
  } );

  /// Reads the response from the backend's JSON body.
  factory ClaudeCodeSubmitResponse.fromJson( Map<String, dynamic> j ) =>
      ClaudeCodeSubmitResponse(
        status        : j[ "status" ]         as String,
        jobId         : j[ "job_id" ]         as String,
        queuePosition : ( j[ "queue_position" ] as int? ) ?? 0,
        message       : ( j[ "message" ] as String? ) ?? "",
      );
}

/// A failed call to the Claude Code API.
class ClaudeCodeApiException implements Exception {
  /// The server's detail text, or the transport error message.
  final String  message;
  /// The HTTP status code, when a response arrived.
  final int?    statusCode;

  /// Creates the exception.
  const ClaudeCodeApiException( this.message, { this.statusCode } );

  @override
  String toString() => "ClaudeCodeApiException($statusCode): $message";
}
