import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/fleet/data/task_write_repository.dart';
import 'package:lupin_mobile/features/task_list/data/task_list_repository.dart';
import 'package:lupin_mobile/features/task_list/domain/task_list_bloc.dart';
import 'package:lupin_mobile/features/task_list/presentation/task_list_pane.dart';

/// 🔴 ROWS SIT UNDER THEIR PERSONA, NOT FLUSH AGAINST THE SCREEN EDGE.
///
/// Rick, on the emulator 2026-09-23: the rows were *"crushed up against the left hand side
/// of the rendering area … they should be indented to reflect containment by each
/// persona."* The pane handed `TaskRow` to the list with no padding at all, while the
/// group header had a 16 dp gutter — so every row started LEFT of its own header.
///
/// ⇒ Asserted as GEOMETRY, measured at 360×800 (ordinary Android portrait), because an
/// indent is a relationship between two widgets and only positions can show it:
///   - the row's title starts exactly where the persona name starts
///   - the row keeps a right gutter, so the indent did not just push it off-screen
///   - nothing overflows at 360 dp — the indent comes out of the title's width
///
/// Mutation-proved: with the row padding removed, the first two tests go RED.

class _Recorder extends Interceptor {
  @override
  void onRequest( RequestOptions options, RequestInterceptorHandler handler ) {
    handler.resolve( Response<dynamic>(
      requestOptions : options,
      statusCode     : 200,
      data           : options.method == 'GET' ? _page : const { 'status': 'ok' },
    ) );
  }
}

const _page = {
  'tasks': [
    {
      'id'            : 'row-1',
      'title'         : '[LUPIN-MOBILE] Phase 3: a title long enough to need truncating at 360 dp',
      'status'        : 'queued',
      'priority'      : 'P1',
      'owner_persona' : 'sam',
    },
  ],
  'total': 1, 'has_more': false, 'truncated': false, 'warnings': <String>[],
};

Future<void> _mount( WidgetTester tester ) async {
  tester.view.physicalSize     = const Size( 360, 800 );
  tester.view.devicePixelRatio = 1.0;
  addTearDown( tester.view.resetPhysicalSize );
  addTearDown( tester.view.resetDevicePixelRatio );

  final dio = Dio( BaseOptions( baseUrl: 'http://test' ) )..interceptors.add( _Recorder() );

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
}

Finder get _personaName => find.descendant(
  of       : find.byKey( const Key( '${TestKeys.taskListGroupHeaderPrefix}sam' ) ),
  matching : find.text( 'sam' ),
);

Finder get _rowTitle => find.byKey( const Key( '${TestKeys.taskRowCellPrefix}title' ) );

void main() {
  testWidgets( '🔴 the row title starts where the persona name starts', ( tester ) async {
    await _mount( tester );

    expect( _personaName, findsOneWidget, reason: 'precondition — the group header rendered' );
    expect( _rowTitle, findsOneWidget, reason: 'precondition — the group is expanded' );

    expect(
      tester.getTopLeft( _rowTitle ).dx,
      tester.getTopLeft( _personaName ).dx,
      reason: 'a row is contained by its persona, so it lines up under the name — '
              'flush left (0 dp) is the defect Rick walked into',
    );
    expect( tester.getTopLeft( _rowTitle ).dx, greaterThan( 16 ),
        reason: 'deeper than the header gutter, or the containment does not read' );
  } );

  testWidgets( 'the row keeps a right gutter at 360 dp', ( tester ) async {
    await _mount( tester );

    final row = find.byKey( const Key( '${TestKeys.taskListRowIndentPrefix}row-1' ) );
    expect( row, findsOneWidget );
    expect( tester.getTopRight( find.byKey( const Key( TestKeys.taskListView ) ) ).dx -
                tester.getTopRight( find.descendant( of: row, matching: find.byType( Column ) ).first ).dx,
            16,
            reason: 'matching right inset, or the indent just reads as lopsided' );
  } );

  testWidgets( 'nothing overflows at 360 dp — the indent comes out of the title', ( tester ) async {
    await _mount( tester );

    expect( tester.takeException(), isNull,
        reason: 'a RenderFlex overflow at 360 dp is exactly the trap B3 was scoped around' );
    expect( tester.getSize( _rowTitle ).width, greaterThan( 150 ),
        reason: 'the title must stay readable, not squeezed to a few characters' );
  } );
}
