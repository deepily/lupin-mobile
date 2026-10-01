import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/claude_code_models.dart';
import '../data/claude_code_repository.dart';
import 'claude_code_event.dart';
import 'claude_code_state.dart';

/// Submits Claude Code jobs to the queue endpoint and reports the outcome.
///
/// Submission is the only operation. Interactive controls (inject, interrupt,
/// end session) are not offered, because the server job has no such methods.
class ClaudeCodeBloc extends Bloc<ClaudeCodeEvent, ClaudeCodeState> {
  final ClaudeCodeRepository _repo;

  /// Creates the bloc over [_repo], starting in the initial state.
  ClaudeCodeBloc( this._repo ) : super( const ClaudeCodeInitial() ) {
    on<ClaudeCodeSubmit>( _onSubmit );
  }

  Future<void> _onSubmit(
    ClaudeCodeSubmit event,
    Emitter<ClaudeCodeState> emit,
  ) async {
    emit( const ClaudeCodeSubmitting() );
    try {
      final res = await _repo.submit( event.request );
      emit( ClaudeCodeSubmitted( res ) );
    } on ClaudeCodeApiException catch ( e ) {
      emit( ClaudeCodeError( e.message ) );
    }
  }
}
