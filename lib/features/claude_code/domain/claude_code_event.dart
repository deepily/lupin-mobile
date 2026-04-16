import 'package:equatable/equatable.dart';

import '../data/claude_code_models.dart';

abstract class ClaudeCodeEvent extends Equatable {
  const ClaudeCodeEvent();
  @override List<Object?> get props => [];
}

class ClaudeCodeDispatch extends ClaudeCodeEvent {
  final ClaudeCodeDispatchRequest request;
  const ClaudeCodeDispatch( this.request );
  @override List<Object?> get props => [ request.prompt ];
}

class ClaudeCodeQueueSubmit extends ClaudeCodeEvent {
  final ClaudeCodeQueueRequest request;
  const ClaudeCodeQueueSubmit( this.request );
  @override List<Object?> get props => [ request.prompt ];
}

class ClaudeCodePollStatus extends ClaudeCodeEvent {
  final String taskId;
  const ClaudeCodePollStatus( this.taskId );
  @override List<Object?> get props => [ taskId ];
}

class ClaudeCodeInject extends ClaudeCodeEvent {
  final String taskId;
  final String message;
  const ClaudeCodeInject( { required this.taskId, required this.message } );
  @override List<Object?> get props => [ taskId, message ];
}

class ClaudeCodeInterrupt extends ClaudeCodeEvent {
  final String taskId;
  const ClaudeCodeInterrupt( this.taskId );
  @override List<Object?> get props => [ taskId ];
}

class ClaudeCodeEnd extends ClaudeCodeEvent {
  final String taskId;
  const ClaudeCodeEnd( this.taskId );
  @override List<Object?> get props => [ taskId ];
}

/// Fired by WS subscription manager when a claude_code_* event arrives.
class ClaudeCodeExternalMessage extends ClaudeCodeEvent {
  final String              taskId;
  final Map<String, dynamic> payload;
  const ClaudeCodeExternalMessage( { required this.taskId, required this.payload } );
  @override List<Object?> get props => [ taskId ];
}
