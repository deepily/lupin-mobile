import 'package:equatable/equatable.dart';

import '../data/claude_code_models.dart';

abstract class ClaudeCodeState extends Equatable {
  const ClaudeCodeState();
  @override List<Object?> get props => [];
}

class ClaudeCodeInitial extends ClaudeCodeState {
  const ClaudeCodeInitial();
}

class ClaudeCodeDispatching extends ClaudeCodeState {
  const ClaudeCodeDispatching();
}

/// Session is running and accepting status polls / WS events.
class ClaudeCodeActive extends ClaudeCodeState {
  final ClaudeCodeSession session;
  const ClaudeCodeActive( this.session );
  @override List<Object?> get props => [ session.taskId, session.status ];
}

/// Session is paused, awaiting user input inject.
class ClaudeCodeAwaitingInput extends ClaudeCodeState {
  final ClaudeCodeSession session;
  const ClaudeCodeAwaitingInput( this.session );
  @override List<Object?> get props => [ session.taskId ];
}

/// Session completed (success or interrupted).
class ClaudeCodeDone extends ClaudeCodeState {
  final ClaudeCodeSession session;
  const ClaudeCodeDone( this.session );
  @override List<Object?> get props => [ session.taskId, session.costUsd ];
}

/// BOUNDED job was queued via CJ Flow.
class ClaudeCodeQueued extends ClaudeCodeState {
  final ClaudeCodeQueueResponse response;
  const ClaudeCodeQueued( this.response );
  @override List<Object?> get props => [ response.jobId ];
}

class ClaudeCodeError extends ClaudeCodeState {
  final String message;
  const ClaudeCodeError( this.message );
  @override List<Object?> get props => [ message ];
}
