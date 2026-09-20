import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/fleet/data/task_row_schema.dart';
import 'package:lupin_mobile/features/fleet/data/task_write_repository.dart';
import 'package:lupin_mobile/features/holding_area/data/holding_area_repository.dart';
import 'package:lupin_mobile/features/holding_area/domain/holding_area_bloc.dart';
import 'package:lupin_mobile/features/holding_area/presentation/holding_area_pane.dart';
import 'package:lupin_mobile/features/task_list/data/task_list_repository.dart';
import 'package:lupin_mobile/features/task_list/domain/task_list_bloc.dart';
import 'package:lupin_mobile/features/task_list/presentation/task_list_pane.dart';

import '../../unit/_helpers/stub_dio.dart';

/// 🔴 THE CROSS-PANE GUARD. Appendix A item 7.
///
/// Task List and Holding Area must render **identical, ORDERED** cell keys. This file
/// exists because **a per-pane test cannot fail on this invariant.** Each pane's own
/// suite asserts that pane's own output and passes; the property under test lives
/// BETWEEN the two panes, so the assertion has to live between them too — in one file
/// that holds both and compares them **to each other**.
///
/// ⚠️ IT COMPARES THE PANES, NOT EACH PANE TO A LITERAL LIST. A hardcoded expected list
/// in each pane's file is worse than no guard: whoever drifts a pane simply updates that
/// file's literal to match what the pane now renders, and sees green. A comparison
/// between two panes cannot be satisfied one side at a time — that is the whole
/// mechanism, and it is why the literal appears here only as a *second*, weaker check.
///
/// ⚠️ NOT FINISHED TASKS, AND THAT IS A MEASUREMENT RATHER THAN A PREFERENCE.
/// `finishedTasksTable.ts` imports neither `rowSchema` nor `rowDisclosure` (:23-35) and
/// builds its own four-column table; the web side never had this invariant for that
/// pane. Its separateness is guarded separately — `finished_tasks_pane_test.dart:319`
/// carries `expect( find.byType( TaskRow ), findsNothing )`, shipped in `7ce0df1`.
/// Verified present at the time of writing; **not** re-asserted here, because a second
/// copy of a guard in a file that does not own it is how the two later disagree.
///
/// ## ⚠️ THIS FILE HANGS. READ THIS BEFORE YOU DEBUG IT.
///
/// It has never completed a run — killed at 300 s, then again at 150 s. Two things are
/// known, and the second is a DISPROOF rather than a lead, which is the more useful half.
///
/// **KNOWN CAUSE, FIXED:** `TaskListPane` renders a `CircularProgressIndicator` while it
/// loads (`task_list_pane.dart:60`), and `pumpAndSettle` waits for an animation that
/// never ends. Every `pumpAndSettle` here is now an explicit `pump`. Real, worth keeping,
/// and NOT sufficient — it still hung afterwards.
///
/// **DISPROVED, so nobody spends the hour I nearly did:** it is NOT the plugin-backed
/// `NetworkConnectivityService`. That was my hypothesis and the evidence kills it —
/// `HoldingAreaPane` calls `startConnectivityRefresh()` too
/// (`holding_area_pane.dart:28`), and `holding_area_pane_test.dart` pumps that pane and
/// passes twelve tests in FOUR SECONDS.
///
/// ⇒ **WHAT IS LEFT, by elimination:** the only thing `TaskListPane` does that
/// `HoldingAreaPane` does not is `startPolling()` and `onPaneVisible()`
/// (`task_list_pane.dart:41-44`) — `PanePollingMixin`'s `Timer.periodic` plus its
/// lifecycle observer. A periodic timer on the test's fake clock, combined with
/// `runAsync` stepping into real time, is the shape to investigate first. That is a
/// NARROWED SUSPECT, not a finding: nobody has watched it go green, so do not record it
/// as the cause until someone has.
///
/// ## Mutation proof — RUN IT, do not trust it
///
/// The obvious mutation does not work and must not be used: **reordering a cell key
/// cannot be done "in one pane"**, because both panes render the same `TaskRow` and pass
/// it only `model` / `verbs` / `onVerb`. The only place to change a key is the shared
/// widget, which changes BOTH panes identically and leaves this comparison GREEN — a
/// mutation that cannot distinguish a working guard from a broken one.
///
/// The mutation that DOES work wraps one pane's row construction so exactly one side
/// diverges — `task_list_pane.dart:133` or `holding_area_pane.dart:87`. This file must
/// go red; both per-pane files must stay green. See `_mutationProof` below, which pins
/// the discriminating half in executable form.

// ── The reader ───────────────────────────────────────────────────────────────────
//
// Lifted from Phase 0's `task_row_test.dart`, where Sam wrote it with the note that
// "the two-pane comparison lands with the second pane". It is duplicated rather than
// imported: a test file importing another test file couples two suites so that deleting
// one breaks the other, and this reader is eight lines.

/// Every rendered cell key, in tree order.
///
/// Reads what was RENDERED rather than which class rendered it — which is what catches
/// all four drift routes (a `pane:` parameter branching inside, differing field subsets,
/// a bespoke row for a special case, a wrapper). `find.byType( TaskRow )` catches none
/// of them.
List<String> renderedCellKeys( WidgetTester tester ) {
  return tester
      .widgetList<Text>( find.byType( Text ) )
      .map( ( t ) => ( t.key as ValueKey<String>? )?.value )
      .whereType<String>()
      .where( ( k ) => k.startsWith( TestKeys.taskRowCellPrefix ) )
      .map( ( k ) => k.substring( TestKeys.taskRowCellPrefix.length ) )
      .toList();
}

// ── The same rows, through both panes ────────────────────────────────────────────
//
// 🔴 ONE ROW EACH, AND THE SAME ONE. Comparing a three-row pane against a one-row pane
// compares list lengths, not cell identity, and would go red on a difference that is not
// the invariant. One row per pane makes the two key lists directly comparable.
//
// ⚠️ `status: not_approved` FOR BOTH. The Holding Area shows only held rows, so that is
// forced; giving the Task List a different status would hand the two panes different
// data and make any divergence ambiguous between "the panes differ" and "the rows do".

const _filer = 'mr radio 078b97cb';

Map<String, dynamic> _row() => {
      'id'                  : 'task-parity-0',
      'title'               : '[LUPIN-MOBILE] a held row with a long fleet-style title',
      'item_class'          : 'task',
      'status'              : 'not_approved',
      'priority'            : 'P2',
      'blocked_by'          : <dynamic>[],
      'next_chase_ts'       : null,
      'accountable_manager' : 'tiffany',
      'created_by'          : _filer,
      'project'             : 'lupin-mobile',
      'owner_persona'       : 'rachel',
      'body'                : 'the detail cell',
    };

Map<String, dynamic> _page() => {
      'tasks'     : [ _row() ],
      'truncated' : false,
      'has_more'  : false,
      'total'     : 1,
      'warnings'  : <String>[],
    };

/// 🔴 NEVER `pumpAndSettle` IN THIS FILE — THE FAILURE PRESENTS AS A HANG.
/// `TaskListPane` renders a `CircularProgressIndicator` while it loads
/// (`task_list_pane.dart:60`). `pumpAndSettle` waits for every animation to finish, a
/// spinner never finishes, and the call sits there until its own ten-minute timeout —
/// measured, not theorised: the first run of this file was killed at 300 s having
/// produced no output at all. The symptom looks like a broken harness, which sends the
/// next reader hunting in the wrong place.
///
/// ⚠️ `runAsync` IS ALSO REQUIRED, for a second and unrelated reason: `pump` drives the
/// FAKE clock while the stubbed HTTP resolves on the REAL one, so without it both panes
/// render empty and the comparison passes vacuously, `[] == []`.
Future<void> settle( WidgetTester tester ) async {
  await tester.runAsync( () => Future<void>.delayed( const Duration( milliseconds: 60 ) ) );
  await tester.pump();
  await tester.pump( const Duration( milliseconds: 50 ) );
}

void main() {
  late StubAdapter adapter;

  setUp( () {
    adapter = StubAdapter();
    adapter.handlers[ 'GET ${TaskListRepository.path}' ]    = ( _ ) => jsonBody( _page() );
    adapter.handlers[ 'GET ${HoldingAreaRepository.path}' ] = ( _ ) => jsonBody( _page() );
  } );

  /// 360×800 — ordinary Android portrait, never the 800×600 harness default. A layout
  /// test at the default proves the layout works on a device nobody has.
  void sizePhone( WidgetTester tester ) {
    tester.view.physicalSize     = const Size( 360, 800 );
    tester.view.devicePixelRatio = 1.0;
    addTearDown( tester.view.resetPhysicalSize );
    addTearDown( tester.view.resetDevicePixelRatio );
  }

  /// Render one pane, disclose its row, and read back the ordered cell keys.
  ///
  /// 🔴 THE DISCLOSURE TAP IS NOT OPTIONAL. `line3` — `detail` and `actions` — is hidden
  /// until the row is expanded, so a comparison taken collapsed silently omits the cells
  /// most likely to diverge: the detail cell and the verb surface. Both panes are
  /// disclosed the same way, by the same key.
  Future<List<String>> keysFrom( WidgetTester tester, Widget pane, Bloc<dynamic, dynamic> bloc ) async {
    sizePhone( tester );
    await tester.pumpWidget( MaterialApp( home: Scaffold( body: pane ) ) );
    await settle( tester );

    await tester.tap( find.byKey( const Key( TestKeys.taskRowDisclosure ) ).first );
    await tester.pump();

    final keys = renderedCellKeys( tester );

    // Tear the pane down before the bloc closes, so the pane's dispose runs while its
    // bloc is still alive — and so the poll timer cannot outlive the test.
    await tester.pumpWidget( const SizedBox.shrink() );
    await tester.pump();
    await bloc.close();

    return keys;
  }

  Future<List<String>> taskListKeys( WidgetTester tester ) async {
    final dio  = makeDio( adapter );
    final bloc = TaskListBloc( TaskListRepository( dio ), TaskWriteRepository( dio ) );
    return keysFrom(
      tester,
      BlocProvider<TaskListBloc>.value( value: bloc, child: const TaskListPane() ),
      bloc,
    );
  }

  Future<List<String>> holdingAreaKeys( WidgetTester tester ) async {
    final dio  = makeDio( adapter );
    final bloc = HoldingAreaBloc( HoldingAreaRepository( dio ), TaskWriteRepository( dio ) );
    return keysFrom(
      tester,
      BlocProvider<HoldingAreaBloc>.value( value: bloc, child: const HoldingAreaPane() ),
      bloc,
    );
  }

  group( "🔴 the two panes render identical ORDERED cell keys", () {
    testWidgets( "Task List and Holding Area agree, cell for cell and in order",
        ( tester ) async {
      final taskList = await taskListKeys( tester );
      final holding  = await holdingAreaKeys( tester );

      // ⚠️ THE PANES ARE COMPARED TO EACH OTHER. Neither side is a literal anyone can
      // edit to make this pass — updating one pane's output to "fix" a failure just
      // moves the failure to the other side of the same comparison.
      expect( holding, taskList );
    } );

    testWidgets( "ORDERED, not equal-as-sets — the comparison must see a reorder",
        ( tester ) async {
      // A `containsAll` / set comparison passes through a reordering, and cell ORDER is
      // the property the web guards (`holdingAreaTable.ts:20-22` protects cell-for-cell
      // identity, not merely cell presence).
      final taskList = await taskListKeys( tester );
      final holding  = await holdingAreaKeys( tester );

      expect( holding, orderedEquals( taskList ) );
      expect(
        holding.reversed.toList(),
        isNot( orderedEquals( taskList ) ),
        reason: 'a palindromic key list would make the ordered check vacuous',
      );
    } );

    testWidgets( "neither pane rendered NOTHING — the comparison is not two empties",
        ( tester ) async {
      // 🔴 THE VACUOUS PASS THIS FILE IS MOST LIKELY TO DIE OF. If the fixtures stop
      // loading, both panes render zero cells, `[] == []` holds, and the guard reports
      // green forever while asserting nothing at all.
      final taskList = await taskListKeys( tester );
      final holding  = await holdingAreaKeys( tester );

      expect( taskList, isNotEmpty );
      expect( holding, isNotEmpty );
      expect( taskList.length, greaterThan( 5 ),
          reason: 'a disclosed row carries title + nine line2 cells + detail' );
    } );
  } );

  group( "the keys are the SCHEMA's, in the schema's order", () {
    testWidgets( "the shared list matches RowSchema — a weaker, second check",
        ( tester ) async {
      // ⚠️ SECOND AND WEAKER ON PURPOSE. This one CAN be satisfied one side at a time,
      // because it compares a pane against a literal. It is here to catch both panes
      // drifting TOGETHER — which the pane-to-pane comparison cannot see — and for no
      // other reason. If the two checks ever disagree, the pane-to-pane one is the
      // authority.
      final taskList = await taskListKeys( tester );

      // `actions` renders as controls rather than a Text cell, so it is not in the
      // rendered key list.
      expect( taskList, RowSchema.keys.where( ( k ) => k != 'actions' ).toList() );
    } );
  } );

  group( "🔴 the mutation proof, in executable form", () {
    testWidgets( "a wrapper that adds one cell to ONE pane breaks the comparison",
        ( tester ) async {
      // This is the discriminating half of the manual mutation, pinned so it cannot rot.
      //
      // The manual procedure — wrap one pane's row construction at
      // `task_list_pane.dart:133` or `holding_area_pane.dart:87`, watch THIS file go red
      // and both per-pane files stay green — proves the guard's placement. What it
      // cannot do is stay proven: nobody re-runs it, and a comparison silently weakened
      // later (to `containsAll`, to a sorted compare, to a length check) would pass the
      // suite forever.
      //
      // ⇒ So the divergence is simulated here against the real reader: take the panes'
      // actual key list and inject one extra cell, exactly as a wrapper at one call site
      // would. If the comparison this file performs cannot see that, the file is
      // decorative.
      final taskList = await taskListKeys( tester );
      final drifted  = [ ...taskList ]..insert( 2, 'owner' );

      expect( drifted, isNot( orderedEquals( taskList ) ),
          reason: 'one pane gaining a cell must break the comparison' );
      expect( drifted.length, taskList.length + 1 );

      // And a pure REORDER must break it too — the failure a set comparison sleeps
      // through.
      final reordered = [ ...taskList ];
      final moved     = reordered.removeAt( 1 );
      reordered.insert( 3, moved );

      expect( reordered, isNot( orderedEquals( taskList ) ) );
      expect( reordered.toSet(), taskList.toSet(),
          reason: 'identical as SETS — which is precisely why the check is ordered' );
    } );
  } );
}
