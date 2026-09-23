import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/fleet/data/task_row_model.dart';
import 'package:lupin_mobile/features/holding_area/data/holding_area_models.dart';

/// Persona grouping and the batch controls' words.
///
/// ⚠️ THE GROUPING TESTS RUN AGAINST THE CAPTURED FIXTURE AS WELL AS AGAINST
/// HAND-BUILT ROWS, and the two jobs are different. The hand-built rows drive the edge
/// cases a live board does not happen to contain today; the fixture proves the grouper
/// survives the shape the server actually returns.
///
/// 🔴 TWO FIXTURES, AND THE SECOND ONE EXISTS BECAUSE THE FIRST CANNOT SEE THIS RULING.
/// `holding_area.json` is an eight-row page that happens to hold ONE session each of
/// "mr radio" and "maya" — so a grouper that merges a persona's sessions and one that
/// does not produce IDENTICAL output against it. R1=B would have been untestable
/// against the fixture that was here. `holding_area_multi_session.json` is a wider
/// capture from the same live producer, carrying "maria" and "mr radio" across two
/// sessions apiece.

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
    test( "🔴 two sessions of ONE persona make ONE group — Rick's R1=B", () {
      // 🔴 THIS CASE USED TO ASSERT THE OPPOSITE, AND IT IS INVERTED RATHER THAN DELETED.
      // It read "groups by the WHOLE created_by string, session hash included" and
      // pinned two sessions to two groups, on the argument that merging them widens
      // approve-all's blast radius past what the button says. Rick overruled that on
      // 2026-09-22 after walking the pane: *"I want you to group all sessions without
      // any explicit labeling under each persona… I don't give a shit about your notion
      // of session, it's irrelevant to me."*
      //
      // ⚠️ THE OLD TEST'S HAZARD IS REAL AND DID NOT GO AWAY — it moved to the case
      // below, "the count spans every session". The blast radius IS wider now; what must
      // hold is that the label says so.
      final groups = groupByFiler( [
        _row( id: 'a', createdBy: 'mr radio 078b97cb' ),
        _row( id: 'b', createdBy: 'mr radio 99999999' ),
      ] );

      expect( groups.length, 1 );
      expect( groups.single.filer, 'Mr Radio',
          reason: 'the persona, display-cased, with no session anywhere in it' );
      expect( groups.single.ids, [ 'a', 'b' ] );
    } );

    test( "🔴 the count and the ids span EVERY session, so the button cannot undercount",
        () {
      // The one thing R1=B still owes, per the walkthrough plan: *"A batch control whose
      // label undercounts what it does is a defect under any grouping scheme."* The
      // count and the send are the same rows by construction; this pins that they stay
      // that way across a session boundary, which is where they could diverge.
      final groups = groupByFiler( [
        _row( id: 'a', createdBy: 'mr radio 078b97cb' ),
        _row( id: 'b', createdBy: 'mr radio 078b97cb' ),
        _row( id: 'c', createdBy: 'mr radio 99999999' ),
      ] );

      expect( groups.single.count, 3 );
      expect( groups.single.ids.length, 3 );
      expect( batchLabel( "Approve", groups.single.count ), "Approve (3)" );
      expect( holdingApproveAllConfirmBody( groups.single.filer, groups.single.count ),
          contains( '3 rows filed by Mr Radio' ) );
    } );

    test( "a TWO-WORD persona survives — 'mr radio', never 'mr'", () {
      // 🔴 THE NAIVE `split(" ").first` RENDERS THIS AS "mr", AND IT WOULD ALSO SPLIT THE
      // GROUP: "mr" for the row with a session id and "mr radio" for the one without.
      // Measured wrong on 6 of 13 live rows in the web client, and those six are exactly
      // the ones this pane is for.
      final groups = groupByFiler( [
        _row( id: 'a', createdBy: 'mr radio 8fa24215' ),
        _row( id: 'b', createdBy: 'mr radio' ),
      ] );

      expect( groups.single.filer, 'Mr Radio' );
      expect( groups.single.count, 2 );
    } );

    test( "one persona stored under two casings is ONE group", () {
      // The live board holds "Krishna" and "maria" side by side — one store, two casing
      // conventions — so a grouper keyed on the raw persona splits a person in two. That
      // is the defect R1=B exists to remove, one level down.
      final groups = groupByFiler( [
        _row( id: 'a', createdBy: 'krishna 12c43f44' ),
        _row( id: 'b', createdBy: 'Krishna 99999999' ),
      ] );

      expect( groups.length, 1 );
      expect( groups.single.filer, 'Krishna' );
      expect( groups.single.ids, [ 'a', 'b' ] );
    } );

    test( "a bare session id with no name in front of it is shown WHOLE", () {
      // Pinned by the web client's JS-parity corpus, entry [ "0e61abe3", "0e61abe3" ].
      // An unexpected format shown in full is visibly odd and sends the reader to the
      // row; a truncated name is a WRONG name wearing a right one's clothes.
      final groups = groupByFiler( [ _row( id: 'a', createdBy: '0e61abe3' ) ] );

      expect( groups.single.filer, '0e61abe3' );
    } );

    test( "orders groups case-insensitively so the pane cannot reshuffle", () {
      final groups = groupByFiler( [
        _row( id: 'a', createdBy: 'zoe' ),
        _row( id: 'b', createdBy: 'Alice' ),
        _row( id: 'c', createdBy: 'bob' ),
      ] );

      expect( groups.map( ( g ) => g.filer ).toList(), [ 'Alice', 'Bob', 'Zoe' ] );
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
      // ⚠️ THE FALLBACK IS NOT A NAME AND MUST NOT BE DISPLAY-CASED INTO ONE. It is the
      // pane's word for "nobody", and putting it through the persona caser would make
      // it look like a persona called Unattributed.
      expect( groups.last.filer, 'Unattributed' );
    } );

    test( "Unattributed sorts LAST even against a filer named later in the alphabet", () {
      final groups = groupByFiler( [
        _row( id: 'a', createdBy: 'zoe' ),
        _row( id: 'b', createdBy: null ),
      ] );

      expect( groups.map( ( g ) => g.filer ).toList(), [ 'Zoe', kUnattributedFiler ] );
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
    test( "the live shape groups into the personas it actually contains", () {
      final groups = groupByFiler( _fixtureRows( 'holding_area.json' ) );

      // This page holds one session each, so it says nothing about merging — see the
      // wide fixture below for that. What it does prove is that the session hash is off
      // the label on real captured data, not only on rows a test author typed.
      expect( groups.map( ( g ) => g.filer ).toList(), [ 'Maya', 'Mr Radio' ] );
      expect( groups.map( ( g ) => g.count ).toList(), [ 1, 7 ] );
    } );

    test( "🔴 the WIDE capture merges each persona's two sessions into one group", () {
      // 🔴 THE CASE THE NARROW FIXTURE CANNOT CONTAIN. Censused live 2026-09-23: this
      // page carries `maria 171945f0` + `maria be26cc2d` and `mr radio 75c92041` +
      // `mr radio 8fa24215`. Against the eight-row fixture a merging grouper and a
      // non-merging one are indistinguishable, so R1=B needed a page wide enough to
      // hold a second session of somebody.
      final rows   = _fixtureRows( 'holding_area_multi_session.json' );
      final groups = groupByFiler( rows );

      // Six personas out of fourteen rows and eight distinct created_by values.
      expect(
        rows.map( ( r ) => r.createdBy ).toSet().length, 8,
        reason: 'eight sessions in the capture',
      );
      expect( groups.map( ( g ) => g.filer ).toList(),
          [ 'Krishna', 'Maria', 'Maya', 'Mr Radio', 'Rachel', 'Sam' ] );

      // The two multi-session personas, with the count the button will print.
      final maria = groups.firstWhere( ( g ) => g.filer == 'Maria' );
      final radio = groups.firstWhere( ( g ) => g.filer == 'Mr Radio' );
      expect( maria.count, 2, reason: '171945f0 + be26cc2d, one group' );
      expect( radio.count, 7, reason: '75c92041 (1) + 8fa24215 (6), one group' );

      // ⚠️ THE ASSERTION THAT ACTUALLY PINS THE MERGE: the group's ids come from more
      // than one session. A count alone would pass against two rows of one session.
      expect(
        maria.rows.map( ( r ) => r.createdBy ).toSet(),
        { 'maria 171945f0', 'maria be26cc2d' },
      );
      expect(
        radio.rows.map( ( r ) => r.createdBy ).toSet(),
        { 'mr radio 75c92041', 'mr radio 8fa24215' },
      );
    } );

    test( "🔴 every group's label is free of session hashes, on real captured data", () {
      // A single assertion over the whole capture, because "no session label anywhere"
      // is what Rick asked for and a per-persona spot check would miss a seventh one.
      final groups = groupByFiler( _fixtureRows( 'holding_area_multi_session.json' ) );
      final hash   = RegExp( r'[0-9a-f]{8}' );

      for ( final g in groups ) {
        expect( hash.hasMatch( g.filer ), isFalse, reason: '${g.filer} carries a session' );
      }
    } );

    test( "the wide capture's rows are all held, like the narrow one's", () {
      final rows = _fixtureRows( 'holding_area_multi_session.json' );
      expect( rows.length, 14 );
      expect( rows.every( ( r ) => r.status == 'not_approved' ), isTrue );
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
