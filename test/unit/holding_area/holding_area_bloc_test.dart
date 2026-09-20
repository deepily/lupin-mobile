import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/fleet/data/task_write_repository.dart';
import 'package:lupin_mobile/features/holding_area/data/holding_area_models.dart';
import 'package:lupin_mobile/features/holding_area/data/holding_area_repository.dart';
import 'package:lupin_mobile/features/holding_area/domain/holding_area_bloc.dart';

import '../_helpers/stub_dio.dart';

/// The Holding Area's bloc, with the BATCH path as the thing under test.
///
/// 🔴 THE BATCH IS WHERE THIS PANE CAN DO THE MOST DAMAGE AND THE LEAST VISIBLY. One
/// press moves every held row a filer filed. These tests assert what went ON THE WIRE —
/// how many transitions, to which ids, with which body — because a bloc that emitted a
/// pleasing state while sending three of fourteen writes is the exact failure the
/// operator cannot see from inside the pane.

Map<String, dynamic> _page( List<Map<String, dynamic>> rows, { bool hasMore = false } ) => {
      'tasks'     : rows,
      'truncated' : false,
      'has_more'  : hasMore,
      'total'     : rows.length,
      'warnings'  : <String>[],
    };

Map<String, dynamic> _row( String id, String filer ) => {
      'id'         : id,
      'title'      : 'held $id',
      'status'     : 'not_approved',
      'created_by' : filer,
    };

Map<String, dynamic> _fixture( String name ) =>
    jsonDecode( File( 'test/fixtures/tasks/$name' ).readAsStringSync() )
        as Map<String, dynamic>;

/// Every transition the adapter saw, as (id, decoded body).
List<( String, Map<String, dynamic> )> _transitions( StubAdapter adapter ) => adapter
    .captured
    .where( ( o ) => o.method == 'POST' && o.path.contains( '/transition' ) )
    .map( ( o ) => (
          Uri.decodeComponent( o.path.split( '/' )[ 3 ] ),
          ( o.data as Map ).cast<String, dynamic>(),
        ) )
    .toList();

void main() {
  late StubAdapter adapter;
  late HoldingAreaBloc bloc;

  /// Serve one held page, and let every transition succeed unless overridden.
  void servePage( List<Map<String, dynamic>> rows, { bool hasMore = false } ) {
    adapter.handlers[ 'GET ${HoldingAreaRepository.path}' ] =
        ( _ ) => jsonBody( _page( rows, hasMore: hasMore ) );
  }

  void serveTransitions( { int status = 200, dynamic body = const <String, dynamic>{} } ) {
    for ( final id in [ 'a', 'b', 'c', 'd' ] ) {
      adapter.handlers[ 'POST /api/tasks/$id/transition' ] =
          ( _ ) => jsonBody( body, status: status );
    }
  }

  Future<void> settle() => Future<void>.delayed( const Duration( milliseconds: 80 ) );

  setUp( () {
    adapter = StubAdapter();
    final dio = makeDio( adapter );
    bloc = HoldingAreaBloc( HoldingAreaRepository( dio ), TaskWriteRepository( dio ) );
  } );

  tearDown( () async => bloc.close() );

  group( "the refresh", () {
    test( "groups the page by filer", () async {
      servePage( [ _row( 'a', 'sam' ), _row( 'b', 'chloe' ), _row( 'c', 'sam' ) ] );

      bloc.add( const HoldingAreaRefreshRequested() );
      await settle();

      expect( bloc.state.groups.map( ( g ) => g.filer ).toList(), [ 'chloe', 'sam' ] );
      expect( bloc.state.groups.last.ids, [ 'a', 'c' ] );
      expect( bloc.state.loading, isFalse );
    } );

    test( "🔴 a cancelled poll leaves NO error — leaving a pane is not an outage", () async {
      adapter.handlers[ 'GET ${HoldingAreaRepository.path}' ] = ( _ ) =>
          throw DioException.requestCancelled(
            requestOptions : RequestOptions( path: HoldingAreaRepository.path ),
            reason         : 'pane hidden',
          );

      bloc.add( const HoldingAreaRefreshRequested() );
      await settle();

      expect( bloc.state.error, isNull );
      expect( bloc.state.loading, isFalse, reason: 'and it must not spin forever' );
    } );

    test( "an incomplete page sets the flag the banner reads", () async {
      servePage( [ _row( 'a', 'sam' ) ], hasMore: true );

      bloc.add( const HoldingAreaRefreshRequested() );
      await settle();

      expect( bloc.state.incomplete, isTrue );
    } );
  } );

  group( "the batch reason box", () {
    test( "🔴 won't-fix-all with an EMPTY box sends NOTHING and complains", () async {
      // The whole point of the client-side check: the alternative is N identical 422s
      // the operator must read one at a time to learn a single fact.
      servePage( [ _row( 'a', 'sam' ), _row( 'b', 'sam' ) ] );
      serveTransitions();
      bloc.add( const HoldingAreaRefreshRequested() );
      await settle();

      bloc.add( const HoldingAreaWontFixAllPressed( filer: 'sam', reason: '   ' ) );
      await settle();

      expect( _transitions( adapter ), isEmpty, reason: 'not one write may leave' );
      expect( bloc.state.reasonErrors[ 'sam' ], kHoldingWontFixReasonMissing );
    } );

    test( "typing clears the complaint", () async {
      servePage( [ _row( 'a', 'sam' ) ] );
      serveTransitions();
      bloc.add( const HoldingAreaRefreshRequested() );
      await settle();

      bloc.add( const HoldingAreaWontFixAllPressed( filer: 'sam', reason: '' ) );
      await settle();
      expect( bloc.state.reasonErrors[ 'sam' ], isNotNull );

      bloc.add( const HoldingAreaReasonChanged( filer: 'sam', reason: 'sup' ) );
      await settle();

      expect( bloc.state.reasonErrors[ 'sam' ], isNull );
      expect( bloc.state.reasonFor( 'sam' ), 'sup' );
    } );

    test( "the reason is per FILER — one group's box is not another's", () async {
      servePage( [ _row( 'a', 'sam' ), _row( 'b', 'chloe' ) ] );
      bloc.add( const HoldingAreaRefreshRequested() );
      await settle();

      bloc.add( const HoldingAreaReasonChanged( filer: 'sam', reason: 'mine' ) );
      await settle();

      expect( bloc.state.reasonFor( 'sam' ), 'mine' );
      expect( bloc.state.reasonFor( 'chloe' ), '' );
    } );

    test( "a refresh does NOT blank a half-typed reason", () async {
      // The poll runs every 60–180 s. A refresh that cleared the box would make the
      // batch unusable on exactly the groups big enough to need it.
      servePage( [ _row( 'a', 'sam' ) ] );
      bloc.add( const HoldingAreaRefreshRequested() );
      await settle();

      bloc.add( const HoldingAreaReasonChanged( filer: 'sam', reason: 'half typed' ) );
      await settle();
      bloc.add( const HoldingAreaRefreshRequested() );
      await settle();

      expect( bloc.state.reasonFor( 'sam' ), 'half typed' );
    } );
  } );

  group( "won't-fix-all", () {
    test( "sends ONE transition per row, all with the SAME reason", () async {
      servePage( [ _row( 'a', 'sam' ), _row( 'b', 'sam' ), _row( 'c', 'chloe' ) ] );
      serveTransitions();
      bloc.add( const HoldingAreaRefreshRequested() );
      await settle();

      bloc.add( const HoldingAreaWontFixAllPressed( filer: 'sam', reason: 'superseded' ) );
      await settle();

      final sent = _transitions( adapter );
      expect( sent.length, 2, reason: 'sam filed two; chloe is a different group' );
      expect( sent.map( ( t ) => t.$1 ).toList(), [ 'a', 'b' ] );
      expect( sent.every( ( t ) => t.$2[ 'to_status' ] == 'wont_fix' ), isTrue );
      expect( sent.every( ( t ) => t.$2[ 'reason' ] == 'superseded' ), isTrue );
    } );

    test( "🔴 it does NOT touch another filer's rows", () async {
      // The blast radius is one group. A grouping key read wrong, or a filter dropped,
      // closes a peer's held work under a reason written about someone else's.
      servePage( [ _row( 'a', 'sam' ), _row( 'b', 'chloe' ) ] );
      serveTransitions();
      bloc.add( const HoldingAreaRefreshRequested() );
      await settle();

      bloc.add( const HoldingAreaWontFixAllPressed( filer: 'sam', reason: 'x' ) );
      await settle();

      expect( _transitions( adapter ).map( ( t ) => t.$1 ), isNot( contains( 'b' ) ) );
    } );

    test( "the reason is TRIMMED before it goes on the wire", () async {
      servePage( [ _row( 'a', 'sam' ) ] );
      serveTransitions();
      bloc.add( const HoldingAreaRefreshRequested() );
      await settle();

      bloc.add( const HoldingAreaWontFixAllPressed( filer: 'sam', reason: '  spaced  ' ) );
      await settle();

      expect( _transitions( adapter ).single.$2[ 'reason' ], 'spaced' );
    } );

    test( "a fully applied batch clears that group's box", () async {
      servePage( [ _row( 'a', 'sam' ) ] );
      serveTransitions();
      bloc.add( const HoldingAreaRefreshRequested() );
      await settle();

      bloc.add( const HoldingAreaReasonChanged( filer: 'sam', reason: 'done with it' ) );
      await settle();
      bloc.add( const HoldingAreaWontFixAllPressed( filer: 'sam', reason: 'done with it' ) );
      await settle();

      expect( bloc.state.reasonFor( 'sam' ), '' );
      expect( bloc.state.error, isNull );
    } );
  } );

  group( "approve-all", () {
    test( "sends approve for every row in the group", () async {
      servePage( [ _row( 'a', 'sam' ), _row( 'b', 'sam' ) ] );
      serveTransitions();
      bloc.add( const HoldingAreaRefreshRequested() );
      await settle();

      bloc.add( const HoldingAreaApproveAllPressed( 'sam' ) );
      await settle();

      final sent = _transitions( adapter );
      expect( sent.length, 2 );
      expect( sent.every( ( t ) => t.$2[ 'to_status' ] == 'queued' ), isTrue );
    } );

    test( "an unknown filer is a no-op, not a crash", () async {
      servePage( [ _row( 'a', 'sam' ) ] );
      serveTransitions();
      bloc.add( const HoldingAreaRefreshRequested() );
      await settle();

      bloc.add( const HoldingAreaApproveAllPressed( 'nobody' ) );
      await settle();

      expect( _transitions( adapter ), isEmpty );
    } );
  } );

  group( "🔴 a PARTIAL batch is reported as partial", () {
    test( "one failure does not stop the rest, and the count is honest", () async {
      // ⚠️ THE FAILURE THIS PINS: `Future.wait` would discard the outcomes of everything
      // racing alongside the first rejection, and the operator would learn that
      // "something failed" with no way to know which rows moved — in the pane whose job
      // is telling them exactly that.
      servePage( [ _row( 'a', 'sam' ), _row( 'b', 'sam' ), _row( 'c', 'sam' ) ] );
      serveTransitions();
      adapter.handlers[ 'POST /api/tasks/b/transition' ] =
          ( _ ) => jsonBody( { 'detail': 'nope' }, status: 500 );

      bloc.add( const HoldingAreaRefreshRequested() );
      await settle();
      bloc.add( const HoldingAreaApproveAllPressed( 'sam' ) );
      await settle();

      expect( _transitions( adapter ).map( ( t ) => t.$1 ).toList(), [ 'a', 'b', 'c' ],
          reason: 'the loop continues past the failure' );
      expect( bloc.state.batchNotice, contains( '1 of 3' ) );
      expect( bloc.state.batchNotice, contains( 'the rest did' ) );

      // 🔴 AND IT SURVIVES THE REFETCH THE BATCH ITSELF SCHEDULES. This assertion is the
      // whole reason the notice is not stored in `error`: a refresh clears `error`, so a
      // partial-batch report parked there vanished about eighty milliseconds after it
      // appeared — unread, in the one case where some rows moved and some did not.
      await settle();
      expect( bloc.state.batchNotice, contains( '1 of 3' ) );
    } );

    test( "a failed batch KEEPS the reason, so the retry does not retype it", () async {
      servePage( [ _row( 'a', 'sam' ) ] );
      adapter.handlers[ 'POST /api/tasks/a/transition' ] =
          ( _ ) => jsonBody( { 'detail': 'nope' }, status: 500 );

      bloc.add( const HoldingAreaRefreshRequested() );
      await settle();
      bloc.add( const HoldingAreaReasonChanged( filer: 'sam', reason: 'keep me' ) );
      await settle();
      bloc.add( const HoldingAreaWontFixAllPressed( filer: 'sam', reason: 'keep me' ) );
      await settle();

      expect( bloc.state.reasonFor( 'sam' ), 'keep me' );
    } );

    test( "🔴 a 202 does NOT read as 'failed' — it says awaiting approval", () async {
      // Telling the operator a write FAILED when the server accepted it is wrong in the
      // one direction that causes harm: the natural response to a failure is to press
      // again, and pressing again files a second approval ticket.
      servePage( [ _row( 'a', 'sam' ) ] );
      adapter.handlers[ 'POST /api/tasks/a/transition' ] = ( _ ) => jsonBody(
            { 'status': 'awaiting_human_approval', 'ticket_id': 't-1' },
            status: 202,
          );

      bloc.add( const HoldingAreaRefreshRequested() );
      await settle();
      bloc.add( const HoldingAreaApproveAllPressed( 'sam' ) );
      await settle();

      expect( bloc.state.batchNotice, contains( 'awaiting human approval' ) );
      expect( bloc.state.batchNotice, isNot( contains( 'failed' ) ) );
      expect( bloc.state.batchNotice, contains( 'second ticket' ) );
    } );
  } );

  group( "the busy flag", () {
    test( "is cleared once the batch finishes, win or lose", () async {
      servePage( [ _row( 'a', 'sam' ) ] );
      adapter.handlers[ 'POST /api/tasks/a/transition' ] =
          ( _ ) => jsonBody( { 'detail': 'nope' }, status: 500 );

      bloc.add( const HoldingAreaRefreshRequested() );
      await settle();
      bloc.add( const HoldingAreaApproveAllPressed( 'sam' ) );
      await settle();

      expect( bloc.state.busyFilers, isEmpty,
          reason: 'a stuck flag disables the control the operator needs to retry with' );
    } );
  } );

  group( "the per-row verb", () {
    test( "sends one transition and then REFETCHES rather than dropping the row", () async {
      // Removing the row locally would paint a write as applied that the server may
      // have only queued. The fetch is what proves it left.
      servePage( [ _row( 'a', 'sam' ) ] );
      serveTransitions();
      bloc.add( const HoldingAreaRefreshRequested() );
      await settle();

      final getsBefore =
          adapter.captured.where( ( o ) => o.method == 'GET' ).length;

      bloc.add( HoldingAreaRowVerbPressed( id: 'a', verb: TaskVerb.approve() ) );
      await settle();

      expect( _transitions( adapter ).single.$1, 'a' );
      expect( adapter.captured.where( ( o ) => o.method == 'GET' ).length,
          greaterThan( getsBefore ) );
    } );
  } );

  group( "against the captured fixture", () {
    test( "the live page groups into the two filers it contains", () async {
      adapter.handlers[ 'GET ${HoldingAreaRepository.path}' ] =
          ( _ ) => jsonBody( _fixture( 'holding_area.json' ) );

      bloc.add( const HoldingAreaRefreshRequested() );
      await settle();

      expect( bloc.state.groups.map( ( g ) => g.filer ).toList(),
          [ 'maya 371d6d91', 'mr radio 078b97cb' ] );
      expect( bloc.state.incomplete, isTrue, reason: 'the fixture carries has_more' );
    } );
  } );
}
