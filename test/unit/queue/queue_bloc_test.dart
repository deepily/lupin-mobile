import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/queue/data/queue_models.dart';
import 'package:lupin_mobile/features/queue/data/queue_repository.dart';
import 'package:lupin_mobile/features/queue/domain/queue_bloc.dart';
import 'package:lupin_mobile/features/queue/domain/queue_event.dart';
import 'package:lupin_mobile/features/queue/domain/queue_state.dart';

import '../_helpers/stub_dio.dart';

void main() {
  group( 'QueueBloc', () {
    late StubAdapter adapter;
    late QueueRepository repo;

    setUp( () {
      adapter = StubAdapter();
      repo    = QueueRepository( makeDio( adapter ) );
    } );

    blocTest<QueueBloc, QueueState>(
      'QueueLoadSnapshot emits Loading → SnapshotLoaded',
      setUp: () {
        adapter.handlers[ 'GET /api/get-queue/todo' ] = ( _ ) => jsonBody( {
          'todo_jobs_metadata': [
            { 'job_id': 'j-1', 'question_text': 'hi', 'agent_type': 'A', 'status': 'todo', 'paused': false },
          ],
        } );
      },
      build : () => QueueBloc( repo ),
      act   : ( b ) => b.add( const QueueLoadSnapshot( 'todo' ) ),
      wait  : const Duration( milliseconds: 50 ),
      expect: () => [
        isA<QueueLoading>(),
        isA<QueueSnapshotLoaded>()
          .having( ( s ) => s.snapshot.queueName,  'name',  'todo' )
          .having( ( s ) => s.snapshot.jobs.length, 'count', 1 ),
      ],
    );

    blocTest<QueueBloc, QueueState>(
      'QueueSubmitJob emits Submitting → Submitted',
      setUp: () {
        adapter.handlers[ 'POST /api/push' ] = ( _ ) => jsonBody( {
          'status'      : 'queued',
          'websocket_id': 'mobile',
          'user_id'     : 'u-1',
          'job_id'      : 'j-new',
        } );
      },
      build : () => QueueBloc( repo ),
      act   : ( b ) => b.add(
        QueueSubmitJob( PushJobRequest( question: 'hello', websocketId: 'mobile' ) ),
      ),
      wait  : const Duration( milliseconds: 50 ),
      expect: () => [
        isA<QueueSubmitting>(),
        isA<QueueSubmitted>().having( ( s ) => s.response.jobId, 'jobId', 'j-new' ),
      ],
    );

    blocTest<QueueBloc, QueueState>(
      'QueueCancelJob emits ActionComplete when server returns 200',
      setUp: () {
        adapter.handlers[ 'POST /api/jobs/j-1/cancel' ] = ( _ ) =>
            jsonBody( { 'status': 'cancelled' } );
      },
      build : () => QueueBloc( repo ),
      act   : ( b ) => b.add( const QueueCancelJob( 'j-1' ) ),
      wait  : const Duration( milliseconds: 50 ),
      expect: () => [
        isA<QueueActionComplete>(),
      ],
    );

    blocTest<QueueBloc, QueueState>(
      'QueueLoadSnapshot emits QueueError on 500',
      setUp: () {
        adapter.handlers[ 'GET /api/get-queue/run' ] = ( _ ) =>
            jsonBody( { 'detail': 'internal error' }, status: 500 );
      },
      build : () => QueueBloc( repo ),
      act   : ( b ) => b.add( const QueueLoadSnapshot( 'run' ) ),
      wait  : const Duration( milliseconds: 50 ),
      expect: () => [
        isA<QueueLoading>(),
        isA<QueueError>(),
      ],
    );

    blocTest<QueueBloc, QueueState>(
      'QueueExternalUpdate silently re-fetches when SnapshotLoaded',
      setUp: () {
        // First call returns empty list; second (after external update) returns one job.
        var callCount = 0;
        adapter.handlers[ 'GET /api/get-queue/todo' ] = ( _ ) {
          callCount++;
          if ( callCount == 1 ) {
            return jsonBody( { 'todo_jobs_metadata': [], 'total_jobs': 0 } );
          }
          return jsonBody( {
            'total_jobs'        : 1,
            'todo_jobs_metadata': [
              { 'job_id': 'j-2', 'question_text': 'x', 'agent_type': 'B', 'status': 'todo', 'paused': false },
            ],
          } );
        };
      },
      build : () => QueueBloc( repo ),
      act   : ( b ) async {
        b.add( const QueueLoadSnapshot( 'todo' ) );
        await Future<void>.delayed( const Duration( milliseconds: 30 ) );
        b.add( const QueueExternalUpdate( 'todo' ) );
      },
      wait  : const Duration( milliseconds: 80 ),
      expect: () => [
        isA<QueueLoading>(),
        isA<QueueSnapshotLoaded>().having( ( s ) => s.snapshot.jobs.length, 'empty', 0 ),
        isA<QueueSnapshotLoaded>().having( ( s ) => s.snapshot.jobs.length, 'count', 1 ),
      ],
    );
  } );
}
