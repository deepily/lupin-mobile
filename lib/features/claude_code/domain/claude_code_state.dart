import 'package:equatable/equatable.dart';

import '../data/claude_code_models.dart';

/// Base class for the states of the Claude Code bloc.
abstract class ClaudeCodeState extends Equatable {
  /// Creates a state.
  const ClaudeCodeState();
  @override List<Object?> get props => [];
}

/// Nothing has been submitted yet.
class ClaudeCodeInitial extends ClaudeCodeState {
  /// Creates the initial state.
  const ClaudeCodeInitial();
}

/// A submission is in flight.
class ClaudeCodeSubmitting extends ClaudeCodeState {
  /// Creates the submitting state.
  const ClaudeCodeSubmitting();
}

/// The server accepted the job.
class ClaudeCodeSubmitted extends ClaudeCodeState {
  /// The server's response, including the new job id.
  final ClaudeCodeSubmitResponse response;
  /// Creates the state for [response].
  const ClaudeCodeSubmitted( this.response );
  @override List<Object?> get props => [ response.jobId ];
}

/// The submission failed.
class ClaudeCodeError extends ClaudeCodeState {
  /// The error text to show the user.
  final String message;
  /// Creates the state for [message].
  const ClaudeCodeError( this.message );
  @override List<Object?> get props => [ message ];
}
