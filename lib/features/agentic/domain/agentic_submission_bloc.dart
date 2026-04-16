import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/agentic_common_models.dart';
import '../data/agentic_repository.dart';
import '../data/bug_fix_expediter_models.dart';
import '../data/chained_models.dart';
import '../data/deep_research_models.dart';
import '../data/podcast_models.dart';
import '../data/presentation_models.dart';
import '../data/swe_team_models.dart';
import '../data/test_fix_expediter_models.dart';
import '../data/test_suite_models.dart';
import 'agentic_submission_event.dart';
import 'agentic_submission_state.dart';

/// Single BLoC for all 9 agentic job submission forms.
/// All forms share the same request → response lifecycle:
///   submit → InProgress → Success(jobId) → navigate to JobDetailScreen.
class AgenticSubmissionBloc
    extends Bloc<AgenticSubmissionEvent, AgenticSubmissionState> {
  final AgenticRepository _repo;

  AgenticSubmissionBloc( this._repo ) : super( const AgenticSubmissionInitial() ) {
    on<AgenticSubmitRequested>( _onSubmitRequested );
    on<AgenticFormReset>( ( _, emit ) => emit( const AgenticSubmissionInitial() ) );
  }

  Future<void> _onSubmitRequested(
    AgenticSubmitRequested event,
    Emitter<AgenticSubmissionState> emit,
  ) async {
    emit( const AgenticSubmissionInProgress() );
    try {
      switch ( event.type ) {
        case AgenticJobType.deepResearch:
          final res = await _repo.submitDeepResearch( event.request as DeepResearchRequest );
          emit( AgenticSubmissionSuccess(
            type          : event.type,
            jobId         : res.jobId,
            queuePosition : res.queuePosition,
          ) );

        case AgenticJobType.podcast:
          final res = await _repo.submitPodcast( event.request as PodcastGeneratorRequest );
          emit( AgenticSubmissionSuccess(
            type          : event.type,
            jobId         : res.jobId,
            queuePosition : res.queuePosition,
          ) );

        case AgenticJobType.presentation:
          final res = await _repo.submitPresentation( event.request as PresentationGeneratorRequest );
          emit( AgenticSubmissionSuccess(
            type          : event.type,
            jobId         : res.jobId,
            queuePosition : res.queuePosition,
          ) );

        case AgenticJobType.sweTeam:
          final res = await _repo.submitSweTeam( event.request as SweTeamRequest );
          emit( AgenticSubmissionSuccess(
            type          : event.type,
            jobId         : res.jobId,
            queuePosition : res.queuePosition,
          ) );

        case AgenticJobType.bugFixExpediter:
          final res = await _repo.submitBugFixExpediter( event.request as BugFixExpediterRequest );
          emit( AgenticSubmissionSuccess(
            type          : event.type,
            jobId         : res.jobId,
            queuePosition : res.queuePosition,
          ) );

        case AgenticJobType.testSuite:
          final res = await _repo.submitTestSuite( event.request as TestSuiteRequest );
          emit( AgenticSubmissionSuccess(
            type          : event.type,
            jobId         : res.jobId,
            queuePosition : res.queuePosition,
          ) );

        case AgenticJobType.testFixExpediter:
          final res = await _repo.resumeTestFixExpediter( event.request as TfeResumeFromRequest );
          emit( TfeResumeSuccess( res ) );

        case AgenticJobType.researchToPodcast:
          final res = await _repo.submitResearchToPodcast( event.request as ResearchToPodcastRequest );
          emit( AgenticSubmissionSuccess(
            type          : event.type,
            jobId         : res.jobId,
            queuePosition : res.queuePosition,
          ) );

        case AgenticJobType.researchToPresentation:
          final res = await _repo.submitResearchToPresentation(
            event.request as ResearchToPresentationRequest,
          );
          emit( AgenticSubmissionSuccess(
            type          : event.type,
            jobId         : res.jobId,
            queuePosition : res.queuePosition,
          ) );
      }
    } on AgenticApiException catch ( e ) {
      emit( AgenticSubmissionFailure( e.message ) );
    } catch ( e ) {
      emit( AgenticSubmissionFailure( e.toString() ) );
    }
  }
}
