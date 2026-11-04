import 'package:equatable/equatable.dart';

import '../data/agentic_common_models.dart';

/// Base class of the events a submission form sends.
abstract class AgenticSubmissionEvent extends Equatable {
  /// Creates an event.
  const AgenticSubmissionEvent();
  @override
  List<Object?> get props => [];
}

/// Submits an agentic job; [request] is the typed request object for [type].
class AgenticSubmitRequested extends AgenticSubmissionEvent {
  /// Which kind of job to submit.
  final AgenticJobType type;
  /// The request object matching [type].
  final dynamic        request;

  /// Creates a submit event for [type] carrying [request].
  const AgenticSubmitRequested( { required this.type, required this.request } );

  @override
  List<Object?> get props => [ type, request ];
}

/// Resets the bloc to its initial state when a form opens or closes.
class AgenticFormReset extends AgenticSubmissionEvent {
  /// Creates a reset event.
  const AgenticFormReset();
}
