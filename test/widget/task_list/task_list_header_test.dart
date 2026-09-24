import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/fleet/data/task_write_repository.dart';
import 'package:lupin_mobile/features/task_list/data/task_list_repository.dart';
import 'package:lupin_mobile/features/task_list/data/task_lookup.dart';
import 'package:lupin_mobile/features/task_list/domain/task_list_bloc.dart';
import 'package:lupin_mobile/features/task_list/presentation/task_list_pane.dart';

/// M1, M3 and M4 driven through the REAL pane, asserting what reaches the wire.
class _Recorder extends Interceptor {
  final List<RequestOptions> calls = [];
  final Response<dynamic> Function( RequestOptions ) respond;

  _Recorder( this.respond );

  @override
  void onRequest( RequestOptions options, RequestInterceptorHandler handler ) {
    calls.add( options );
    final res = respond( options );
    if ( ( res.statusCode ?? 200 ) >= 400 ) {
      handler.reject( DioException( requestOptions: options, response: res ) );
    } else {
      handler.resolve( res );
    }
  }

  Iterable<RequestOptions> get lookups =>
      calls.where( ( c ) => c.path.startsWith( '/api/tasks/' ) );
}

Response<dynamic> _json( RequestOptions o, dynamic body, { int status = 200 } ) =>
    Response<dynamic>( requestOptions: o, statusCode: status, data: body );

Map<String, dynamic> _page( List<Map<String, dynamic>> tasks ) => {
  'tasks': tasks, 'total': tasks.length, 'has_more': false, 'truncated': false,
  'warnings': <String>[],
};

const _heldRow = {
  'id'     : '323d0f9c-71ce-4d51-bf69-524a7f95a733',
  'title'  : 'a row sitting in the holding area',
  'status' : 'not_approved',
};

Future<_Recorder> _mount(
  WidgetTester tester, {
  List<Map<String, dynamic>> board = const [],
  Response<dynamic> Function( RequestOptions )? onLookup,
} ) async {
  final rec = _Recorder( ( o ) {
    if ( o.path.startsWith( '/api/tasks/' ) ) {
      return onLookup?.call( o ) ?? _json( o, _heldRow );
    }
    return _json( o, _page( board ) );
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

String _text( WidgetTester tester, String key ) =>
    tester.widget<Text>( find.byKey( Key( key ) ) ).data!;

void main() {
  group( 'M1 — the count headline', () {
    testWidgets( 'a board with no parked rows reads "Live: N"', ( tester ) async {
      await _mount( tester, board: [
        { 'id': 'a', 'title': 'one', 'status': 'queued',      'owner_persona': 'sam' },
        { 'id': 'b', 'title': 'two', 'status': 'in_progress', 'owner_persona': 'sam' },
      ] );
      expect( _text( tester, TestKeys.taskListCountHeadline ), 'Live: 2' );
    } );

    testWidgets( 'a park-active row splits it', ( tester ) async {
      final chase = DateTime.now().toUtc().add( const Duration( days: 2 ) ).toIso8601String();
      await _mount( tester, board: [
        { 'id': 'a', 'title': 'one', 'status': 'queued', 'owner_persona': 'sam' },
        { 'id': 'b', 'title': 'two', 'status': 'parked', 'owner_persona': 'sam',
          'next_chase_ts': chase },
      ] );
      expect( _text( tester, TestKeys.taskListCountHeadline ),
          'Live: 1 · Parked: 1 · Total: 2' );
    } );
  } );

  group( 'M4 — the new-task stub', () {
    testWidgets( 'is on screen and disabled', ( tester ) async {
      await _mount( tester );
      final finder = find.byKey( const Key( TestKeys.taskListNewTaskStub ) );
      expect( finder, findsOneWidget );
      expect( tester.widget<ButtonStyleButton>( finder ).onPressed, isNull );
    } );
  } );

  group( 'M3 — the lookup box', () {
    testWidgets( 'works on an EMPTY board — the rows looked up are usually not on it',
        ( tester ) async {
      final rec = await _mount( tester );
      expect( find.byKey( const Key( TestKeys.taskListEmptyState ) ), findsOneWidget );

      await tester.enterText( find.byKey( const Key( TestKeys.taskLookupInput ) ), '323D0F9C' );
      await tester.tap( find.byKey( const Key( TestKeys.taskLookupGo ) ) );
      await tester.pumpAndSettle();

      expect( rec.lookups.single.path, '/api/tasks/323d0f9c' );
      expect( find.byKey( const Key( TestKeys.taskLookupResultCard ) ), findsOneWidget );
      expect( find.text( 'a row sitting in the holding area' ), findsOneWidget );
    } );

    testWidgets( '🔴 the result states the status — held reads as held, not queued',
        ( tester ) async {
      await _mount( tester );
      await tester.enterText( find.byKey( const Key( TestKeys.taskLookupInput ) ), '323d0f9c' );
      await tester.testTextInput.receiveAction( TextInputAction.search );
      await tester.pumpAndSettle();

      expect( _text( tester, TestKeys.taskLookupResultStatus ), contains( 'holding area' ) );
    } );

    testWidgets( 'junk is refused WITHOUT a request', ( tester ) async {
      final rec = await _mount( tester );
      await tester.enterText( find.byKey( const Key( TestKeys.taskLookupInput ) ), 'abc' );
      await tester.tap( find.byKey( const Key( TestKeys.taskLookupGo ) ) );
      await tester.pumpAndSettle();

      expect( rec.lookups, isEmpty );
      expect( _text( tester, TestKeys.taskLookupMessage ), taskRefRefusalMessage );
    } );

    testWidgets( 'a 404 says no ticket matches, and shows no card', ( tester ) async {
      await _mount( tester, onLookup: ( o ) => _json( o, { 'detail': 'nope' }, status: 404 ) );
      await tester.enterText( find.byKey( const Key( TestKeys.taskLookupInput ) ), 'dead' );
      await tester.tap( find.byKey( const Key( TestKeys.taskLookupGo ) ) );
      await tester.pumpAndSettle();

      expect( _text( tester, TestKeys.taskLookupMessage ), 'No ticket matches "dead".' );
      expect( find.byKey( const Key( TestKeys.taskLookupResultCard ) ), findsNothing );
    } );

    testWidgets( 'clear removes the card and empties the box', ( tester ) async {
      await _mount( tester );
      await tester.enterText( find.byKey( const Key( TestKeys.taskLookupInput ) ), '323d0f9c' );
      await tester.tap( find.byKey( const Key( TestKeys.taskLookupGo ) ) );
      await tester.pumpAndSettle();
      await tester.tap( find.byKey( const Key( TestKeys.taskLookupClear ) ) );
      await tester.pumpAndSettle();

      expect( find.byKey( const Key( TestKeys.taskLookupResultCard ) ), findsNothing );
      expect( tester.widget<TextField>( find.byKey( const Key( TestKeys.taskLookupInput ) ) )
          .controller!.text, isEmpty );
    } );
  } );
}
