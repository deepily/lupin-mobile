import 'package:equatable/equatable.dart';

import '../data/agentic_common_models.dart';

abstract class AgenticSubmissionEvent extends Equatable {
  const AgenticSubmissionEvent();
  @override
  List<Object?> get props => [];
}

/// Submit any agentic job. [request] is the typed request object for [type].
class AgenticSubmitRequested extends AgenticSubmissionEvent {
  final AgenticJobType type;
  final dynamic        request;

  const AgenticSubmitRequested( { required this.type, required this.request } );

  @override
  List<Object?> get props => [ type, request ];
}

/// Reset bloc to initial state (called when form is opened/closed).
class AgenticFormReset extends AgenticSubmissionEvent {
  const AgenticFormReset();
}
