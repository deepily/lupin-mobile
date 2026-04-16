import 'package:equatable/equatable.dart';

import '../data/queue_models.dart';

abstract class QueueEvent extends Equatable {
  const QueueEvent();
  @override
  List<Object?> get props => [];
}

// ─── Load / refresh ──────────────────────────────────────────────────────────

class QueueLoadSnapshot extends QueueEvent {
  final String queueName;  // todo | run | done | dead
  const QueueLoadSnapshot( this.queueName );
  @override List<Object?> get props => [ queueName ];
}

class QueueLoadHistory extends QueueEvent {
  final String? status;
  final String? jobType;
  final int     limit;
  final int     offset;
  const QueueLoadHistory( { this.status, this.jobType, this.limit = 20, this.offset = 0 } );
  @override List<Object?> get props => [ status, jobType, limit, offset ];
}

class QueueLoadInteractions extends QueueEvent {
  final String jobId;
  const QueueLoadInteractions( this.jobId );
  @override List<Object?> get props => [ jobId ];
}

/// Fired by WS subscription manager when a queue event arrives.
class QueueExternalUpdate extends QueueEvent {
  final String queueName;
  const QueueExternalUpdate( this.queueName );
  @override List<Object?> get props => [ queueName ];
}

// ─── Job submission ───────────────────────────────────────────────────────────

class QueueSubmitJob extends QueueEvent {
  final PushJobRequest request;
  const QueueSubmitJob( this.request );
  @override List<Object?> get props => [ request ];
}

class QueueSubmitAgenticJob extends QueueEvent {
  final PushAgenticRequest request;
  const QueueSubmitAgenticJob( this.request );
  @override List<Object?> get props => [ request ];
}

// ─── Job lifecycle ────────────────────────────────────────────────────────────

class QueueCancelJob extends QueueEvent {
  final String jobId;
  const QueueCancelJob( this.jobId );
  @override List<Object?> get props => [ jobId ];
}

class QueuePauseJob extends QueueEvent {
  final String jobId;
  const QueuePauseJob( this.jobId );
  @override List<Object?> get props => [ jobId ];
}

class QueueResumeJob extends QueueEvent {
  final String jobId;
  const QueueResumeJob( this.jobId );
  @override List<Object?> get props => [ jobId ];
}

class QueueDeleteJob extends QueueEvent {
  final String queueName;
  final String jobId;
  const QueueDeleteJob( { required this.queueName, required this.jobId } );
  @override List<Object?> get props => [ queueName, jobId ];
}

class QueueRetryJob extends QueueEvent {
  final String jobId;
  final String websocketId;
  const QueueRetryJob( { required this.jobId, required this.websocketId } );
  @override List<Object?> get props => [ jobId, websocketId ];
}

class QueueResumeFromCheckpoint extends QueueEvent {
  final String idHash;
  const QueueResumeFromCheckpoint( this.idHash );
  @override List<Object?> get props => [ idHash ];
}

class QueueInjectMessage extends QueueEvent {
  final String jobId;
  final String message;
  final String priority;
  const QueueInjectMessage( { required this.jobId, required this.message, this.priority = 'normal' } );
  @override List<Object?> get props => [ jobId, message, priority ];
}
