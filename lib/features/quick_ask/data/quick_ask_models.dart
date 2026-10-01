/// Quick Ask card model: one question-and-answer pair per entry.
///
/// An entry carries the full transition metadata, not just the answer text.
/// The completed frame is already card-shaped, so a grouped card view only has to render it.
library;

import '../../queue/data/queue_models.dart';
import '../../queue/domain/job_lifecycle.dart';

/// How an entry's state was learned.
///
/// Call sites use it to keep the reconcile-versus-folded precedence rule legible.
enum QuickAskSource {
  /// A `job_state_transition` frame.
  transition,

  /// A queue listing row found during reconcile.
  reconcile,

  /// The direct response to the ask request.
  askResponse
}

/// One Quick Ask card: a question, its lifecycle state and the answer once it exists.
class QuickAskEntry {
  /// The server's `id_hash`.
  ///
  /// Null only in the window after a question is submitted and before a job id exists.
  final String?           jobId;

  /// The job's lifecycle state.
  final JobLifecycleState state;

  /// How [state] was learned.
  final QuickAskSource    source;

  /// Every field the frame carried, parsed by the existing `JobSummary.fromJson`.
  final JobSummary?       details;

  /// The transcript that was submitted.
  ///
  /// It is held apart from `details.questionText` because it exists before any frame does.
  /// It is also one of the two insert-time buffer filter keys.
  final String            questionText;

  /// The latest `progress`-type notification text for this job, or null if none yet.
  ///
  /// A long-running job reports milestones on the way to its answer.
  /// They live here, beside the answer and never in it, so the card shows the job is alive
  /// without claiming it is finished.
  final String?           progressText;

  /// Creates an entry; only the question, state and source are required.
  const QuickAskEntry( {
    required this.questionText,
    required this.state,
    required this.source,
    this.jobId,
    this.details,
    this.progressText,
  } );

  /// The lane the card sits in, derived from [state].
  JobLane get lane       => state.lane;

  /// Whether the job has reached a final state.
  bool    get isTerminal => state.isTerminal;

  /// The answer text, or null when none has arrived.
  String? get answer => details?.responseText;

  /// The error text, or null when the job has not failed.
  String? get error  => details?.error;

  /// Whether a non-blank answer has arrived.
  bool get hasAnswer => ( answer?.trim().isNotEmpty ) ?? false;

  /// Builds an entry from a `job_state_transition` frame.
  ///
  /// The lifecycle state comes from the frame's own `to_state`, never from `metadata.status`.
  /// `JobSummary.fromJson` falls back silently to `queued`, which is the opposite of dropping
  /// a frame whose state is unknown. The parser is reused for the metadata only.
  ///
  /// Returns null when `to_state` or the job id is absent, or `to_state` is unrecognized.
  /// The caller then drops the frame rather than guess a lane for an unknown state.
  static QuickAskEntry? fromTransition( Map<String, dynamic> data, { String questionText = '' } ) {
    final state = JobLifecycleState.parse( data[ 'to_state' ] as String? );
    if ( state == null ) return null;

    final jobId = data[ 'job_id' ] as String?;
    if ( jobId == null || jobId.isEmpty ) return null;

    final rawMeta = data[ 'metadata' ];
    final meta    = rawMeta is Map ? Map<String, dynamic>.from( rawMeta ) : <String, dynamic>{};

    // The frame's metadata is a JobSummary body once the job id is folded in.
    final details = JobSummary.fromJson( { ...meta, 'job_id': jobId } );

    return QuickAskEntry(
      questionText : questionText.isNotEmpty ? questionText : ( details.questionText ?? '' ),
      state        : state,
      source       : QuickAskSource.transition,
      jobId        : jobId,
      details      : details,
    );
  }

  /// Builds an entry from a queue listing row found during reconcile.
  ///
  /// The caller supplies [state], derived from the queue the row was found in.
  /// It is not read off `summary.status`, for the same reason [fromTransition] ignores
  /// `metadata.status`: that field falls back silently to `queued`.
  factory QuickAskEntry.fromSummary(
    JobSummary summary, {
    required JobLifecycleState state,
    String questionText = '',
  } ) => QuickAskEntry(
    questionText : questionText.isNotEmpty ? questionText : ( summary.questionText ?? '' ),
    state        : state,
    source       : QuickAskSource.reconcile,
    jobId        : summary.jobId,
    details      : summary,
  );

  /// Returns a copy with the given fields replaced.
  QuickAskEntry copyWith( {
    String?            jobId,
    JobLifecycleState? state,
    QuickAskSource?    source,
    JobSummary?        details,
    String?            questionText,
    String?            progressText,
  } ) => QuickAskEntry(
    questionText : questionText ?? this.questionText,
    state        : state        ?? this.state,
    source       : source       ?? this.source,
    jobId        : jobId        ?? this.jobId,
    details      : details      ?? this.details,
    progressText : progressText ?? this.progressText,
  );

  @override
  String toString() => 'QuickAskEntry($jobId, ${state.name}, ${source.name})';
}

/// The lifecycle state a reconcile hit implies, by the queue it was found in.
///
/// The mapping is stated once here so no call site re-derives it.
JobLifecycleState stateForQueue( String queueName ) {
  switch ( queueName ) {
    case 'done': return JobLifecycleState.completed;
    case 'dead': return JobLifecycleState.failed;
    case 'run' : return JobLifecycleState.running;
    default    : return JobLifecycleState.queued;   // 'todo'
  }
}
