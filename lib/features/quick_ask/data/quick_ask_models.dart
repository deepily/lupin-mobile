/// Quick Ask card model.
///
/// One entry is one question-and-answer pair. It carries the FULL transition
/// metadata rather than just the answer text, deliberately: the completed
/// frame is already card-shaped (`running_fifo_queue.py:1691`, tagged in-source
/// "Phase 6.2: Card-rendering fields for client-side card creation"), so
/// parsing all of it now makes round 2's grouped card view a rendering
/// exercise instead of a re-parse.
library;

import '../../queue/data/queue_models.dart';
import '../../queue/domain/job_lifecycle.dart';

/// How this entry's state was learned. Round 2 renders provenance; round 1
/// uses it to keep the reconcile-vs-folded precedence rule (AC-S1.4d) legible
/// at the call site.
enum QuickAskSource { transition, reconcile, askResponse }

class QuickAskEntry {
  /// The server's `id_hash`. Null only in the pre-attribution window, where a
  /// question has been submitted and no job id exists yet.
  final String?           jobId;
  final JobLifecycleState state;
  final QuickAskSource    source;

  /// Every field the frame carried, parsed by the EXISTING parser
  /// (`JobSummary.fromJson`) rather than a second hand-written one — AC-S1.9.
  final JobSummary?       details;

  /// The transcript we submitted. Held separately from `details.questionText`
  /// because it exists BEFORE any frame does, and it is one of the two
  /// insert-time buffer filter keys.
  final String            questionText;

  /// Latest `progress`-type notification text for this job (bug 1829eb26).
  /// A long-running job reports milestones on the way to its answer; those
  /// used to be read as the answer itself, which ended the card on the first
  /// one and dropped the real result minutes later. They live HERE instead —
  /// beside the answer, never in it — so the card can show the job is alive
  /// without ever claiming to be finished. Null ⇒ nothing reported yet.
  final String?           progressText;

  const QuickAskEntry( {
    required this.questionText,
    required this.state,
    required this.source,
    this.jobId,
    this.details,
    this.progressText,
  } );

  JobLane get lane       => state.lane;
  bool    get isTerminal => state.isTerminal;

  String? get answer => details?.responseText;
  String? get error  => details?.error;

  bool get hasAnswer => ( answer?.trim().isNotEmpty ) ?? false;

  /// Build from a `job_state_transition` frame.
  ///
  /// 🔴 The lifecycle state comes from the frame's own `to_state` and NEVER
  /// from `metadata.status` (AC-S1.9). `JobSummary.fromJson` reads
  /// `( j['status'] as String? ) ?? 'queued'` — a SILENT fallback, the exact
  /// opposite of "unknown means drop the frame". Reusing that parser for the
  /// metadata is correct; letting it decide the lifecycle state would not be.
  ///
  /// Returns null when `to_state` is absent or unrecognized, so the caller
  /// drops the frame rather than guessing a lane for a state this build has
  /// never heard of.
  static QuickAskEntry? fromTransition( Map<String, dynamic> data, { String questionText = '' } ) {
    final state = JobLifecycleState.parse( data[ 'to_state' ] as String? );
    if ( state == null ) return null;

    final jobId = data[ 'job_id' ] as String?;
    if ( jobId == null || jobId.isEmpty ) return null;

    final rawMeta = data[ 'metadata' ];
    final meta    = rawMeta is Map ? Map<String, dynamic>.from( rawMeta ) : <String, dynamic>{};

    // The one-line adapter AC-S1.9 specifies: the frame's metadata IS a
    // JobSummary body once the job id is folded in.
    final details = JobSummary.fromJson( { ...meta, 'job_id': jobId } );

    return QuickAskEntry(
      questionText : questionText.isNotEmpty ? questionText : ( details.questionText ?? '' ),
      state        : state,
      source       : QuickAskSource.transition,
      jobId        : jobId,
      details      : details,
    );
  }

  /// Build from a queue listing row found during reconcile.
  ///
  /// The state is supplied by the CALLER, derived from which queue the row was
  /// found in — not read off `summary.status`, for the same reason
  /// `fromTransition` ignores `metadata.status`: that field carries a silent
  /// `?? 'queued'` fallback.
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
/// Stated once here so the mapping is not re-derived at each call site.
JobLifecycleState stateForQueue( String queueName ) {
  switch ( queueName ) {
    case 'done': return JobLifecycleState.completed;
    case 'dead': return JobLifecycleState.failed;
    case 'run' : return JobLifecycleState.running;
    default    : return JobLifecycleState.queued;   // 'todo'
  }
}
