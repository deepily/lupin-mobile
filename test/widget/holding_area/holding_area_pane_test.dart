import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/fleet/data/task_write_repository.dart';
import 'package:lupin_mobile/features/fleet/presentation/task_row.dart';
import 'package:lupin_mobile/features/holding_area/data/holding_area_repository.dart';
import 'package:lupin_mobile/features/holding_area/domain/holding_area_bloc.dart';
import 'package:lupin_mobile/features/holding_area/presentation/filer_group_header.dart';
import 'package:lupin_mobile/features/holding_area/presentation/holding_area_pane.dart';

import '../../unit/_helpers/stub_dio.dart';

/// The whole pane, at 360×800.
///
/// 🔴 THE POINT OF TESTING THE PANE RATHER THAN ONLY ITS PARTS IS THE WIRING. A header
/// whose approve-all fires correctly and a bloc that batches correctly still add up to
/// nothing if the pane hands the wrong filer down, and both component suites pass while
/// it does.

Map<String, dynamic> _page( List<Map<String, dynamic>> rows, { bool hasMore = false } ) => {
      'tasks'     : rows,
      'truncated' : false,
      'has_more'  : hasMore,
      'total'     : rows.length,
      'warnings'  : <String>[],
    };

Map<String, dynamic> _row( String id, String filer ) => {
      'id'         : id,
      'title'      : '[LUPIN-MOBILE] Phase 4: held row $id with a long fleet-style title',
      'status'     : 'not_approved',
      'priority'   : 'P2',
      'created_by' : filer,
    };

Map<String, dynamic> _fixture( String name ) =>
    jsonDecode( File( 'test/fixtures/tasks/$name' ).readAsStringSync() )
        as Map<String, dynamic>;

List<String> _transitionIds( StubAdapter a ) => a.captured
    .where( ( o ) => o.method == 'POST' && o.path.contains( '/transition' ) )
    .map( ( o ) => Uri.decodeComponent( o.path.split( '/' )[ 3 ] ) )
    .toList();

/// ⚠️ `pumpAndSettle` ALONE IS NOT ENOUGH HERE, AND IT FAILS QUIETLY. It drives the
/// test's fake clock, and the stubbed HTTP response resolves on the REAL one — so the
/// fetch is still in flight when the assertions run and every pane test sees an empty
/// pane. `runAsync` lets real async actually happen before the frames are pumped.
Future<void> settle( WidgetTester tester ) async {
  await tester.runAsync( () => Future<void>.delayed( const Duration( milliseconds: 60 ) ) );
  await tester.pumpAndSettle();
}


void main() {
  late StubAdapter adapter;
  late HoldingAreaBloc bloc;

  setUp( () {
    adapter = StubAdapter();
    final dio = makeDio( adapter );
    bloc = HoldingAreaBloc( HoldingAreaRepository( dio ), TaskWriteRepository( dio ) );
    for ( final id in [ 'a', 'b', 'c' ] ) {
      adapter.handlers[ 'POST /api/tasks/$id/transition' ] = ( _ ) => jsonBody( {} );
    }
  } );

  tearDown( () async => bloc.close() );

  /// 360×800 — ordinary Android portrait, never the 800×600 harness default.
  Future<void> pumpPane( WidgetTester tester ) async {
    tester.view.physicalSize     = const Size( 360, 800 );
    tester.view.devicePixelRatio = 1.0;
    addTearDown( tester.view.resetPhysicalSize );
    addTearDown( tester.view.resetDevicePixelRatio );

    await tester.pumpWidget( MaterialApp(
      home : BlocProvider<HoldingAreaBloc>.value(
        value : bloc,
        child : const Scaffold( body: HoldingAreaPane() ),
      ),
    ) );
    await settle( tester );
  }

  void serve( List<Map<String, dynamic>> rows, { bool hasMore = false } ) {
    adapter.handlers[ 'GET ${HoldingAreaRepository.path}' ] =
        ( _ ) => jsonBody( _page( rows, hasMore: hasMore ) );
  }

  group( "the blocks", () {
    testWidgets( "one header per filer, and every held row rendered", ( tester ) async {
      serve( [ _row( 'a', 'sam' ), _row( 'b', 'chloe' ), _row( 'c', 'sam' ) ] );
      await pumpPane( tester );

      expect( find.byType( FilerGroupHeader ), findsNWidgets( 2 ) );
      expect( find.byType( TaskRow ), findsNWidgets( 3 ) );
    } );

    testWidgets( "🔴 renders the SHARED TaskRow, not a bespoke Holding Area row", ( tester ) async {
      // §7's mechanism is that the row takes no pane discriminator. A pane that grew its
      // own row would pass every other test in this file.
      serve( [ _row( 'a', 'sam' ) ] );
      await pumpPane( tester );

      expect( find.byType( TaskRow ), findsOneWidget );
    } );

    testWidgets( "no group collapses — every block stays open", ( tester ) async {
      serve( [ _row( 'a', 'sam' ), _row( 'b', 'sam' ) ] );
      await pumpPane( tester );

      await tester.tap( find.text( 'sam · 2' ) );
      await tester.pumpAndSettle();

      expect( find.byType( TaskRow ), findsNWidgets( 2 ),
          reason: 'tapping the heading must not hide held rows' );
    } );
  } );

  group( "empty, error, incomplete", () {
    testWidgets( "an empty held set says so", ( tester ) async {
      serve( const [] );
      await pumpPane( tester );

      expect( find.byKey( const Key( TestKeys.holdingEmptyState ) ), findsOneWidget );
    } );

    testWidgets( "an incomplete page raises the banner", ( tester ) async {
      serve( [ _row( 'a', 'sam' ) ], hasMore: true );
      await pumpPane( tester );

      expect( find.byKey( const Key( TestKeys.holdingIncompleteBanner ) ), findsOneWidget );
    } );

    testWidgets( "a fetch failure with no rows shows the error view and a retry", ( tester ) async {
      adapter.handlers[ 'GET ${HoldingAreaRepository.path}' ] =
          ( _ ) => jsonBody( { 'detail': 'boom' }, status: 500 );
      await pumpPane( tester );

      expect( find.byKey( const Key( TestKeys.holdingErrorView ) ), findsOneWidget );
      expect( find.text( 'Retry' ), findsOneWidget );
    } );
  } );

  group( "🔴 the batch, end to end through the pane", () {
    testWidgets( "approve-all confirms, then writes only that filer's rows", ( tester ) async {
      serve( [ _row( 'a', 'sam' ), _row( 'b', 'chloe' ), _row( 'c', 'sam' ) ] );
      await pumpPane( tester );

      await tester.tap( find.byKey( const Key( '${TestKeys.holdingApproveAllPrefix}sam' ) ) );
      await tester.pumpAndSettle();
      await tester.tap( find.byKey( const Key( TestKeys.holdingApproveAllConfirmOk ) ) );
      await settle( tester );

      expect( _transitionIds( adapter ), [ 'a', 'c' ],
          reason: "chloe's held row must not move" );
    } );

    testWidgets( "cancelling the confirm writes NOTHING", ( tester ) async {
      serve( [ _row( 'a', 'sam' ) ] );
      await pumpPane( tester );

      await tester.tap( find.byKey( const Key( '${TestKeys.holdingApproveAllPrefix}sam' ) ) );
      await tester.pumpAndSettle();
      await tester.tap( find.byKey( const Key( TestKeys.holdingApproveAllConfirmNo ) ) );
      await tester.pumpAndSettle();

      expect( _transitionIds( adapter ), isEmpty );
    } );

    testWidgets( "🔴 won't-fix-all with an empty box writes NOTHING and complains "
                 "in the field", ( tester ) async {
      serve( [ _row( 'a', 'sam' ), _row( 'c', 'sam' ) ] );
      await pumpPane( tester );

      await tester.tap( find.byKey( const Key( '${TestKeys.holdingWontFixAllPrefix}sam' ) ) );
      await settle( tester );

      expect( _transitionIds( adapter ), isEmpty );
      final field = tester.widget<TextField>(
        find.byKey( const Key( '${TestKeys.holdingReasonFieldPrefix}sam' ) ) );
      expect( field.decoration!.errorText, isNotNull );
    } );

    testWidgets( "typed reason reaches the wire on every row of the group", ( tester ) async {
      serve( [ _row( 'a', 'sam' ), _row( 'c', 'sam' ) ] );
      await pumpPane( tester );

      await tester.enterText(
        find.byKey( const Key( '${TestKeys.holdingReasonFieldPrefix}sam' ) ),
        'superseded by the rewrite',
      );
      // ⚠️ A REAL-TIME SETTLE AFTER THE TYPING TOO, NOT ONLY AFTER THE PRESS. The
      // keystroke reaches the bloc, but the pane's rebuild — and with it the fresh
      // callback that carries the typed reason — lands after `pumpAndSettle` has already
      // decided nothing more is scheduled. Without this the press fires the PREVIOUS
      // build's closure, sends an empty reason, and the test fails against a pane that
      // works.
      await settle( tester );
      await tester.tap( find.byKey( const Key( '${TestKeys.holdingWontFixAllPrefix}sam' ) ) );
      await settle( tester );

      final bodies = adapter.captured
          .where( ( o ) => o.path.contains( '/transition' ) )
          .map( ( o ) => ( o.data as Map ).cast<String, dynamic>() )
          .toList();

      expect( bodies.length, 2 );
      expect( bodies.every( ( b ) => b[ 'reason' ] == 'superseded by the rewrite' ), isTrue );
      expect( bodies.every( ( b ) => b[ 'to_status' ] == 'wont_fix' ), isTrue );
    } );

    testWidgets( "🔴 a partial batch leaves a notice ON SCREEN, not in a snackbar",
        ( tester ) async {
      // A snackbar takes it away on a timer while the rows it describes are still there,
      // and this is the one message this pane produces that the operator must act on.
      serve( [ _row( 'a', 'sam' ), _row( 'c', 'sam' ) ] );
      adapter.handlers[ 'POST /api/tasks/c/transition' ] =
          ( _ ) => jsonBody( { 'detail': 'nope' }, status: 500 );
      await pumpPane( tester );

      await tester.tap( find.byKey( const Key( '${TestKeys.holdingApproveAllPrefix}sam' ) ) );
      await tester.pumpAndSettle();
      await tester.tap( find.byKey( const Key( TestKeys.holdingApproveAllConfirmOk ) ) );
      await settle( tester );

      expect( find.byKey( const Key( TestKeys.holdingNotice ) ), findsOneWidget );
      expect( find.textContaining( '1 of 2' ), findsOneWidget );
      expect( find.byType( SnackBar ), findsNothing );
    } );
  } );

  group( "against the captured fixture", () {
    testWidgets( "the live page renders its two blocks at 360 dp without overflowing",
        ( tester ) async {
      adapter.handlers[ 'GET ${HoldingAreaRepository.path}' ] =
          ( _ ) => jsonBody( _fixture( 'holding_area.json' ) );
      await pumpPane( tester );

      expect( find.byType( FilerGroupHeader ), findsNWidgets( 2 ) );
      expect( tester.takeException(), isNull );
    } );
  } );
}
