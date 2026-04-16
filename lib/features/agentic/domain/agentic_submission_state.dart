import 'package:equatable/equatable.dart';

import '../data/agentic_common_models.dart';

abstract class AgenticSubmissionState extends Equatable {
  const AgenticSubmissionState();
  @override
  List<Object?> get props => [];
}

class AgenticSubmissionInitial extends AgenticSubmissionState {
  const AgenticSubmissionInitial();
}

class AgenticSubmissionInProgress extends AgenticSubmissionState {
  const AgenticSubmissionInProgress();
}

class AgenticSubmissionSuccess extends AgenticSubmissionState {
  final AgenticJobType type;
  final String         jobId;
  final int            queuePosition;

  const AgenticSubmissionSuccess( {
    required this.type,
    required this.jobId,
    required this.queuePosition,
  } );

  @override
  List<Object?> get props => [ type, jobId, queuePosition ];
}

/// Distinct success state for TFE resume-from (carries extra fields).
class TfeResumeSuccess extends AgenticSubmissionState {
  final TfeResumeResponse response;

  const TfeResumeSuccess( this.response );

  @override
  List<Object?> get props => [ response.resumedJobId ];
}

class AgenticSubmissionFailure extends AgenticSubmissionState {
  final String error;

  const AgenticSubmissionFailure( this.error );

  @override
  List<Object?> get props => [ error ];
}
