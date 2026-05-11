import 'package:equatable/equatable.dart';

import '../data/claude_code_models.dart';

abstract class ClaudeCodeState extends Equatable {
  const ClaudeCodeState();
  @override List<Object?> get props => [];
}

class ClaudeCodeInitial extends ClaudeCodeState {
  const ClaudeCodeInitial();
}

class ClaudeCodeSubmitting extends ClaudeCodeState {
  const ClaudeCodeSubmitting();
}

class ClaudeCodeSubmitted extends ClaudeCodeState {
  final ClaudeCodeSubmitResponse response;
  const ClaudeCodeSubmitted( this.response );
  @override List<Object?> get props => [ response.jobId ];
}

class ClaudeCodeError extends ClaudeCodeState {
  final String message;
  const ClaudeCodeError( this.message );
  @override List<Object?> get props => [ message ];
}
