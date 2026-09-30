import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/fleet/data/task_write_repository.dart';
import 'package:lupin_mobile/features/holding_area/data/holding_area_repository.dart';
import 'package:lupin_mobile/features/holding_area/domain/holding_area_bloc.dart';
import 'package:lupin_mobile/services/network/network_connectivity_service.dart';

import '../_helpers/stub_dio.dart';

/// G6 on the Holding Area — and the half a group-level notice cannot do.
///
/// 🔴 APPROVE-ALL WRITES N ROWS IN ONE PRESS AND THEY FAIL INDEPENDENTLY. The pane
/// already reports *"one of fourteen did not move — the rest did"*, which is the right
/// sentence and still leaves the operator scanning fourteen rows to find the one. Keying
/// the marks by task id means the row that did not land is the row wearing the mark.
///
/// ─────────────────────────────────────────────────────────────────────────────────
/// 🔴 MUTATION MATRIX — MEASURED, NOT ASSERTED.
///
/// | Test                                     | A | B | C |
/// |------------------------------------------|---|---|---|
/// | a lost per-row verb is marked             |🔴 | . | . |
/// | a partial batch marks ONLY the lost rows  |🔴 |🔴 | . |
/// | a row that lands clears its older mark    | . |🔴 | . |
/// | restored → retried → cleared              |🔴 | . |🔴 |
/// | a refused write is not marked             | . | . | . |
///
///   A — the failure handlers stop recording (the shipped G6 state)
///   B — the batch marks the WHOLE group on any failure, not the rows that failed
///   C — the restored edge only refetches, as it did before this row
///
/// ⚠️ "a refused write is not marked" has no red column here; it is covered by column B
/// of `unsent_write_test.dart`, where `isTransportFailure` is the thing under test. Said
/// plainly so a reader can tell "guarded elsewhere" from "guards nothing".

class _FakeNetwork implements NetworkConnectivityService {
  final StreamController<NetworkState> controller =
      StreamController<NetworkState>.broadcast();

  @override
  Stream<NetworkState> get networkStateStream => controller.stream;

  @override
  bool get isMobile => false;

  void restore() => controller.add( NetworkState.connected );

  @override
  dynamic noSuchMethod( Invocation invocation ) => super.noSuchMethod( invocation );
}

Map<String, dynamic> _row( String id, String filer ) => <String, dynamic>{
      'id'          : id,
      'title'       : 'held row $id',
      'status'      : 'not_approved',
      'created_by'  : filer,
      'priority'    : 'P2',
    };

Map<String, dynamic> _page( List<Map<String, dynamic>> rows ) => <String, dynamic>{
      'tasks'     : rows,
      'total'     : rows.length,
      'has_more'  : false,
      'truncated' : false,
      'warnings'  : <String>[],
    };

ResponseBody _neverAnswered( RequestOptions o ) => throw DioException.connectionError(
      requestOptions : o,
      reason         : 'the signal went away',
    );

void main() {
  late StubAdapter adapter;
  late _FakeNetwork network;
  late HoldingAreaBloc bloc;

  String transitionKey( String id ) => 'POST /api/tasks/$id/transition';

  setUp( () {
    adapter = StubAdapter();
    network = _FakeNetwork();
    final dio = makeDio( adapter );
    adapter.handlers[ 'GET ${HoldingAreaRepository.path}' ] = ( _ ) => jsonBody( _page( [
          _row( 'a', 'sam' ),
          _row( 'b', 'sam' ),
        ] ) );
    bloc = HoldingAreaBloc(
      HoldingAreaRepository( dio ),
      TaskWriteRepository( dio, actorEmail: () => 'rick@example.com' ),
      network : network,
    )..startConnectivityRefresh();
  } );

  tearDown( () async {
    await bloc.close();
    await network.controller.close();
  } );

  Future<void> settle() => Future<void>.delayed( const Duration( milliseconds: 80 ) );

  Future<void> load() async {
    bloc.add( const HoldingAreaRefreshRequested() );
    await settle();
  }

  int writesTo( String key ) =>
      adapter.captured.where( ( c ) => '${c.method} ${c.path}' == key ).length;

  test( 'a per-row verb nobody answered is marked unsent', () async {
    await load();
    adapter.handlers[ transitionKey( 'a' ) ] = _neverAnswered;

    bloc.add( HoldingAreaRowVerbPressed( id: 'a', verb: TaskVerb.approve() ) );
    await settle();

    expect( bloc.state.unsentLabelFor( 'a' ), 'Approve' );
    expect( bloc.state.batchNotice, isNotNull, reason: 'and they are still told' );
  } );

  // 🔴 THE ROWS THAT DID NOT LAND ARE THE ROWS THAT WEAR A MARK, and no others. Marking
  // the whole group on any failure would tell the operator that thirteen rows which DID
  // move are still pending — the opposite of the fact the pane exists to show.
  test( 'a partial batch marks ONLY the rows that did not land', () async {
    await load();
    adapter.handlers[ transitionKey( 'a' ) ] = ( _ ) => jsonBody( { 'status' : 'ok' } );
    adapter.handlers[ transitionKey( 'b' ) ] = _neverAnswered;

    // ⚠️ 'Sam', NOT 'sam'. The group KEY is the display-cased persona label
    // (`personaDisplayLabel`), which is what Chloé's R1 grouping produces and what the
    // pane passes back. A batch dispatched against the raw `created_by` string finds no
    // group, returns early, and every assertion below then fails for the wrong reason.
    bloc.add( const HoldingAreaApproveAllPressed( 'Sam' ) );
    await settle();

    expect( bloc.state.unsent.keys, [ 'b' ],
        reason: 'row a moved; saying otherwise is a false fact about the board' );
    expect( bloc.state.batchNotice, contains( 'did not move' ) );
  } );

  test( 'a row that lands clears the mark it was already wearing', () async {
    await load();
    adapter.handlers[ transitionKey( 'a' ) ] = _neverAnswered;
    bloc.add( HoldingAreaRowVerbPressed( id: 'a', verb: TaskVerb.approve() ) );
    await settle();
    expect( bloc.state.unsent.keys, [ 'a' ] );

    adapter.handlers[ transitionKey( 'a' ) ] = ( _ ) => jsonBody( { 'status' : 'ok' } );
    bloc.add( HoldingAreaRowVerbPressed( id: 'a', verb: TaskVerb.approve() ) );
    await settle();

    expect( bloc.state.unsent, isEmpty,
        reason: 'a stale mark on a row that HAS moved is the same lie in reverse' );
  } );

  group( 'the connectivity trigger — driven, not called', () {
    test( 'restored → retried → the mark clears', () async {
      await load();
      adapter.handlers[ transitionKey( 'a' ) ] = _neverAnswered;
      bloc.add( HoldingAreaRowVerbPressed( id: 'a', verb: TaskVerb.approve() ) );
      await settle();
      final afterPress = writesTo( transitionKey( 'a' ) );

      adapter.handlers[ transitionKey( 'a' ) ] = ( _ ) => jsonBody( { 'status' : 'ok' } );
      network.restore();
      await settle();

      expect( writesTo( transitionKey( 'a' ) ) - afterPress, 1,
          reason: 'one attempt per write per edge' );
      expect( bloc.state.unsent, isEmpty );
    } );

    test( 'ONE restore produces exactly ONE attempt', () async {
      await load();
      adapter.handlers[ transitionKey( 'a' ) ] = _neverAnswered;
      bloc.add( HoldingAreaRowVerbPressed( id: 'a', verb: TaskVerb.approve() ) );
      await settle();
      final afterPress = writesTo( transitionKey( 'a' ) );

      network.restore();
      await settle();

      expect( writesTo( transitionKey( 'a' ) ) - afterPress, 1,
          reason: 'a loop inside one edge hammers a connection that just came back' );
      expect( bloc.state.unsent.keys, [ 'a' ], reason: 'still unsent, still visible' );
    } );

    test( 'TWO restores produce TWO attempts', () async {
      await load();
      adapter.handlers[ transitionKey( 'a' ) ] = _neverAnswered;
      bloc.add( HoldingAreaRowVerbPressed( id: 'a', verb: TaskVerb.approve() ) );
      await settle();
      final afterPress = writesTo( transitionKey( 'a' ) );

      network.restore();
      await settle();
      network.restore();
      await settle();

      expect( writesTo( transitionKey( 'a' ) ) - afterPress, 2 );
    } );
  } );
}
