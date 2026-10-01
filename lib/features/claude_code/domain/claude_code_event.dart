import 'package:equatable/equatable.dart';

import '../data/claude_code_models.dart';

/// Base class for events handled by the Claude Code bloc.
abstract class ClaudeCodeEvent extends Equatable {
  /// Creates an event.
  const ClaudeCodeEvent();
  @override List<Object?> get props => [];
}

/// Asks the bloc to submit a Claude Code job.
class ClaudeCodeSubmit extends ClaudeCodeEvent {
  /// The job to submit.
  final ClaudeCodeSubmitRequest request;
  /// Creates the event for [request].
  const ClaudeCodeSubmit( this.request );
  @override List<Object?> get props => [ request.prompt ];
}
