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
      'ClaudeCodeDispatch emits Dispatching → Active',
      setUp: () {
        adapter.handlers[ 'POST /api/claude-code/dispatch' ] = ( _ ) =>
            jsonBody( { 'task_id': 't-1', 'status': 'running' } );
      },
      build : () => ClaudeCodeBloc( repo ),
      act   : ( b ) => b.add(
        ClaudeCodeDispatch(
          ClaudeCodeDispatchRequest( prompt: 'go', taskType: ClaudeCodeTaskType.interactive ),
        ),
      ),
      wait  : const Duration( milliseconds: 50 ),
      expect: () => [
        isA<ClaudeCodeDispatching>(),
        isA<ClaudeCodeActive>()
          .having( ( s ) => s.session.taskId, 'taskId', 't-1' ),
      ],
    );

    blocTest<ClaudeCodeBloc, ClaudeCodeState>(
      'ClaudeCodeDispatch with awaiting_input maps to AwaitingInput',
      setUp: () {
        adapter.handlers[ 'POST /api/claude-code/dispatch' ] = ( _ ) =>
            jsonBody( { 'task_id': 't-2', 'status': 'awaiting_input' } );
      },
      build : () => ClaudeCodeBloc( repo ),
      act   : ( b ) => b.add(
        ClaudeCodeDispatch(
          ClaudeCodeDispatchRequest( prompt: 'ask me', taskType: ClaudeCodeTaskType.interactive ),
        ),
      ),
      wait  : const Duration( milliseconds: 50 ),
      expect: () => [
        isA<ClaudeCodeDispatching>(),
        isA<ClaudeCodeAwaitingInput>(),
      ],
    );

    blocTest<ClaudeCodeBloc, ClaudeCodeState>(
      'ClaudeCodeDispatch emits Error on 500',
      setUp: () {
        adapter.handlers[ 'POST /api/claude-code/dispatch' ] = ( _ ) =>
            jsonBody( { 'detail': 'fail' }, status: 500 );
      },
      build : () => ClaudeCodeBloc( repo ),
      act   : ( b ) => b.add(
        ClaudeCodeDispatch(
          ClaudeCodeDispatchRequest( prompt: 'x', taskType: ClaudeCodeTaskType.interactive ),
        ),
      ),
      wait  : const Duration( milliseconds: 50 ),
      expect: () => [
        isA<ClaudeCodeDispatching>(),
        isA<ClaudeCodeError>(),
      ],
    );

    blocTest<ClaudeCodeBloc, ClaudeCodeState>(
      'ClaudeCodeQueueSubmit emits Dispatching → Queued',
      setUp: () {
        adapter.handlers[ 'POST /api/claude-code/queue/submit' ] = ( _ ) => jsonBody( {
          'status'        : 'queued',
          'job_id'        : 'cj-1',
          'queue_position': 2,
          'message'       : 'ok',
        } );
      },
      build : () => ClaudeCodeBloc( repo ),
      act   : ( b ) => b.add(
        ClaudeCodeQueueSubmit( ClaudeCodeQueueRequest( prompt: 'bounded' ) ),
      ),
      wait  : const Duration( milliseconds: 50 ),
      expect: () => [
        isA<ClaudeCodeDispatching>(),
        isA<ClaudeCodeQueued>()
          .having( ( s ) => s.response.jobId, 'jobId', 'cj-1' ),
      ],
    );

    blocTest<ClaudeCodeBloc, ClaudeCodeState>(
      'ClaudeCodeInject optimistically transitions AwaitingInput → Active',
      setUp: () {
        adapter.handlers[ 'POST /api/claude-code/t-3/inject' ] = ( _ ) =>
            jsonBody( { 'status': 'ok', 'task_id': 't-3' } );
      },
      build: () => ClaudeCodeBloc( repo ),
      seed : () => ClaudeCodeAwaitingInput(
        ClaudeCodeSession.fromJson( { 'task_id': 't-3', 'status': 'awaiting_input' } ),
      ),
      act  : ( b ) => b.add( const ClaudeCodeInject( taskId: 't-3', message: 'yes' ) ),
      wait : const Duration( milliseconds: 50 ),
      expect: () => [
        isA<ClaudeCodeActive>()
          .having( ( s ) => s.session.status, 'status', 'running' ),
      ],
    );

    blocTest<ClaudeCodeBloc, ClaudeCodeState>(
      'ClaudeCodeEnd emits Done with status ended',
      setUp: () {
        adapter.handlers[ 'POST /api/claude-code/t-4/end' ] = ( _ ) =>
            jsonBody( { 'status': 'ended' } );
      },
      build: () => ClaudeCodeBloc( repo ),
      seed : () => ClaudeCodeActive(
        ClaudeCodeSession.fromJson( { 'task_id': 't-4', 'status': 'running' } ),
      ),
      act  : ( b ) => b.add( const ClaudeCodeEnd( 't-4' ) ),
      wait : const Duration( milliseconds: 50 ),
      expect: () => [
        isA<ClaudeCodeDone>()
          .having( ( s ) => s.session.status, 'status', 'ended' ),
      ],
    );
  } );
}
