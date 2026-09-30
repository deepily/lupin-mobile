import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/claude_code_models.dart';
import '../data/claude_code_repository.dart';
import 'claude_code_event.dart';
import 'claude_code_state.dart';

/// BLoC for Claude Code submissions to `POST /api/claude-code/submit`.
/// Sole survivor of the 2026-05-05 dispatch-cluster retirement —
/// INTERACTIVE controls (inject/interrupt/end_session) return when parent's
/// ClaudeCodeJob gains them.
class ClaudeCodeBloc extends Bloc<ClaudeCodeEvent, ClaudeCodeState> {
  final ClaudeCodeRepository _repo;

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
