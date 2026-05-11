import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/claude_code/data/claude_code_models.dart';
import 'package:lupin_mobile/features/claude_code/data/claude_code_repository.dart';
import 'package:lupin_mobile/features/claude_code/domain/claude_code_bloc.dart';
import 'package:lupin_mobile/features/claude_code/domain/claude_code_event.dart';
import 'package:lupin_mobile/features/claude_code/domain/claude_code_state.dart';

import '../_helpers/stub_dio.dart';

void main() {
  group( 'ClaudeCodeBloc', () {
    late StubAdapter adapter;
    late ClaudeCodeRepository repo;

    setUp( () {
      adapter = StubAdapter();
      repo    = ClaudeCodeRepository( makeDio( adapter ) );
    } );

    blocTest<ClaudeCodeBloc, ClaudeCodeState>(
      'ClaudeCodeSubmit emits Submitting → Submitted',
      setUp: () {
        adapter.handlers[ 'POST /api/claude-code/submit' ] = ( _ ) => jsonBody( {
          'status'        : 'queued',
          'job_id'        : 'cc-1',
          'queue_position': 2,
          'message'       : 'ok',
        } );
      },
      build : () => ClaudeCodeBloc( repo ),
      act   : ( b ) => b.add(
        ClaudeCodeSubmit( ClaudeCodeSubmitRequest( prompt: 'bounded' ) ),
      ),
      wait  : const Duration( milliseconds: 50 ),
      expect: () => [
        isA<ClaudeCodeSubmitting>(),
        isA<ClaudeCodeSubmitted>()
          .having( ( s ) => s.response.jobId, 'jobId', 'cc-1' ),
      ],
    );

    blocTest<ClaudeCodeBloc, ClaudeCodeState>(
      'ClaudeCodeSubmit emits Submitting → Error on HTTP 500',
      setUp: () {
        adapter.handlers[ 'POST /api/claude-code/submit' ] = ( _ ) =>
            jsonBody( { 'detail': 'fail' }, status: 500 );
      },
      build : () => ClaudeCodeBloc( repo ),
      act   : ( b ) => b.add(
        ClaudeCodeSubmit( ClaudeCodeSubmitRequest( prompt: 'x' ) ),
      ),
      wait  : const Duration( milliseconds: 50 ),
      expect: () => [
        isA<ClaudeCodeSubmitting>(),
        isA<ClaudeCodeError>()
          .having( ( s ) => s.message, 'message', 'fail' ),
      ],
    );
  } );
}
