import 'package:equatable/equatable.dart';

import '../data/agentic_common_models.dart';

/// Base class of the states of a submission form.
abstract class AgenticSubmissionState extends Equatable {
  /// Creates a state.
  const AgenticSubmissionState();
  @override
  List<Object?> get props => [];
}

/// Nothing has been submitted yet.
class AgenticSubmissionInitial extends AgenticSubmissionState {
  /// Creates the initial state.
  const AgenticSubmissionInitial();
}

/// A submit call is in flight.
class AgenticSubmissionInProgress extends AgenticSubmissionState {
  /// Creates the in-progress state.
  const AgenticSubmissionInProgress();
}

/// The server accepted the job.
class AgenticSubmissionSuccess extends AgenticSubmissionState {
  /// Kind of job that was created.
  final AgenticJobType type;
  /// Id of the created job.
  final String         jobId;
  /// Place in the queue; 0 when the server reports none.
  final int            queuePosition;

  /// Creates a success state for the created job.
  const AgenticSubmissionSuccess( {
    required this.type,
    required this.jobId,
    required this.queuePosition,
  } );

  @override
  List<Object?> get props => [ type, jobId, queuePosition ];
}

/// Success state for a test-fix-expediter resume, which carries extra fields.
class TfeResumeSuccess extends AgenticSubmissionState {
  /// The resume response from the server.
  final TfeResumeResponse response;

  /// Creates a success state holding [response].
  const TfeResumeSuccess( this.response );

  @override
  List<Object?> get props => [ response.resumedJobId ];
}

/// The submit call failed.
class AgenticSubmissionFailure extends AgenticSubmissionState {
  /// Message to show the user.
  final String error;

  /// Creates a failure state with an error message.
  const AgenticSubmissionFailure( this.error );

  @override
  List<Object?> get props => [ error ];
}
