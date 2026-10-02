/// Data models for submitting a Claude Code job.
///
/// Jobs go through `POST /api/v2/submit` with the Claude Code routing command.
/// The job's own settings ride in `args`; queue directives stay top-level.
library;

import '../../queue/data/queue_models.dart';

/// One Claude Code job to queue.
class ClaudeCodeSubmitRequest {
  /// The routing command that names the Claude Code agent.
  static const String submitCommand = "agent router go to claude code";

  /// The longest question text the server accepts.
  static const int maxQuestionLength = 4000;

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

  /// The `/api/v2/submit` body for this job.
  ///
  /// Ensures:
  ///   - `prompt`, `project`, `task_type`, `max_turns` and `dry_run` go in `args`
  ///   - `websocket_id`, `scheduled_at` and `monopolize` stay top-level
  ///   - `question` carries the prompt, cut to [maxQuestionLength] characters
  SubmitRequest toSubmitRequest() => SubmitRequest(
    command     : submitCommand,
    args        : {
      "prompt"    : prompt,
      "project"   : project,
      "task_type" : taskType,
      "max_turns" : maxTurns,
      "dry_run"   : dryRun,
    },
    question    : prompt.length > maxQuestionLength
        ? prompt.substring( 0, maxQuestionLength )
        : prompt,
    websocketId : websocketId,
    scheduledAt : scheduledAt,
    monopolize  : monopolize ? true : null,
  );
}

/// The job the server created for a submission.
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

  /// Reads the `/api/v2/submit` answer.
  ///
  /// Ensures:
  ///   - `message` is the server's `answer`, or empty when it gave none
  ///   - `queuePosition` is the server's `queue_position`, or 0 when it gave none
  ///
  /// Raises:
  ///   - [ClaudeCodeApiException] when the body carries no job id, or a status
  ///     other than `waiting` or `done`; the message is the server's own words
  factory ClaudeCodeSubmitResponse.fromAsk( Map<String, dynamic> j ) {
    final ask   = AskResponse.fromJson( j );
    final jobId = ask.jobId;
    if ( jobId != null && jobId.isNotEmpty && ( ask.status == "waiting" || ask.status == "done" ) ) {
      return ClaudeCodeSubmitResponse(
        status        : ask.status,
        jobId         : jobId,
        queuePosition : ( j[ "queue_position" ] as int? ) ?? 0,
        message       : ask.answer ?? "",
      );
    }
    if ( ask.status == "needs_input" ) {
      throw ClaudeCodeApiException( "Missing: ${ask.argsMissing.join( ", " )}" );
    }
    throw ClaudeCodeApiException(
      ask.error ?? ask.answer ?? "No job was created (${ask.path}/${ask.status}: ${ask.routeReason})",
    );
  }
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
