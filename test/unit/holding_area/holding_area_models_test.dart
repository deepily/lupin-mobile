import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/fleet/data/task_row_model.dart';
import 'package:lupin_mobile/features/holding_area/data/holding_area_models.dart';

/// Filer grouping and the batch controls' words.
///
/// ⚠️ THE GROUPING TESTS RUN AGAINST THE CAPTURED FIXTURE AS WELL AS AGAINST
/// HAND-BUILT ROWS, and the two jobs are different. The hand-built rows drive the edge
/// cases a live board does not happen to contain today; the fixture proves the grouper
/// survives the shape the server actually returns.

TaskRowModel _row( { required String id, String? createdBy } ) => TaskRowModel(
      id        : id,
      title     : 'row $id',
      status    : 'not_approved',
      createdBy : createdBy,
    );

List<TaskRowModel> _fixtureRows( String name ) {
  final raw  = File( 'test/fixtures/tasks/$name' ).readAsStringSync();
  final json = jsonDecode( raw ) as Map<String, dynamic>;
  return ( json[ 'tasks' ] as List )
      .whereType<Map<String, dynamic>>()
      .map( TaskRowModel.fromJson )
      .toList();
}

void main() {
  group( "groupByFiler", () {
    test( "groups by the WHOLE created_by string, session hash included", () {
      // 🔴 THE DEFECT THIS PINS: stripping the hash to group by bare persona merges one
      // persona's sessions into one group, which makes approve-all's blast radius WIDER
      // than the name on the button says. Two sessions, two groups.
      final groups = groupByFiler( [
        _row( id: 'a', createdBy: 'mr radio 078b97cb' ),
        _row( id: 'b', createdBy: 'mr radio 99999999' ),
      ] );

      expect( groups.length, 2 );
      expect( groups.map( ( g ) => g.filer ),
          containsAll( [ 'mr radio 078b97cb', 'mr radio 99999999' ] ) );
    } );

    test( "orders groups case-insensitively so the pane cannot reshuffle", () {
      final groups = groupByFiler( [
        _row( id: 'a', createdBy: 'zoe' ),
        _row( id: 'b', createdBy: 'Alice' ),
        _row( id: 'c', createdBy: 'bob' ),
      ] );

      expect( groups.map( ( g ) => g.filer ).toList(), [ 'Alice', 'bob', 'zoe' ] );
    } );

    test( "keeps the SERVER's row order inside a group", () {
      // The store returns newest first. Re-sorting inside a group would silently
      // reorder what the operator is about to batch.
      final groups = groupByFiler( [
        _row( id: 'third',  createdBy: 'sam' ),
        _row( id: 'first',  createdBy: 'sam' ),
        _row( id: 'second', createdBy: 'sam' ),
      ] );

      expect( groups.single.ids, [ 'third', 'first', 'second' ] );
    } );

    test( "a row with NO filer is kept in one trailing Unattributed group", () {
      // A held row nobody can see is worse than an odd label — and this pane is the
      // only place a held row is visible at all.
      final groups = groupByFiler( [
        _row( id: 'a', createdBy: 'sam' ),
        _row( id: 'b', createdBy: null ),
        _row( id: 'c', createdBy: '   ' ),
      ] );

      expect( groups.last.filer, kUnattributedFiler );
      expect( groups.last.ids, [ 'b', 'c' ], reason: 'blank and null land together' );
      expect( groups.length, 2 );
    } );

    test( "Unattributed sorts LAST even against a filer named later in the alphabet", () {
      final groups = groupByFiler( [
        _row( id: 'a', createdBy: 'zoe' ),
        _row( id: 'b', createdBy: null ),
      ] );

      expect( groups.map( ( g ) => g.filer ).toList(), [ 'zoe', kUnattributedFiler ] );
    } );

    test( "an empty page yields no groups, not a group of nothing", () {
      expect( groupByFiler( const <TaskRowModel>[] ), isEmpty );
    } );

    test( "ids match the rows, so the batch cannot act on a different set", () {
      final groups = groupByFiler( [
        _row( id: 'a', createdBy: 'sam' ),
        _row( id: 'b', createdBy: 'sam' ),
      ] );

      expect( groups.single.ids.length, groups.single.count );
      expect( groups.single.ids, [ 'a', 'b' ] );
    } );
  } );

  group( "against the captured fixture", () {
    test( "the live shape groups into the filers it actually contains", () {
      final groups = groupByFiler( _fixtureRows( 'holding_area.json' ) );

      expect( groups.map( ( g ) => g.filer ).toList(),
          [ 'maya 371d6d91', 'mr radio 078b97cb' ] );
      expect( groups.map( ( g ) => g.count ).toList(), [ 1, 7 ] );
    } );

    test( "every fixture row is held — this pane is status=not_approved, not a filter", () {
      final rows = _fixtureRows( 'holding_area.json' );
      expect( rows, isNotEmpty );
      expect( rows.every( ( r ) => r.status == 'not_approved' ), isTrue );
    } );

    test( "the empty fixture yields no groups", () {
      expect( groupByFiler( _fixtureRows( 'holding_area_empty.json' ) ), isEmpty );
    } );
  } );

  group( "the batch controls' words", () {
    test( "the count rides INSIDE the label, not beside it", () {
      // The web prints it in a span next to the filer name, so the operator reads the
      // blast radius somewhere other than on the control they are about to press.
      expect( batchLabel( "Approve", 14 ), "Approve (14)" );
      expect( batchLabel( "Won't fix all", 1 ), "Won't fix all (1)" );
    } );

    test( "approve-all's hint states that it is REVERSIBLE", () {
      // That sentence is the entire justification for its lighter gating. If it stops
      // being said, the gating stops being defensible.
      expect( holdingApproveAllHint( 'sam' ), contains( 'reversible' ) );
      expect( holdingApproveAllHint( 'sam' ), contains( 'sam' ) );
    } );

    test( "won't-fix-all's hint states TERMINAL and the one-reason-for-all rule", () {
      final hint = holdingWontFixAllHint( 'sam' );
      expect( hint, contains( 'TERMINAL' ) );
      expect( hint, contains( 'SAME' ) );
      expect( hint, contains( 'per-row control' ) );
    } );

    test( "the confirm body carries BOTH the count and the filer", () {
      // They are the two facts that decide the answer. Inferring either from the pane
      // behind a modal is not reading it.
      final body = holdingApproveAllConfirmBody( 'sam', 14 );
      expect( body, contains( '14 rows' ) );
      expect( body, contains( 'sam' ) );
      expect( body, contains( 'reversible' ) );
    } );

    test( "the confirm body says 'row' not 'rows' for a group of one", () {
      expect( holdingApproveAllConfirmBody( 'sam', 1 ), contains( '1 row filed' ) );
    } );

    test( "the confirm's accept button repeats the VERB, never 'OK'", () {
      // It is often the only thing focus lands on, and "OK" names neither the action
      // nor its size.
      expect( holdingApproveAllConfirmAccept( 14 ), "Approve (14)" );
    } );
  } );
}
