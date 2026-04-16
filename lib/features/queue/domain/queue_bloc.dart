import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/queue_models.dart';
import '../data/queue_repository.dart';
import 'queue_event.dart';
import 'queue_state.dart';

/// Repository-backed queue BLoC. Replaces the prior WS-only skeleton with
/// real REST integration against the 14-endpoint CJ Flow queue API.
class QueueBloc extends Bloc<QueueEvent, QueueState> {
  final QueueRepository _repo;

  // Track context so external updates can refresh the right view.
  String? _activeQueueName;

  QueueBloc( this._repo ) : super( const QueueInitial() ) {
    on<QueueLoadSnapshot>( _onLoadSnapshot );
    on<QueueLoadHistory>( _onLoadHistory );
    on<QueueLoadInteractions>( _onLoadInteractions );
    on<QueueExternalUpdate>( _onExternalUpdate );
    on<QueueSubmitJob>( _onSubmitJob );
    on<QueueSubmitAgenticJob>( _onSubmitAgenticJob );
    on<QueueCancelJob>( _onCancelJob );
    on<QueuePauseJob>( _onPauseJob );
    on<QueueResumeJob>( _onResumeJob );
    on<QueueDeleteJob>( _onDeleteJob );
    on<QueueRetryJob>( _onRetryJob );
    on<QueueResumeFromCheckpoint>( _onResumeFromCheckpoint );
    on<QueueInjectMessage>( _onInjectMessage );
  }

  Future<void> _onLoadSnapshot(
    QueueLoadSnapshot event,
    Emitter<QueueState> emit,
  ) async {
    _activeQueueName = event.queueName;
    emit( const QueueLoading() );
    try {
      final snapshot = await _repo.getQueue( event.queueName );
      emit( QueueSnapshotLoaded( snapshot ) );
    } on QueueApiException catch ( e ) {
      emit( QueueError( e.message ) );
    }
  }

  Future<void> _onLoadHistory(
    QueueLoadHistory event,
    Emitter<QueueState> emit,
  ) async {
    _activeQueueName = null;  // history is not a queue snapshot
    emit( const QueueLoading() );
    try {
      final page = await _repo.getJobHistory(
        status  : event.status,
        jobType : event.jobType,
        limit   : event.limit,
        offset  : event.offset,
      );
      emit( QueueHistoryLoaded( page ) );
    } on QueueApiException catch ( e ) {
      emit( QueueError( e.message ) );
    }
  }

  Future<void> _onLoadInteractions(
    QueueLoadInteractions event,
    Emitter<QueueState> emit,
  ) async {
    emit( const QueueLoading() );
    try {
      final data = await _repo.getJobInteractions( event.jobId );
      emit( QueueInteractionsLoaded( data ) );
    } on QueueApiException catch ( e ) {
      emit( QueueError( e.message ) );
    }
  }

  /// WS-driven refresh — re-fetch without emitting a loading state so the
  /// UI doesn't flash. No-op if no snapshot is currently active.
  Future<void> _onExternalUpdate(
    QueueExternalUpdate event,
    Emitter<QueueState> emit,
  ) async {
    final target = _activeQueueName ?? event.queueName;
    if ( state is! QueueSnapshotLoaded ) return;
    try {
      final snapshot = await _repo.getQueue( target );
      emit( QueueSnapshotLoaded( snapshot ) );
    } on QueueApiException catch ( _ ) {
      // Keep last good state silently — refresh is best-effort.
    }
  }

  Future<void> _onSubmitJob(
    QueueSubmitJob event,
    Emitter<QueueState> emit,
  ) async {
    emit( const QueueSubmitting() );
    try {
      final res = await _repo.push( event.request );
      emit( QueueSubmitted( res ) );
    } on QueueApiException catch ( e ) {
      emit( QueueError( e.message ) );
    }
  }

  Future<void> _onSubmitAgenticJob(
    QueueSubmitAgenticJob event,
    Emitter<QueueState> emit,
  ) async {
    emit( const QueueSubmitting() );
    try {
      final res = await _repo.pushAgentic( event.request );
      emit( QueueSubmitted( res ) );
    } on QueueApiException catch ( e ) {
      emit( QueueError( e.message ) );
    }
  }

  Future<void> _onCancelJob(
    QueueCancelJob event,
    Emitter<QueueState> emit,
  ) async {
    try {
      await _repo.cancelJob( event.jobId );
      emit( const QueueActionComplete( 'Cancel requested' ) );
    } on QueueApiException catch ( e ) {
      emit( QueueError( e.message ) );
    }
  }

  Future<void> _onPauseJob(
    QueuePauseJob event,
    Emitter<QueueState> emit,
  ) async {
    try {
      await _repo.pauseJob( event.jobId );
      emit( const QueueActionComplete( 'Job paused' ) );
    } on QueueApiException catch ( e ) {
      emit( QueueError( e.message ) );
    }
  }

  Future<void> _onResumeJob(
    QueueResumeJob event,
    Emitter<QueueState> emit,
  ) async {
    try {
      await _repo.resumeJob( event.jobId );
      emit( const QueueActionComplete( 'Job resumed' ) );
    } on QueueApiException catch ( e ) {
      emit( QueueError( e.message ) );
    }
  }

  Future<void> _onDeleteJob(
    QueueDeleteJob event,
    Emitter<QueueState> emit,
  ) async {
    try {
      await _repo.deleteJob( event.queueName, event.jobId );
      emit( const QueueActionComplete( 'Job deleted' ) );
      if ( _activeQueueName != null ) {
        add( QueueExternalUpdate( _activeQueueName! ) );
      }
    } on QueueApiException catch ( e ) {
      emit( QueueError( e.message ) );
    }
  }

  Future<void> _onRetryJob(
    QueueRetryJob event,
    Emitter<QueueState> emit,
  ) async {
    try {
      final res = await _repo.retryJob( event.jobId, event.websocketId );
      emit( QueueActionComplete( 'Retried as ${res.status}' ) );
    } on QueueApiException catch ( e ) {
      emit( QueueError( e.message ) );
    }
  }

  Future<void> _onResumeFromCheckpoint(
    QueueResumeFromCheckpoint event,
    Emitter<QueueState> emit,
  ) async {
    try {
      final res = await _repo.resumeFromCheckpoint( event.idHash );
      emit( QueueActionComplete( 'Resumed from phase ${res.phaseName ?? res.resumeFromPhase}' ) );
    } on QueueApiException catch ( e ) {
      emit( QueueError( e.message ) );
    }
  }

  Future<void> _onInjectMessage(
    QueueInjectMessage event,
    Emitter<QueueState> emit,
  ) async {
    try {
      await _repo.injectMessage( event.jobId, event.message, priority: event.priority );
      emit( const QueueActionComplete( 'Message delivered' ) );
    } on QueueApiException catch ( e ) {
      emit( QueueError( e.message ) );
    }
  }
}
