import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/fleet/data/task_row_model.dart';
import 'package:lupin_mobile/features/task_list/data/task_list_model.dart';
import 'package:lupin_mobile/features/task_list/data/task_list_repository.dart';
import 'package:lupin_mobile/features/task_list/data/task_lookup.dart';

import '../_helpers/stub_dio.dart';

TaskRowModel _row( String id, String status, { DateTime? chase } ) =>
    TaskRowModel( id: id, title: id, status: status, nextChaseTs: chase );

void main() {
  group( 'classifyTaskRef — mirrors the web and the server', () {
    test( 'the server minimum is 4 hex characters', () {
      // Pinned to `MIN_TASK_REF_PREFIX_LEN` in task-lookup.js and the Python rule.
      expect( minTaskRefPrefixLen, 4 );
      expect( classifyTaskRef( 'abc' ).kind, TaskRefKind.invalid );
      expect( classifyTaskRef( 'abcd' ).kind, TaskRefKind.prefix );
    } );

    test( 'a canonical UUID is full and keeps its hyphens, lowercased', () {
      final r = classifyTaskRef( '  323D0F9C-71CE-4D51-BF69-524A7F95A733 ' );
      expect( r.kind, TaskRefKind.full );
      expect( r.value, '323d0f9c-71ce-4d51-bf69-524a7f95a733' );
    } );

    test( '32 bare hex is full', () {
      expect( classifyTaskRef( '323d0f9c71ce4d51bf69524a7f95a733' ).kind, TaskRefKind.full );
    } );

    test( 'a partly copied UUID is a prefix with the hyphens stripped', () {
      final r = classifyTaskRef( '323d0f9c-71ce' );
      expect( r.kind, TaskRefKind.prefix );
      expect( r.value, '323d0f9c71ce' );
    } );

    test( 'junk never becomes a prefix — this is a lookup, not a search', () {
      for ( final junk in [ null, '', '   ', 'holding area', 'zzzz', '#323d', '12 34' ] ) {
        expect( classifyTaskRef( junk ).kind, TaskRefKind.invalid, reason: 'for "$junk"' );
        expect( taskLookupPath( junk ), isNull, reason: 'for "$junk"' );
      }
    } );
  } );

  group( 'taskLookupPath — the single-row endpoint, never the board query', () {
    test( 'builds /api/tasks/<ref> from the normalized value', () {
      expect( taskLookupPath( 'ABCD-EF01' ), '/api/tasks/abcdef01' );
    } );

    test( '🔴 never the id_prefix query, which hides holding-area rows', () {
      final path = taskLookupPath( '323d0f9c' )!;
      expect( path, isNot( contains( 'id_prefix' ) ) );
      expect( path, isNot( contains( '?' ) ) );
    } );
  } );

  group( 'describeLookupFailure', () {
    test( '404 names what was typed', () {
      expect( describeLookupFailure( 'dead', const TaskLookupException( 404 ) ),
          'No ticket matches "dead".' );
    } );

    test( '422 passes the server detail through — it names the candidates', () {
      const detail = 'ambiguous prefix: matches 323d0f9c…, 323d1111…';
      expect( describeLookupFailure( '323d', const TaskLookupException( 422, detail: detail ) ),
          detail );
    } );

    test( '401 asks the user to sign back in', () {
      expect( describeLookupFailure( 'dead', const TaskLookupException( 401 ) ),
          taskLookupAuthRequiredMessage );
    } );

    test( 'a 5xx and no-response say the store did not answer, never the raw text', () {
      expect( describeLookupFailure( 'dead', const TaskLookupException( 500, detail: 'Traceback' ) ),
          taskLookupUnreachableMessage );
      expect( describeLookupFailure( 'dead', const TaskLookupException( 0 ) ),
          taskLookupUnreachableMessage );
    } );
  } );

  group( 'TaskListRepository.lookup — what goes on the wire', () {
    late StubAdapter adapter;
    late TaskListRepository repo;

    setUp( () {
      adapter = StubAdapter();
      repo    = TaskListRepository( makeDio( adapter ) );
    } );

    test( 'a 200 returns the full row, held status included', () async {
      adapter.handlers[ 'GET /api/tasks/323d0f9c' ] = ( _ ) => jsonBody( {
        'id'     : '323d0f9c-71ce-4d51-bf69-524a7f95a733',
        'title'  : 'a held row',
        'status' : 'not_approved',
        'body'   : 'the detail',
      } );

      final row = await repo.lookup( taskLookupPath( '323d0f9c' )! );

      expect( row.status, 'not_approved' );
      expect( row.detail, 'the detail' );
      expect( adapter.captured.single.path, '/api/tasks/323d0f9c' );
    } );

    test( 'a 404 becomes a TaskLookupException carrying the status', () async {
      await expectLater(
        repo.lookup( '/api/tasks/dead' ),
        throwsA( isA<TaskLookupException>().having( ( e ) => e.status, 'status', 404 ) ),
      );
    } );

    test( 'a 422 carries the server detail', () async {
      adapter.handlers[ 'GET /api/tasks/323d' ] =
          ( _ ) => jsonBody( { 'detail': 'ambiguous' }, status: 422 );

      await expectLater(
        repo.lookup( '/api/tasks/323d' ),
        throwsA( isA<TaskLookupException>()
            .having( ( e ) => e.status, 'status', 422 )
            .having( ( e ) => e.detail, 'detail', 'ambiguous' ) ),
      );
    } );
  } );

  group( 'taskListCountLabel — the M1 headline', () {
    final now = DateTime.utc( 2026, 9, 24, 12 );

    test( 'no parked rows reads "Live: L" alone, not a zero-padded triple', () {
      final model = groupTasksByOwner( [ _row( 'a', 'queued' ), _row( 'b', 'in_progress' ) ] );
      expect( taskListCountLabel( model, now ), 'Live: 2' );
    } );

    test( 'a park-active row splits the headline', () {
      final model = groupTasksByOwner( [
        _row( 'a', 'queued' ),
        _row( 'b', 'parked', chase: now.add( const Duration( days: 3 ) ) ),
      ] );
      expect( taskListCountLabel( model, now ), 'Live: 1 · Parked: 1 · Total: 2' );
    } );

    test( 'a parked row whose chase has passed counts as LIVE, as the store does', () {
      final model = groupTasksByOwner( [
        _row( 'a', 'parked', chase: now.subtract( const Duration( minutes: 1 ) ) ),
        _row( 'b', 'parked' ),
      ] );
      expect( taskListCountLabel( model, now ), 'Live: 2' );
    } );

    test( 'an empty board is "Live: 0"', () {
      expect( taskListCountLabel( groupTasksByOwner( const [] ), now ), 'Live: 0' );
    } );
  } );
}
