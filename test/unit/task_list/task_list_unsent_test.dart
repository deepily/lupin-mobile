import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/fleet/data/task_verbs.dart';
import 'package:lupin_mobile/features/fleet/data/task_write_repository.dart';
import 'package:lupin_mobile/features/task_list/data/task_list_repository.dart';
import 'package:lupin_mobile/features/task_list/domain/task_list_bloc.dart';
import 'package:lupin_mobile/services/network/network_connectivity_service.dart';

import '../_helpers/stub_dio.dart';

/// G6 end to end on the Task List, INCLUDING THE CONNECTIVITY TRIGGER ITSELF.
///
/// 🔴 THE THIRD TEST THE ROW ASKED FOR IS THE ONE THAT IS EASY TO SKIP. "Fail → marked"
/// and "restored → retried → cleared" can both be written by calling the retry handler
/// directly, and both would pass while nothing on earth ever fires it — which is the
/// shape of every gap in this analysis: built, tested, unreachable. So these drive the
/// real `NetworkConnectivityService` stream through `startConnectivityRefresh`, and the
/// assertion is on the request that actually went out.
///
/// ─────────────────────────────────────────────────────────────────────────────────
/// 🔴 MUTATION MATRIX — MEASURED, NOT ASSERTED. Red counts are what came back.
///
/// | Test                                      | A | B | C | D | E |
/// |-------------------------------------------|---|---|---|---|---|
/// | a lost write is marked unsent              |🔴 | . | . | . | . |
/// | the mark names the verb, on the right row  |🔴 | . | . | . | . |
/// | a refused write is NOT marked              | . |🔴 | . | . | . |
/// | a 202 is never marked unsent               | . |🔴 | . | . | . |
/// | a field edit is remembered too             |🔴 | . | . | . | . |
/// | restored → retried → cleared               |🔴 | . |🔴 | . | . |
/// | a failed retry keeps the mark              |🔴 | . | . | . | . |
/// | TWO restores produce TWO attempts          |🔴 | . |🔴 | . |🔴 |
/// | ONE restore produces exactly ONE attempt   |🔴 | . |🔴 | . |🔴 |
/// | the retry uses the door it came from       |🔴 | . |🔴 |🔴 | . |
/// | a refusal on retry clears and reports      | . |🔴 |🔴 | . | . |
///
///   A — the failure handlers stop recording (rollback only: the shipped G6 state)
///   B — `isTransportFailure` forced true, so refusals and 202s get marked too
///   C — the restored edge only refetches, as it did before this row
///   D — the retry sends every write through the transition door
///   E — the restored edge retries in a loop until the set empties
///
/// Measured red counts across all four G6 test files: A 15 · B 7 · C 8 · D 1 · E 6.
///
/// ⚠️ D REDDENS EXACTLY ONE TEST, AND THAT IS THE POINT OF KEEPING IT. Sending a field
/// edit through the transition door is §4.2's named failure applied to a retry, and it is
/// SILENT — the field door ignores an unknown key without complaint. One narrow detector
/// on a defect nothing else can see is worth more than a broad one on a defect three
/// tests already catch.

/// Drives the connectivity edge the bloc actually listens to.
class _FakeNetwork implements NetworkConnectivityService {
  final StreamController<NetworkState> controller =
      StreamController<NetworkState>.broadcast();

  bool mobile = false;

  @override
  Stream<NetworkState> get networkStateStream => controller.stream;

  @override
  bool get isMobile => mobile;

  /// The restored edge. Anything else must not act.
  void restore() => controller.add( NetworkState.connected );
  void drop()    => controller.add( NetworkState.disconnected );

  @override
  dynamic noSuchMethod( Invocation invocation ) => super.noSuchMethod( invocation );
}

const _page = {
  'tasks' : [
    {
      'id'            : 'row-1',
      'title'         : 'a row on the board',
      'status'        : 'queued',
      'priority'      : 'P2',
      'owner_persona' : 'sam',
    },
  ],
  'total' : 1, 'has_more' : false, 'truncated' : false, 'warnings' : <String>[],
};

/// A write that died with nobody answering — the case a restored connection fixes.
ResponseBody _neverAnswered( RequestOptions o ) =>
    throw DioException.connectionError(
      requestOptions : o,
      reason         : 'the signal went away',
    );

void main() {
  late StubAdapter adapter;
  late _FakeNetwork network;
  late TaskListBloc bloc;

  const transitionKey = 'POST /api/tasks/row-1/transition';
  const patchKey      = 'PATCH /api/tasks/row-1';

  setUp( () {
    adapter = StubAdapter();
    network = _FakeNetwork();
    final dio = makeDio( adapter );
    adapter.handlers[ 'GET ${TaskListRepository.path}' ] = ( _ ) => jsonBody( _page );
    bloc = TaskListBloc(
      TaskListRepository( dio ),
      TaskWriteRepository( dio, actorEmail: () => 'rick@example.com' ),
      network : network,
    )..startConnectivityRefresh();
  } );

  tearDown( () async {
    await bloc.close();
    await network.controller.close();
  } );

  Future<void> settle() => Future<void>.delayed( const Duration( milliseconds: 60 ) );

  int writesTo( String key ) => adapter.captured
      .where( ( c ) => '${c.method} ${c.path}' == key )
      .length;

  Future<void> pressPark() async {
    bloc.add( TaskListVerbPressed(
      taskId : 'row-1',
      verb   : buildTaskVerb( 'park',
          reason: 'not this quarter', chaseTs: DateTime.utc( 2026, 10, 1 ) ),
    ) );
    await settle();
  }

  group( 'a lost write is kept, not forgotten', () {
    // 🔴 G6 IN ONE ASSERTION. Before this row the failure handler rolled the row back and
    // set an error, and what the operator DID was gone.
    test( 'a write that nobody answered is marked unsent', () async {
      adapter.handlers[ transitionKey ] = _neverAnswered;
      await pressPark();

      expect( bloc.state.unsent.keys, [ 'row-1' ],
          reason: 'rolling back is right; FORGETTING is the defect' );
      expect( bloc.state.error, isNotNull, reason: 'and they are still told' );
    } );

    // ⚠️ THE MARK NAMES THE VERB, NOT THE FAILURE. "Park not sent" tells the operator
    // what to press again; "write failed" leaves them to work it out.
    test( 'the mark names the verb and sits on the row it belongs to', () async {
      adapter.handlers[ transitionKey ] = _neverAnswered;
      await pressPark();

      expect( bloc.state.unsentLabelFor( 'row-1' ), 'Park' );
      expect( bloc.state.unsentLabelFor( 'some-other-row' ), isNull );
    } );

    // 🔴 TIFFANY'S RULING: a 4xx is a refusal, rolled back with the server's words, and
    // never marked. A mark for it could never clear however good the signal got.
    test( 'a write the server REFUSED is not marked unsent', () async {
      adapter.handlers[ transitionKey ] =
          ( _ ) => jsonBody( { 'detail' : 'illegal transition' }, status: 409 );
      await pressPark();

      expect( bloc.state.unsent, isEmpty,
          reason: 'retrying a 409 just fails again, forever and invisibly' );
      expect( bloc.state.error, isNotNull, reason: "the server's words still reach them" );
    } );

    // 🔴 A 202 IS NOT A FAILURE AND NOT A SUCCESS. Retrying it files a SECOND ticket.
    test( 'a 202 is never marked unsent', () async {
      adapter.handlers[ transitionKey ] = ( _ ) => jsonBody(
        { 'status' : 'awaiting_human_approval', 'ticket_id' : 'tk-3' },
        status: 202,
      );
      await pressPark();

      expect( bloc.state.unsent, isEmpty );
      expect( bloc.state.error, contains( 'awaiting approval' ) );
    } );

    test( 'a field edit is remembered too, not only a verb', () async {
      adapter.handlers[ patchKey ] = _neverAnswered;
      bloc.add( const TaskListFieldChanged( taskId: 'row-1', priority: 'P0' ) );
      await settle();

      expect( bloc.state.unsentLabelFor( 'row-1' ), 'Priority' );
    } );
  } );

  group( 'the connectivity trigger — driven, not called', () {
    // 🔴 THE TEST THE ROW NAMED. Everything else here could pass while nothing ever
    // fired the edge.
    test( 'restored → retried → the mark clears', () async {
      adapter.handlers[ transitionKey ] = _neverAnswered;
      await pressPark();
      expect( bloc.state.unsent, isNotEmpty );

      // The connection comes back and the write now lands.
      adapter.handlers[ transitionKey ] = ( _ ) => jsonBody( { 'status' : 'ok' } );
      network.restore();
      await settle();

      expect( bloc.state.unsent, isEmpty, reason: 'it landed; the mark is spent' );
      expect( writesTo( transitionKey ), 2,
          reason: 'the original press plus exactly one retry' );
    } );

    test( 'a failed retry keeps the mark', () async {
      adapter.handlers[ transitionKey ] = _neverAnswered;
      await pressPark();

      network.restore();
      await settle();

      expect( bloc.state.unsent.keys, [ 'row-1' ],
          reason: 'still unsent, still visible, and still the operator\'s act' );
    } );

    // 🔴 TIFFANY ASKED FOR THIS PAIR BY NAME. Two restores are two edges and therefore
    // two attempts: "once ever" would lose an action permanently over one bad moment.
    test( 'TWO restores produce TWO attempts', () async {
      adapter.handlers[ transitionKey ] = _neverAnswered;
      await pressPark();
      final afterPress = writesTo( transitionKey );

      network.restore();
      await settle();
      network.restore();
      await settle();

      expect( writesTo( transitionKey ) - afterPress, 2,
          reason: 'each restored edge is a genuine new signal' );
    } );

    // 🔴 AND THE OTHER HALF: one edge is ONE attempt, never a loop until the set empties.
    // A loop is invisible to a test that calls the handler directly — it shows up only
    // when something fires the edge and the test counts what left.
    test( 'ONE restore produces exactly ONE attempt', () async {
      adapter.handlers[ transitionKey ] = _neverAnswered;
      await pressPark();
      final afterPress = writesTo( transitionKey );

      network.restore();
      await settle();

      expect( writesTo( transitionKey ) - afterPress, 1,
          reason: 'a loop inside one edge hammers a connection that just came back' );
    } );

    // ⚠️ ONLY THE RESTORED EDGE ACTS. Firing on every state change would also fire on the
    // way DOWN — a request into a connection that just failed.
    test( 'losing the connection retries nothing', () async {
      adapter.handlers[ transitionKey ] = _neverAnswered;
      await pressPark();
      final afterPress = writesTo( transitionKey );

      network.drop();
      await settle();

      expect( writesTo( transitionKey ), afterPress );
    } );

    test( 'a restore with nothing unsent writes nothing', () async {
      network.restore();
      await settle();

      expect( writesTo( transitionKey ), 0 );
      expect( writesTo( patchKey ), 0 );
    } );

    // 🔴 THE RETRY GOES BACK THROUGH THE DOOR IT CAME FROM. §4.2's named failure applies
    // to a retry exactly as to a fresh write: a PATCH carrying a status is ignored
    // without complaint, and a transition carrying a priority is not a request the
    // endpoint understands.
    test( 'a field edit retries through the FIELD door, not the transition door',
        () async {
      adapter.handlers[ patchKey ] = _neverAnswered;
      bloc.add( const TaskListFieldChanged( taskId: 'row-1', priority: 'P0' ) );
      await settle();
      final postsBefore = writesTo( transitionKey );

      adapter.handlers[ patchKey ] = ( _ ) => jsonBody( { 'status' : 'ok' } );
      network.restore();
      await settle();

      expect( writesTo( patchKey ), 2, reason: 'the press plus the retry' );
      expect( writesTo( transitionKey ), postsBefore,
          reason: 'a retry through the wrong door is silently ignored by the field door' );
      expect( bloc.state.unsent, isEmpty );
    } );

    // A refusal met on RETRY drops the record and surfaces the server's words: the
    // connection is fine, so the mark would never clear.
    test( 'a refusal on retry clears the mark and reports it', () async {
      adapter.handlers[ transitionKey ] = _neverAnswered;
      await pressPark();

      adapter.handlers[ transitionKey ] =
          ( _ ) => jsonBody( { 'detail' : 'illegal transition' }, status: 409 );
      network.restore();
      await settle();

      expect( bloc.state.unsent, isEmpty,
          reason: 'a mark no signal can clear is a mark that lies' );
      expect( bloc.state.error, isNotNull );
    } );
  } );
}
