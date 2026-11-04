/// Shared response and error types for the agentic job submission endpoints.
///
/// Every submit endpoint returns the same job id, queue position and status.
/// Only the test-fix-expediter resume call has extra fields, so it has its own class.
library;

import '../../queue/data/queue_models.dart';

T? _as<T>( dynamic v ) => v is T ? v : null;

// ─────────────────────────────────────────────
// Job type enum
// ─────────────────────────────────────────────

/// The kinds of agentic job the hub can submit.
enum AgenticJobType {
  /// A deep research report job.
  deepResearch,
  /// A podcast generation job.
  podcast,
  /// A presentation generation job.
  presentation,
  /// A software-engineering team job.
  sweTeam,
  /// A job that fixes a dead job's bug.
  bugFixExpediter,
  /// A test suite run.
  testSuite,
  /// A job that fixes failing tests.
  testFixExpediter,
  /// Deep research chained into a podcast.
  researchToPodcast,
  /// Deep research chained into a presentation.
  researchToPresentation,
}

// ─────────────────────────────────────────────
// Common submit response
// ─────────────────────────────────────────────

/// Response from the standard agentic submit endpoints.
///
/// The job id prefix names the job type: dr-, pg-, px-, swe-, bfe-, ts-, rp- or rx-.
class AgenticSubmitResponse {
  /// Queue state the server reported, such as `queued`, `waiting` or `done`.
  final String  status;
  /// Id of the created job.
  final String  jobId;
  /// Place in the queue; 0 when the server reports none.
  final int     queuePosition;
  /// Optional text from the server, such as the answer to a finished request.
  final String? message;

  /// Creates a response from its parts.
  const AgenticSubmitResponse( {
    required this.status,
    required this.jobId,
    required this.queuePosition,
    this.message,
  } );

  /// Builds a response from the synchronous `/api/v2/submit` body.
  ///
  /// A long job returns status `waiting` with a job id, which counts as success.
  /// Any body that produced no job throws an [AgenticApiException] carrying the server's words.
  factory AgenticSubmitResponse.fromAsk( AskResponse ask ) {
    final jobId = ask.jobId;
    if ( jobId != null && jobId.isNotEmpty && ( ask.status == 'waiting' || ask.status == 'done' ) ) {
      return AgenticSubmitResponse(
        status        : ask.status,
        jobId         : jobId,
        queuePosition : 0,            // /api/v2/submit reports no queue position
        message       : ask.answer,
      );
    }
    if ( ask.status == 'needs_input' ) {
      throw AgenticApiException( 'Missing: ${ask.argsMissing.join( ", " )}' );
    }
    throw AgenticApiException(
      ask.error ?? ask.answer ?? 'No job was created (${ask.path}/${ask.status}: ${ask.routeReason})',
    );
  }

  /// Builds a response from the JSON body of a standard submit endpoint.
  factory AgenticSubmitResponse.fromJson( Map<String, dynamic> j ) =>
      AgenticSubmitResponse(
        status        : ( j[ 'status' ] as String? ) ?? 'queued',
        jobId         : j[ 'job_id' ]          as String,
        queuePosition : ( j[ 'queue_position' ] as int? ) ?? 0,
        message       : _as<String>( j[ 'message' ] ),
      );
}

// ─────────────────────────────────────────────
// TFE resume response (distinct — extra fields)
// ─────────────────────────────────────────────

/// Response from POST /api/test-fix-expediter/resume-from.
class TfeResumeResponse {
  /// Outcome the server reported, `resumed` by default.
  final String  status;
  /// Id of the new job that continues the work.
  final String  resumedJobId;
  /// Id of the job that was resumed.
  final String  originalJobId;
  /// Phase the new job restarts from; null when the server gave none.
  final int?    resumeFromPhase;
  /// Name of the restart phase; null when the server gave none.
  final String? phaseName;
  /// How many times the original job has been resumed.
  final int     resumeCount;

  /// Creates a response from its parts.
  const TfeResumeResponse( {
    required this.status,
    required this.resumedJobId,
    required this.originalJobId,
    this.resumeFromPhase,
    this.phaseName,
    this.resumeCount = 1,
  } );

  /// Builds a response from the resume endpoint's JSON body.
  factory TfeResumeResponse.fromJson( Map<String, dynamic> j ) =>
      TfeResumeResponse(
        status          : ( j[ 'status' ] as String? ) ?? 'resumed',
        resumedJobId    : j[ 'resumed_job_id' ]    as String,
        originalJobId   : j[ 'original_job_id' ]   as String,
        resumeFromPhase : j[ 'resume_from_phase' ]  as int?,
        phaseName       : _as<String>( j[ 'phase_name' ] ),
        resumeCount     : ( j[ 'resume_count' ] as int? ) ?? 1,
      );
}

// ─────────────────────────────────────────────
// Error
// ─────────────────────────────────────────────

/// Failure from an agentic endpoint, carrying the server's own explanation.
class AgenticApiException implements Exception {
  /// What went wrong, in the server's words when it gave any.
  final String message;
  /// HTTP status code; null when no response arrived.
  final int?   statusCode;

  /// Creates an exception with a message and an optional status code.
  const AgenticApiException( this.message, { this.statusCode } );

  @override
  String toString() => 'AgenticApiException($statusCode): $message';
}
