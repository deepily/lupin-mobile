import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/fleet/data/task_write_repository.dart';
import 'package:lupin_mobile/features/task_list/data/task_list_repository.dart';
import 'package:lupin_mobile/features/task_list/domain/task_list_bloc.dart';
import 'package:lupin_mobile/features/task_list/presentation/task_list_pane.dart';

/// 🔴 THE SEAM BETWEEN A TAP AND THE WIRE, WHICH NOTHING ELSE COVERS.
///
/// This file exists because of a defect that shipped green. Phase 3's acceptance said
/// "both write doors wired"; the pane had the verbs, the repository had the doors, and
/// the callback between them was a COMMENT. The suite passed at 1338 tests. The door
/// tests asserted what the repository SENDS. The widget tests asserted what the pane
/// RENDERS. Nobody asserted they were connected, so nothing could fail.
///
/// ⚠️ IT WAS THE SECOND SEAM DEFECT IN ONE EVENING FROM THE SAME BLIND SPOT — the other
/// was `_provenance()` sending `authority` without `actor`, found by Rachel building
/// against the base rather than reading it. Both were a correct component, a correct
/// caller, and an unasserted join.
///
/// ⇒ These tests drive a REAL TAP through the REAL WIDGET TREE and assert the REQUEST
/// THAT ACTUALLY WENT OUT. A mock returning what it was told to return proves nothing
/// about the wire; that is Rachel's principle and the recorder below is her shape.

/// Records what actually went on the wire and answers per request.
///
/// ⚠️ EXTENDED FROM RACHEL'S `_Recorder` in ONE WAY, DELIBERATELY: hers answers every
/// request with one canned status/body, which is right for a repository test firing one
/// call. A mounted pane polls on init AND then writes, so this one answers as a function
/// of the request. Nothing else about her shape changed — it is still an `Interceptor`
/// that records and resolves, so the assertions stay on `RequestOptions`.
class _Recorder extends Interceptor {
  final List<RequestOptions> calls = [];
  final Response<dynamic> Function( RequestOptions ) respond;

  _Recorder( this.respond );

  @override
  void onRequest( RequestOptions options, RequestInterceptorHandler handler ) {
    calls.add( options );
    handler.resolve( respond( options ) );
  }

  Iterable<RequestOptions> get writes =>
      calls.where( ( c ) => c.method != 'GET' );
}

Response<dynamic> _json( RequestOptions o, dynamic body, { int status = 200 } ) =>
    Response<dynamic>( requestOptions: o, statusCode: status, data: body );

/// One `not_approved` row — the shape the Approve control exists for.
const _page = {
  'tasks': [
    {
      'id'            : 'a/b?c#d',
      'title'         : 'a row awaiting approval',
      'status'        : 'not_approved',
      'priority'      : 'P1',
      'owner_persona' : 'sam',
    },
  ],
  'total': 1, 'has_more': false, 'truncated': false, 'warnings': <String>[],
};

Future<_Recorder> _mount(
  WidgetTester tester, {
  Response<dynamic> Function( RequestOptions )? onWrite,
} ) async {
  late final _Recorder rec;
  rec = _Recorder( ( o ) {
    if ( o.method == 'GET' ) return _json( o, _page );
    return onWrite?.call( o ) ?? _json( o, const { 'status': 'ok' } );
  } );

  final dio = Dio( BaseOptions( baseUrl: 'http://test' ) )..interceptors.add( rec );

  await tester.pumpWidget( MaterialApp(
    home : Scaffold(
      body : BlocProvider<TaskListBloc>(
        create : ( _ ) => TaskListBloc(
          TaskListRepository( dio ),
          TaskWriteRepository( dio, actorEmail: () => 'rick@example.com' ),
        ),
        child : const TaskListPane(),
      ),
    ),
  ) );
  await tester.pumpAndSettle();
  return rec;
}

void main() {
  group( 'tap → wire: the Approve control', () {
    // The highest-value control in this pane. §4.2's named failure is a builder
    // implementing approve as PATCH {status:"queued"} — the field door silently ignores
    // an unknown key, so the pane looks wired and changes nothing.
    testWidgets( 'a tap on Approve puts a real POST on the wire', ( tester ) async {
      final rec = await _mount( tester );

      await tester.tap( find.byKey( const Key( TestKeys.taskRowDisclosure ) ) );
      await tester.pumpAndSettle();
      await tester.tap( find.byKey( const Key( '${TestKeys.taskRowVerbPrefix}approve' ) ) );
      await tester.pumpAndSettle();

      expect( rec.writes, isNotEmpty,
          reason: 'a tap that produces NO request is exactly the defect this file '
                  'exists for — the pane rendered, the verb was there, and nothing '
                  'reached the server' );

      final sent = rec.writes.first;
      expect( sent.method, 'POST' );
      expect( sent.path, endsWith( '/transition' ) );
      expect( sent.path, isNot( contains( 'a/b?c#d' ) ),
          reason: 'the id must be URL-encoded all the way from the tap' );
      expect( sent.path, contains( 'a%2Fb%3Fc%23d' ) );

      final body = sent.data as Map;
      expect( body[ 'to_status' ], 'queued' );
      expect( body[ 'authority' ], 'user_direct' );
      expect( body[ 'actor' ], 'rick@example.com (mobile)',
          reason: 'the provenance pair must survive the whole path, not just the '
                  'repository test that asserts it in isolation' );
    } );

    // ⚠️ THIS ONE IS A NEGATIVE AND NEGATIVES PASS WHEN NOTHING HAPPENS. Measured: with
    // the wiring deliberately reverted, this test STILL PASSED while the two around it
    // went red — a no-op sends no PATCH either. It is worth keeping (it catches the
    // wrong-door mistake §4.2 names) but it is not load-bearing on its own, and it must
    // never be the only assertion guarding this control.
    testWidgets( 'no PATCH is sent for a status change', ( tester ) async {
      final rec = await _mount( tester );

      await tester.tap( find.byKey( const Key( TestKeys.taskRowDisclosure ) ) );
      await tester.pumpAndSettle();
      await tester.tap( find.byKey( const Key( '${TestKeys.taskRowVerbPrefix}approve' ) ) );
      await tester.pumpAndSettle();

      expect( rec.calls.where( ( c ) => c.method == 'PATCH' ), isEmpty,
          reason: 'approve is a STATUS change; a PATCH would be silently ignored by the '
                  'field door and the row would never move' );
    } );

    // 🔴 THE 202, DRIVEN FROM A TAP. The repository test proves the exception is thrown;
    // this proves the OPERATOR sees the row come back rather than watching it vanish
    // into an approval that never happened.
    testWidgets( 'a 202 leaves the row on screen and says awaiting', ( tester ) async {
      final rec = await _mount( tester, onWrite: ( o ) => _json(
        o, const { 'status': 'awaiting_human_approval', 'ticket_id': 'tk-9' },
        status: 202,
      ) );

      await tester.tap( find.byKey( const Key( TestKeys.taskRowDisclosure ) ) );
      await tester.pumpAndSettle();
      await tester.tap( find.byKey( const Key( '${TestKeys.taskRowVerbPrefix}approve' ) ) );
      await tester.pumpAndSettle();

      expect( rec.writes, hasLength( 1 ) );
      expect( find.textContaining( 'a row awaiting approval' ), findsOneWidget,
          reason: 'a 202 is not an approval — the row must NOT disappear, because a row '
                  'that vanishes reads to the operator as approved' );
    } );
  } );

  group( 'tap → wire: the poll', () {
    testWidgets( 'mounting the pane issues exactly one GET, not one per rebuild',
        ( tester ) async {
      final rec = await _mount( tester );
      await tester.pump( const Duration( milliseconds: 100 ) );

      expect( rec.calls.where( ( c ) => c.method == 'GET' ), hasLength( 1 ) );
    } );
  } );
}
