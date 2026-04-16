import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/claude_code_models.dart';
import '../data/claude_code_repository.dart';
import 'claude_code_event.dart';
import 'claude_code_state.dart';

/// BLoC for interactive Claude Code sessions and BOUNDED queue submissions.
/// Uses the shared ClaudeCodeRepository against the 6-endpoint API.
class ClaudeCodeBloc extends Bloc<ClaudeCodeEvent, ClaudeCodeState> {
  final ClaudeCodeRepository _repo;

  ClaudeCodeBloc( this._repo ) : super( const ClaudeCodeInitial() ) {
    on<ClaudeCodeDispatch>( _onDispatch );
    on<ClaudeCodeQueueSubmit>( _onQueueSubmit );
    on<ClaudeCodePollStatus>( _onPollStatus );
    on<ClaudeCodeInject>( _onInject );
    on<ClaudeCodeInterrupt>( _onInterrupt );
    on<ClaudeCodeEnd>( _onEnd );
    on<ClaudeCodeExternalMessage>( _onExternalMessage );
  }

  Future<void> _onDispatch(
    ClaudeCodeDispatch event,
    Emitter<ClaudeCodeState> emit,
  ) async {
    emit( const ClaudeCodeDispatching() );
    try {
      final session = await _repo.dispatch( event.request );
      emit( _stateFromSession( session ) );
    } on ClaudeCodeApiException catch ( e ) {
      emit( ClaudeCodeError( e.message ) );
    }
  }

  Future<void> _onQueueSubmit(
    ClaudeCodeQueueSubmit event,
    Emitter<ClaudeCodeState> emit,
  ) async {
    emit( const ClaudeCodeDispatching() );
    try {
      final res = await _repo.queueSubmit( event.request );
      emit( ClaudeCodeQueued( res ) );
    } on ClaudeCodeApiException catch ( e ) {
      emit( ClaudeCodeError( e.message ) );
    }
  }

  Future<void> _onPollStatus(
    ClaudeCodePollStatus event,
    Emitter<ClaudeCodeState> emit,
  ) async {
    try {
      final session = await _repo.getStatus( event.taskId );
      emit( _stateFromSession( session ) );
    } on ClaudeCodeApiException catch ( e ) {
      emit( ClaudeCodeError( e.message ) );
    }
  }

  Future<void> _onInject(
    ClaudeCodeInject event,
    Emitter<ClaudeCodeState> emit,
  ) async {
    try {
      await _repo.inject( event.taskId, event.message );
      // Optimistically transition back to Active — next poll/WS event will
      // emit the real status.
      if ( state is ClaudeCodeAwaitingInput ) {
        final session = ( state as ClaudeCodeAwaitingInput ).session;
        emit( ClaudeCodeActive( session.copyWith( status: 'running' ) ) );
      }
    } on ClaudeCodeApiException catch ( e ) {
      emit( ClaudeCodeError( e.message ) );
    }
  }

  Future<void> _onInterrupt(
    ClaudeCodeInterrupt event,
    Emitter<ClaudeCodeState> emit,
  ) async {
    try {
      await _repo.interrupt( event.taskId );
    } on ClaudeCodeApiException catch ( e ) {
      emit( ClaudeCodeError( e.message ) );
    }
  }

  Future<void> _onEnd(
    ClaudeCodeEnd event,
    Emitter<ClaudeCodeState> emit,
  ) async {
    try {
      await _repo.endSession( event.taskId );
      // Emit done with current session data if available.
      final current = state;
      if ( current is ClaudeCodeActive ) {
        emit( ClaudeCodeDone( current.session.copyWith( status: 'ended' ) ) );
      } else if ( current is ClaudeCodeAwaitingInput ) {
        emit( ClaudeCodeDone( current.session.copyWith( status: 'ended' ) ) );
      } else {
        emit( const ClaudeCodeInitial() );
      }
    } on ClaudeCodeApiException catch ( e ) {
      emit( ClaudeCodeError( e.message ) );
    }
  }

  /// WS-driven: update state based on the incoming event payload.
  /// Filtered by task_id in the subscription manager — we trust the event
  /// belongs to the active session.
  Future<void> _onExternalMessage(
    ClaudeCodeExternalMessage event,
    Emitter<ClaudeCodeState> emit,
  ) async {
    // Poll for authoritative status when we receive any WS event.
    try {
      final session = await _repo.getStatus( event.taskId );
      emit( _stateFromSession( session ) );
    } on ClaudeCodeApiException catch ( _ ) {
      // Keep last good state — WS refresh is best-effort.
    }
  }

  /// Map backend session status string to BLoC state.
  ClaudeCodeState _stateFromSession( ClaudeCodeSession session ) {
    switch ( session.status ) {
      case 'awaiting_input':
        return ClaudeCodeAwaitingInput( session );
      case 'complete':
      case 'failed':
      case 'error':
      case 'interrupted':
      case 'ended':
        return ClaudeCodeDone( session );
      default:
        return ClaudeCodeActive( session );
    }
  }
}
