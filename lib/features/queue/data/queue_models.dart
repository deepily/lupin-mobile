/// Data models for the Lupin CJ Flow queue API.
///
/// Field names match the backend JSON exactly.
library;

import 'package:equatable/equatable.dart';

DateTime? _parseDt( dynamic v ) =>
    v == null ? null : DateTime.tryParse( v.toString() );

T? _as<T>( dynamic v ) => v is T ? v : null;

// ─────────────────────────────────────────────
// Submission requests
// ─────────────────────────────────────────────

/// Request body for `POST /api/v2/ask`, the question door of the v2 flow.
///
/// It replaces `POST /api/push`, which now answers 410.
/// Field names match the server's `AskRequest`.
class AskRequest {
  /// The question text to route and answer.
  final String  question;

  /// Socket that receives the spoken answer, when one is set.
  final String? websocketId;

  /// Whether the answer is also dispatched as a spoken notification.
  final bool    speak;

  /// Whether a missing argument parks the ask for a resume, instead of answering `needs_input`.
  final bool    interactive;

  /// Creates a request with speech and interaction on by default.
  const AskRequest( {
    required this.question,
    this.websocketId,
    this.speak       = true,
    this.interactive = true,
  } );

  /// Serializes to the wire body, leaving out an unset socket id.
  Map<String, dynamic> toJson() => {
    'question'     : question,
    if ( websocketId != null ) 'websocket_id' : websocketId,
    'speak'        : speak,
    'interactive'  : interactive,
  };
}

/// Request body for `POST /api/v2/submit`, for work whose command is already decided.
///
/// The caller names the routing command and hands over every argument it needs.
/// The server skips routing and extraction, and a submit never parks.
/// Missing arguments come back as `needs_input` with `argsMissing` filled in.
/// `scheduledAt` and `monopolize` travel top-level, not inside `args`, because they are
/// queue directives and `args` is validated against the agent's argument contract.
/// They are serialized only when set, so bodies are unchanged until the server accepts them.
class SubmitRequest {
  /// The routing command that names the agent to run.
  final String               command;

  /// Every argument the command needs.
  final Map<String, dynamic> args;

  /// Optional question text, carried for the record only.
  final String?              question;

  /// Socket that receives the spoken answer, when one is set.
  final String?              websocketId;

  /// Whether the answer is also dispatched as a spoken notification.
  final bool                 speak;

  /// Optional time at which the queue should start the job.
  final String?              scheduledAt;

  /// Optional flag asking the queue to run this job with exclusive use of the worker.
  final bool?                monopolize;

  /// Creates a submit body; only `command` is required.
  const SubmitRequest( {
    required this.command,
    this.args        = const {},
    this.question,
    this.websocketId,
    this.speak       = true,
    this.scheduledAt,
    this.monopolize,
  } );

  /// Serializes to the wire body, leaving out every unset optional field.
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

/// Request body for `POST /api/push-agentic`, an agentic job that bypasses the expediter.
class PushAgenticRequest {
  /// The routing command that names the agent to run.
  final String               routingCommand;

  /// Socket that receives the job's notifications.
  final String               websocketId;

  /// Arguments for the agent, sent only when not empty.
  final Map<String, dynamic> args;

  /// Optional question text, carried for the record only.
  final String?              question;

  /// Optional time at which the queue should start the job.
  final String?              scheduledAt;

  /// Whether the queue runs this job with exclusive use of the worker.
  final bool                 monopolize;

  /// Creates an agentic push body.
  const PushAgenticRequest( {
    required this.routingCommand,
    required this.websocketId,
    this.args       = const {},
    this.question,
    this.scheduledAt,
    this.monopolize = false,
  } );

  /// Returns the same submission as a [SubmitRequest].
  ///
  /// `routingCommand` becomes `command`, and `args` and `question` carry over unchanged.
  /// The queue directives stay top-level.
  SubmitRequest toSubmitRequest( { bool speak = true } ) => SubmitRequest(
    command     : routingCommand,
    args        : args,
    question    : question,
    websocketId : websocketId,
    speak       : speak,
    scheduledAt : scheduledAt,
    monopolize  : monopolize ? true : null,
  );

  /// Serializes to the wire body, leaving out empty or unset optional fields.
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

/// Response from `POST /api/push-agentic`, the queue-and-poll reply.
///
/// The synchronous v2 reply is [AskResponse].
class PushJobResponse {
  /// Outcome of the submission, such as `waiting` or `done`.
  final String  status;

  /// Socket the job was bound to.
  final String  websocketId;

  /// Owner of the job; empty when the v2 body does not carry one.
  final String  userId;

  /// Id of the queued job, when one was created.
  final String? jobId;

  /// Answer text, when the job already finished.
  final String? result;

  /// Routing command of an agentic job.
  final String? routingCommand;

  /// Creates a response.
  const PushJobResponse( {
    required this.status,
    required this.websocketId,
    required this.userId,
    this.jobId,
    this.result,
    this.routingCommand,
  } );

  /// Adapts a synchronous v2 [AskResponse] to the queue-and-poll shape the dashboard renders.
  ///
  /// The agentic push now rides `/api/v2/submit`, whose body has no user id, so `userId` is empty.
  factory PushJobResponse.fromAsk( AskResponse ask, { required String websocketId } ) => PushJobResponse(
    status         : ask.status,
    websocketId    : websocketId,
    userId         : '',
    jobId          : ask.jobId,
    result         : ask.answer,
    routingCommand : ask.command,
  );

  /// Parses the wire JSON; `status`, `websocket_id` and `user_id` are required.
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
// v2 ask response
// ─────────────────────────────────────────────

/// Body of `POST /api/v2/resume`, the answer turn of an interactive ask.
///
/// It has four fields, and `websocketId` is the one that is easy to forget.
/// The ask turn sets `websocket_id`, which routes the answer's speech.
/// A resume that sends only the pending id and the answer speaks nowhere.
/// The interview can re-enter, so every turn after the first is this call.
class ResumeRequest {
  /// Id of the parked ask being answered.
  final String  pendingId;

  /// The user's answer text.
  final String  answer;

  /// Socket that receives the spoken answer.
  final String? websocketId;

  /// Whether the answer is also dispatched as a spoken notification.
  final bool    speak;

  /// Creates a resume body.
  const ResumeRequest( {
    required this.pendingId,
    required this.answer,
    this.websocketId,
    this.speak = true,
  } );

  /// Serializes to the wire body, leaving out an unset socket id.
  Map<String, dynamic> toJson() => {
    'pending_id'   : pendingId,
    'answer'       : answer,
    if ( websocketId != null ) 'websocket_id' : websocketId,
    'speak'        : speak,
  };
}

/// Response from `POST /api/v2/ask`, which is synchronous.
///
/// The answer, or the first clarifying question, comes back in the body and nothing is queued.
/// Field names match the server's `AskResponse`.
class AskResponse {
  /// How the server handled the ask: `replay`, `agent`, `needs_input` or `receptionist`.
  final String        path;

  /// Outcome: `done`, `parked`, `needs_input`, `waiting`, `expired` or `failed`.
  final String        status;

  /// Why the router chose this path.
  final String        routeReason;

  /// The answer text, when there is one.
  final String?       answer;

  /// The answer before any speech-oriented rewriting.
  final String?       answerRaw;

  /// The routing command that handled the ask.
  final String?       command;

  /// Names of the arguments the server already has.
  final List<String>  argsKnown;

  /// Names of the arguments the server still needs.
  final List<String>  argsMissing;

  /// Id to resume with `POST /api/v2/resume`; set only when the ask is parked.
  final String?       pendingId;

  /// Id of the queued or finished job, when one exists.
  final String?       jobId;

  /// Id of the cached snapshot that served the ask, when one did.
  final String?       snapshotId;

  /// Similarity score of the cache match, when one was made.
  final double?       similarity;

  /// Whether this ask wrote a new cache snapshot.
  final bool          wroteSnapshot;

  /// Whether the answer came from the cache.
  final bool          cacheHit;

  /// Whether the server already spoke the answer.
  final bool          spoke;

  /// Per-stage timings in milliseconds.
  final Map<String, dynamic> timingsMs;

  /// Server trace id for this ask.
  final String        traceId;

  /// Failure text, when `status` is `failed`.
  final String?       error;

  /// Creates a response.
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

  /// True when the ask finished with an answer.
  bool get isDone     => status == 'done';

  /// True when the server wants something from the user, whether parked or telling.
  ///
  /// This is the union of [isParked] and [isNeedsInput].
  /// Callers that only ask whether the user must act can use it.
  bool get needsInput => status == 'needs_input' || status == 'parked';

  /// True when the server is asking and the answer goes back through `POST /api/v2/resume`.
  ///
  /// A parked ask carries a `pending_id`.
  /// `needs_input` is different: the submit path never parks, so it carries no id.
  /// The server is telling the user there, not asking, and an answer box has nowhere to send its value.
  bool get isParked    => status == 'parked';

  /// True when the server reports missing arguments without parking; see [isParked].
  bool get isNeedsInput => status == 'needs_input';

  /// True when the ask failed.
  bool get isFailed   => status == 'failed';

  /// True when the ask expired; only the resume door emits this outcome.
  bool get isExpired  => status == 'expired';

  /// True when the job is queued and has not started.
  ///
  /// A queued job is none of done, needing input or failed.
  /// Without this check [summary] fell through to "Done" for work that had not started.
  bool get isWaiting  => status == 'waiting';

  /// One-line summary for snackbars and toasts.
  String get summary {
    if ( needsInput ) return answer ?? 'Needs input: ${argsMissing.join( ", " )}';
    if ( isFailed )   return error ?? 'Request failed';
    // Checked before the answer fallback: a queued job has no answer yet, and saying
    // "Done" about it would be wrong.
    if ( isWaiting )  return 'Queued\u2026';
    return answer ?? 'Done ($path)';
  }

  static List<String> _strList( dynamic v ) =>
      v is List ? v.map( ( e ) => e.toString() ).toList() : const [];

  /// Parses the wire JSON; `path` and `status` are required, other fields default.
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
// POST /api/v2/ask-audio — the spoken-ask stream
// ─────────────────────────────────────────────

/// One event read off the `POST /api/v2/ask-audio` NDJSON body.
///
/// `QueueRepository.askSpoken` returns these as a stream.
/// This is the only sealed, equatable type in the file.
/// The bloc compares emitted events by value, and an identity comparison would mislead it.
/// It lives here because [SpokenAskResult] wraps [AskResponse].
/// The stream emits at most one terminal event ([isTerminal]) and then closes.
/// It never throws; every failure arrives as an event.
///
/// Wire outcomes and the events they produce, in order:
/// - A non-200 gives [SpokenAskFailed] with `statusCode`.
/// - A body that closes before any line gives [SpokenAskFailed].
/// - A `transcript` line gives [SpokenAskTranscript], and the stream continues.
/// - An `ask` line gives [SpokenAskResult].
/// - An `error` line gives [SpokenAskFailed], after the transcript.
/// - A body that closes after the transcript, with no second line, gives [SpokenAskCutOff].
/// - A malformed line or network error mid-body gives Failed before the transcript, CutOff after.
sealed class SpokenAskEvent extends Equatable {
  /// Creates an event.
  const SpokenAskEvent();

  /// True for [SpokenAskResult], [SpokenAskFailed] and [SpokenAskCutOff].
  ///
  /// The stream closes after any of these three.
  bool get isTerminal;
}

/// First line of the stream: the server's transcript of the audio.
///
/// It is not terminal. The ask is already running on the server when it arrives.
class SpokenAskTranscript extends SpokenAskEvent {
  /// The transcribed text.
  final String text;

  /// Creates a transcript event.
  const SpokenAskTranscript( this.text );

  @override
  bool get isTerminal => false;

  @override
  List<Object?> get props => [ text ];
}

/// Second line of the stream: the full [AskResponse].
///
/// It carries the `job_id` that tracking and cancelling key on.
class SpokenAskResult extends SpokenAskEvent {
  /// The server's answer to the spoken ask.
  final AskResponse response;

  /// Creates a result event.
  const SpokenAskResult( this.response );

  @override
  bool get isTerminal => true;

  /// Compares over the response fields, because [AskResponse] has no value equality.
  ///
  /// Two results parsed from the same bytes compare equal.
  @override
  List<Object?> get props => [
    response.path,
    response.status,
    response.routeReason,
    response.answer,
    response.answerRaw,
    response.command,
    response.argsKnown,
    response.argsMissing,
    response.pendingId,
    response.jobId,
    response.snapshotId,
    response.similarity,
    response.wroteSnapshot,
    response.cacheHit,
    response.spoke,
    response.timingsMs,
    response.traceId,
    response.error,
  ];
}

/// Nothing usable came back from the stream.
///
/// The cases are a non-200 (nothing was asked), a body that closed or broke before the
/// transcript, and an `error` line after it.
class SpokenAskFailed extends SpokenAskEvent {
  /// What went wrong, for display.
  final String detail;

  /// HTTP status; set only when the server answered with a non-200.
  final int?   statusCode;

  /// Creates a failure event.
  const SpokenAskFailed( this.detail, { this.statusCode } );

  @override
  bool get isTerminal => true;

  @override
  List<Object?> get props => [ detail, statusCode ];
}

/// The transcript arrived and then the body ended without a second line.
///
/// Causes are a dropped connection, a malformed line or a network error.
/// The ask was sent and is still running on the server, so its answer may still arrive
/// over the WebSocket. Only the job id is lost.
class SpokenAskCutOff extends SpokenAskEvent {
  /// The transcript that did arrive.
  final String transcript;

  /// Creates a cut-off event.
  const SpokenAskCutOff( this.transcript );

  @override
  bool get isTerminal => true;

  @override
  List<Object?> get props => [ transcript ];
}

// ─────────────────────────────────────────────
// Queue snapshot
// ─────────────────────────────────────────────

/// A single job summary entry in any queue (todo, run, done or dead).
///
/// The backend returns these under the `{queue_name}_jobs_metadata` key.
class JobSummary {
  /// Job id (the server's id hash).
  final String   jobId;

  /// The question or request text.
  final String?  questionText;

  /// When the job was created.
  final String?  timestamp;

  /// Owner's user id.
  final String?  userId;

  /// Owner's email.
  final String?  userEmail;

  /// Session the job belongs to.
  final String?  sessionId;

  /// The agent type that runs the job.
  final String?  agentType;

  /// Lifecycle state: `queued`, `running`, `paused`, `completed`, `failed` or `stalled`.
  final String   status;

  /// When the job started running.
  final String?  startedAt;

  /// When the job finished.
  final String?  completedAt;

  /// Failure text, when the job failed.
  final String?  error;

  /// Time at which the queue is to start the job, when scheduled.
  final String?  scheduledAt;

  /// Whether the job runs with exclusive use of the worker.
  final bool     monopolize;

  /// Whether the job is paused.
  final bool     paused;

  /// The job's answer text; set on done and dead jobs.
  final String?  responseText;

  /// Whether the job exchanged interactions with the user; set on done and dead jobs.
  final bool     hasInteractions;

  /// Whether the answer came from the cache; set on done and dead jobs.
  final bool     isCacheHit;

  /// Run time in seconds; set on done and dead jobs.
  final double?  durationSeconds;

  /// Path of the generated report, on done jobs.
  final String?  reportPath;

  /// Path of the generated slide deck, on done jobs.
  final String?  pptxPath;

  /// Path of the generated YAML output, on done jobs.
  final String?  yamlPath;

  /// Short abstract of the result, on done jobs.
  final String?  abstract;

  /// Cost breakdown, on done jobs.
  final Map<String, dynamic>? costSummary;

  /// Path of the plan the job followed, on dead jobs.
  final String?  planPath;

  /// Path of the remediation snapshot, on dead jobs.
  final String?  remediationSnapshotPath;

  /// Creates a summary; only the id and status are required.
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

  /// Parses the wire JSON; `job_id` is required and `status` defaults to `queued`.
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

/// Response from `GET /api/get-queue/{queue_name}`.
class QueueResponse {
  /// Which queue this is: todo, run, done or dead.
  final String         queueName;

  /// The jobs in the queue.
  final List<JobSummary> jobs;

  /// Describes the filter the server applied.
  final String         filteredBy;

  /// Whether the server returned the admin view of all users' jobs.
  final bool           isAdminView;

  /// Total number of jobs in the queue.
  final int            totalJobs;

  /// Creates a response.
  const QueueResponse( {
    required this.queueName,
    required this.jobs,
    required this.filteredBy,
    required this.isAdminView,
    required this.totalJobs,
  } );

  /// Parses the wire JSON, reading the jobs from the `{queueName}_jobs_metadata` key.
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

/// A single job history record from the server's persistent store.
///
/// Returned by `GET /api/job-history` and `GET /api/job-history/{job_id}`.
class JobHistoryEntry {
  /// Job id (the server's id hash).
  final String   idHash;

  /// The agent type that ran the job.
  final String?  jobType;

  /// Owner's user id.
  final String?  userId;

  /// Owner's email.
  final String?  userEmail;

  /// Session the job belonged to.
  final String?  sessionId;

  /// Routing command that handled the job.
  final String?  routingCommand;

  /// Lifecycle state: `pending`, `running`, `completed`, `failed`, `interrupted` or `stalled`.
  final String   status;

  /// The question or request text.
  final String?  questionText;

  /// Failure text, when the job failed.
  final String?  error;

  /// Whether the answer came from the cache.
  final bool     isCacheHit;

  /// Run time in seconds.
  final double?  durationSeconds;

  /// Free-form job metadata as a JSON string.
  final String? metadataJson;

  /// When the record was created.
  final String?  createdAt;

  /// When the job started running.
  final String?  startedAt;

  /// When the job finished.
  final String?  completedAt;

  /// When the record was last updated.
  final String?  updatedAt;

  /// Creates an entry; only the id and status are required.
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

  /// Parses the wire JSON; `id_hash` is required and `status` defaults to `unknown`.
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

/// Paginated list response from `GET /api/job-history`.
class JobHistoryPage {
  /// The entries on this page.
  final List<JobHistoryEntry> jobs;

  /// Total number of entries across all pages.
  final int                   total;

  /// Describes the filter the server applied.
  final String                filteredBy;

  /// Page size the server used.
  final int                   limit;

  /// Index of the first entry on this page.
  final int                   offset;

  /// Creates a page.
  const JobHistoryPage( {
    required this.jobs,
    required this.total,
    required this.filteredBy,
    required this.limit,
    required this.offset,
  } );

  /// Parses the wire JSON; `limit` defaults to 20 and `offset` to 0.
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
  /// Notification id.
  final String  id;

  /// Notification type, when the server sent one.
  final String? type;

  /// The message text shown to the user.
  final String  message;

  /// When the interaction happened.
  final String  timestamp;

  /// Whether the notification asked the user for a response.
  final bool    responseRequested;

  /// The user's response, when one was given.
  final String? responseValue;

  /// Notification priority, when the server sent one.
  final String? priority;

  /// Short abstract attached to the notification.
  final String? abstract;

  /// Creates an interaction; only the id, message and timestamp are required.
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

  /// Parses the wire JSON; `id` is required and the other fields default.
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

/// Full response from `GET /api/get-job-interactions/{job_id}`.
class JobInteractionsResponse {
  /// Id of the job the interactions belong to.
  final String              jobId;

  /// Session the job belongs to.
  final String?             sessionId;

  /// Free-form job metadata.
  final Map<String, dynamic>? jobMetadata;

  /// The interactions, as the server ordered them.
  final List<JobInteraction>  interactions;

  /// Number of interactions the server counted.
  final int                   interactionCount;

  /// Creates a response.
  const JobInteractionsResponse( {
    required this.jobId,
    this.sessionId,
    this.jobMetadata,
    required this.interactions,
    required this.interactionCount,
  } );

  /// Parses the wire JSON; `job_id` is required and the count defaults to 0.
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

/// Response from `POST /api/jobs/{job_id}/message`.
class MessageDeliveredResponse {
  /// Delivery outcome reported by the server.
  final String status;

  /// Id of the notification that carries the message.
  final String notificationId;

  /// Id of the job the message was sent to.
  final String jobId;

  /// Creates a response.
  const MessageDeliveredResponse( {
    required this.status,
    required this.notificationId,
    required this.jobId,
  } );

  /// Parses the wire JSON; all three fields are required.
  factory MessageDeliveredResponse.fromJson( Map<String, dynamic> j ) =>
      MessageDeliveredResponse(
        status         : j[ 'status' ]          as String,
        notificationId : j[ 'notification_id' ] as String,
        jobId          : j[ 'job_id' ]          as String,
      );
}

/// Response from `POST /api/jobs/{id_hash}/resume-from-checkpoint`.
class ResumeCheckpointResponse {
  /// Outcome reported by the server.
  final String  status;

  /// Id of the new job that continues the work.
  final String  resumedJobId;

  /// Id of the job that was resumed from.
  final String  originalJobId;

  /// Phase number the new job starts from.
  final int?    resumeFromPhase;

  /// Name of the phase the new job starts from.
  final String? phaseName;

  /// How many times the original work has been resumed.
  final int     resumeCount;

  /// Creates a response.
  const ResumeCheckpointResponse( {
    required this.status,
    required this.resumedJobId,
    required this.originalJobId,
    this.resumeFromPhase,
    this.phaseName,
    this.resumeCount = 1,
  } );

  /// Parses the wire JSON; the status and both job ids are required.
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

/// Raised by the queue repository when the API returns an error.
class QueueApiException implements Exception {
  /// What went wrong, for display.
  final String  message;

  /// HTTP status, when the failure came from a response.
  final int?    statusCode;

  /// Creates an exception.
  const QueueApiException( this.message, { this.statusCode } );

  @override
  String toString() => 'QueueApiException($statusCode): $message';
}
