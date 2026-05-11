import 'package:equatable/equatable.dart';

import '../data/claude_code_models.dart';

abstract class ClaudeCodeEvent extends Equatable {
  const ClaudeCodeEvent();
  @override List<Object?> get props => [];
}

class ClaudeCodeSubmit extends ClaudeCodeEvent {
  final ClaudeCodeSubmitRequest request;
  const ClaudeCodeSubmit( this.request );
  @override List<Object?> get props => [ request.prompt ];
}
