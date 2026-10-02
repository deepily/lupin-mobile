import 'package:equatable/equatable.dart';

import '../data/queue_models.dart';

/// Base class for events handled by `QueueBloc`.
abstract class QueueEvent extends Equatable {
  /// Creates an event.
  const QueueEvent();
  @override
  List<Object?> get props => [];
}

// ─── Load / refresh ──────────────────────────────────────────────────────────

/// Loads one queue snapshot.
class QueueLoadSnapshot extends QueueEvent {
  /// Which queue to load: `todo`, `run`, `done` or `dead`.
  final String queueName;

  /// Creates the event.
  const QueueLoadSnapshot( this.queueName );
  @override List<Object?> get props => [ queueName ];
}

/// Loads one page of job history.
class QueueLoadHistory extends QueueEvent {
  /// Status filter, or null for all.
  final String? status;

  /// Job type filter, or null for all.
  final String? jobType;

  /// Page size.
  final int     limit;

  /// Index of the first entry to load.
  final int     offset;

  /// Creates the event; the page defaults to the first 20 entries.
  const QueueLoadHistory( { this.status, this.jobType, this.limit = 20, this.offset = 0 } );
  @override List<Object?> get props => [ status, jobType, limit, offset ];
}

/// Loads the notification interactions recorded for one job.
class QueueLoadInteractions extends QueueEvent {
  /// Id of the job.
  final String jobId;

  /// Creates the event.
  const QueueLoadInteractions( this.jobId );
  @override List<Object?> get props => [ jobId ];
}

/// Fired by the WebSocket subscription manager when a queue event arrives.
class QueueExternalUpdate extends QueueEvent {
  /// Queue the update concerns.
  final String queueName;

  /// Creates the event.
  const QueueExternalUpdate( this.queueName );
  @override List<Object?> get props => [ queueName ];
}

// ─── Job submission ───────────────────────────────────────────────────────────

/// Asks a question through `/api/v2/ask`, which answers synchronously; see [QueueAnswered].
class QueueSubmitJob extends QueueEvent {
  /// The ask to send.
  final AskRequest request;

  /// Creates the event.
  const QueueSubmitJob( this.request );
  @override List<Object?> get props => [ request ];
}

/// Submits an agentic job to the queue.
class QueueSubmitAgenticJob extends QueueEvent {
  /// The job to submit.
  final PushAgenticRequest request;

  /// Creates the event.
  const QueueSubmitAgenticJob( this.request );
  @override List<Object?> get props => [ request ];
}

// ─── Job lifecycle ────────────────────────────────────────────────────────────

/// Cancels a job.
class QueueCancelJob extends QueueEvent {
  /// Id of the job.
  final String jobId;

  /// Creates the event.
  const QueueCancelJob( this.jobId );
  @override List<Object?> get props => [ jobId ];
}

/// Pauses a job in the todo queue.
class QueuePauseJob extends QueueEvent {
  /// Id of the job.
  final String jobId;

  /// Creates the event.
  const QueuePauseJob( this.jobId );
  @override List<Object?> get props => [ jobId ];
}

/// Resumes a paused job in the todo queue.
class QueueResumeJob extends QueueEvent {
  /// Id of the job.
  final String jobId;

  /// Creates the event.
  const QueueResumeJob( this.jobId );
  @override List<Object?> get props => [ jobId ];
}

/// Deletes a job from a queue.
class QueueDeleteJob extends QueueEvent {
  /// Queue the job is in.
  final String queueName;

  /// Id of the job.
  final String jobId;

  /// Creates the event.
  const QueueDeleteJob( { required this.queueName, required this.jobId } );
  @override List<Object?> get props => [ queueName, jobId ];
}

/// Re-asks a prior job's question through `/api/v2/ask`.
///
/// The client supplies the question text from the job row, because the server no longer retries.
class QueueRetryJob extends QueueEvent {
  /// Id of the job being retried.
  final String  jobId;

  /// The question to ask again.
  final String  questionText;

  /// Socket that receives the spoken answer, when one is set.
  final String? websocketId;

  /// Creates the event.
  const QueueRetryJob( { required this.jobId, required this.questionText, this.websocketId } );
  @override List<Object?> get props => [ jobId, questionText, websocketId ];
}

/// Resumes a job from its last checkpoint as a new job.
class QueueResumeFromCheckpoint extends QueueEvent {
  /// Id hash of the job to resume from.
  final String idHash;

  /// Creates the event.
  const QueueResumeFromCheckpoint( this.idHash );
  @override List<Object?> get props => [ idHash ];
}

/// Sends a message into a running job.
class QueueInjectMessage extends QueueEvent {
  /// Id of the job.
  final String jobId;

  /// The message text.
  final String message;

  /// Notification priority for the message.
  final String priority;

  /// Creates the event; the priority defaults to `normal`.
  const QueueInjectMessage( { required this.jobId, required this.message, this.priority = 'normal' } );
  @override List<Object?> get props => [ jobId, message, priority ];
}
