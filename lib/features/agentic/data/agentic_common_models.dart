/// Shared types for all agentic job submission endpoints.
///
/// All 9 submit endpoints return the same {job_id, queue_position, status}
/// shape; only TFE resume-from has extra fields and warrants its own class.
library;

import '../../queue/data/queue_models.dart';

T? _as<T>( dynamic v ) => v is T ? v : null;

// ─────────────────────────────────────────────
// Job type enum
// ─────────────────────────────────────────────

enum AgenticJobType {
  deepResearch,
  podcast,
  presentation,
  sweTeam,
  bugFixExpediter,
  testSuite,
  testFixExpediter,
  researchToPodcast,
  researchToPresentation,
}

// ─────────────────────────────────────────────
// Common submit response
// ─────────────────────────────────────────────

/// Response from all 8 standard agentic submit endpoints.
/// job_id prefix identifies type: dr- pg- px- swe- bfe- ts- rp- rx-
class AgenticSubmitResponse {
  final String  status;
  final String  jobId;
  final int     queuePosition;
  final String? message;

  const AgenticSubmitResponse( {
    required this.status,
    required this.jobId,
    required this.queuePosition,
    this.message,
  } );

  /// v2 wave 2: build from the synchronous `/api/v2/submit` body. A long job comes
  /// back `status == 'waiting'` with a `job_id` — that is a SUCCESS (the work was
  /// accepted and is running behind the queue), not a degrade. Anything that did
  /// not produce a job is surfaced as an [AgenticApiException] so the form shows a
  /// Failure with the server's own words instead of a blank success.
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
  final String  status;
  final String  resumedJobId;
  final String  originalJobId;
  final int?    resumeFromPhase;
  final String? phaseName;
  final int     resumeCount;

  const TfeResumeResponse( {
    required this.status,
    required this.resumedJobId,
    required this.originalJobId,
    this.resumeFromPhase,
    this.phaseName,
    this.resumeCount = 1,
  } );

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

class AgenticApiException implements Exception {
  final String message;
  final int?   statusCode;

  const AgenticApiException( this.message, { this.statusCode } );

  @override
  String toString() => 'AgenticApiException($statusCode): $message';
}
