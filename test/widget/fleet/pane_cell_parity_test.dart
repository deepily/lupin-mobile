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
/// ## It used to hang. It does not any more, and the cause was none of the obvious ones.
///
/// This file went months without completing a single run — killed at 300 s, then 150 s,
/// then 240 s. THREE suspects died before the right one, and the two disproofs are worth
/// more than the fix, because each was plausible enough to cost someone an evening:
///
///   1. **`CircularProgressIndicator` vs `pumpAndSettle`** — real, and fixed (every
///      `pumpAndSettle` here is an explicit `pump`). NOT the cause; it still hung after.
///   2. **`NetworkConnectivityService`** — disproved: `HoldingAreaPane` calls
///      `startConnectivityRefresh()` too (`holding_area_pane.dart:28`) and its own test
///      passes twelve cases in four seconds.
///   3. **`PanePollingMixin`'s `Timer.periodic`** — the narrowed suspect, and WRONG. It
///      looked guilty because `HoldingAreaPane` genuinely did not call `startPolling()`,
///      so the difference between the panes really was the timer — just not the
///      difference that mattered.
///
///      ⚠️ THAT ASYMMETRY IS GONE: the Holding Area now starts polling like its sibling
///      (gap G3, closed 2026-09-23). The post-mortem is kept as written because its
///      value is the DISPROOF — the timer was not the cause then, and both panes
///      carrying one now is the evidence that it never was.
///
/// ⇒ **THE ACTUAL CAUSE: `await bloc.close()` inside a `testWidgets` body.** Isolated by
/// elimination, each case its own probe:
///
/// | probe | result |
/// |---|---|
/// | bare `Bloc`, no handlers, no mixin | closes fine |
/// | **ONE `on<Event>` handler, no mixin** | **HANGS** |
/// | `TaskListBloc` / `HoldingAreaBloc` | HANGS |
/// | all of the above in a plain `test()` | close fine |
///
/// `close()` waits for its handler subscriptions to cancel; that completes only on the
/// REAL event loop; the fake-async zone a `testWidgets` body runs in never turns while
/// the body is parked on an await. Fix is at [closedAtTeardown] — the close is registered
/// with `addTearDown` and runs after the body, outside that zone, with the reasoning
/// beside it.
///
/// ⚠️ **The first working fix was `await tester.runAsync( () => bloc.close() )`**, and it
/// is the form every earlier note in this file described. It worked for the same reason:
/// it steps out to the real loop. It was replaced on 2026-09-22 with María's `addTearDown`
/// form after that form was measured — identical wall-clock, no pending-timer complaint,
/// and it moves the close out of the body entirely instead of carving a hole in it. If
/// you are reading a note elsewhere that still says `runAsync`, this paragraph is newer.
///
/// 🔴 **THIS IS NOT SPECIFIC TO THIS FILE.** Any widget test in this repo that awaits a
/// feature bloc's `close()` will hang identically, with no output and no error. If you
/// arrived here from a hanging test of your own, that is your answer.
///
/// ## Mutation proof — it is executable, and it can fail
///
/// The obvious mutation does not work and must not be used: **reordering a cell key
/// cannot be done "in one pane"**, because both panes render the same `TaskRow` and pass
/// it only `model` / `verbs` / `onVerb`. The only place to change a key is the shared
/// widget, which changes BOTH panes identically and leaves this comparison GREEN — a
/// mutation that cannot distinguish a working guard from a broken one.
///
/// The manual mutation that DOES work wraps one pane's row construction so exactly one
/// side diverges — `task_list_pane.dart:133` or `holding_area_pane.dart:87`. Run
/// 2026-09-22: this file RED on exactly the two pane-to-pane tests, all three per-pane
/// files GREEN.
///
/// ⚠️ But a manual proof decays the moment someone weakens the comparison, which is why
/// the group at the bottom pins it. **That pin was itself hollow until review caught it**
/// — it re-tested `orderedEquals` rather than the guard, and stayed green through the
/// exact weakening its comment claimed to catch. It now routes through [assertParity],
/// the single function every parity assertion uses, so softening that one function turns
/// the proof red.

// ── The reader ───────────────────────────────────────────────────────────────────
//
// Lifted from Phase 0's `task_row_test.dart`, where Sam wrote it with the note that
// "the two-pane comparison lands with the second pane". It is duplicated rather than
// imported: a test file importing another test file couples two suites so that deleting
// one breaks the other, and this reader is eight lines.

/// 🔴 THE ONE COMPARISON THIS FILE PERFORMS — AND THE ONLY ONE. Every parity assertion
/// below routes through here, and so does the mutation proof.
///
/// ⚠️ THAT SHARING IS THE WHOLE POINT, NOT TIDINESS. The previous mutation proof built a
/// drifted list and compared it with a FRESH inline `orderedEquals`, so it asserted a
/// property of Dart rather than a property of this guard. Weakening the real comparison
/// to `containsAll` left it GREEN — measured, not argued — which is precisely the threat
/// its own comment claimed it defended against. Found by María in review; the guard had
/// teeth, the thing pinning the guard did not.
///
/// ⇒ Because the proof calls THIS function, softening it turns the proof RED. A test that
/// cannot be made to fail is not evidence, and the fix is to give it one throat to choke.
void assertParity( List<String> expected, List<String> actual ) {
  expect( actual, orderedEquals( expected ) );
}

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
  ///
  /// 🔴 `unfoldGroup` IS A SECOND, OUTER DISCLOSURE AND ONLY THE HOLDING AREA HAS ONE.
  /// Rick's N2 ruling of 2026-09-22 made that pane's persona groups arrive FOLDED, so
  /// its rows are not in the tree at all until a group is opened; the Task List's groups
  /// still arrive open. Without this the Holding Area contributes zero cells and the
  /// comparison is `[] vs [ … ]`.
  ///
  /// ⚠️ IT DOES NOT WEAKEN THE PARITY CLAIM, AND THE DISTINCTION IS THE WHOLE POINT OF
  /// THE PARAMETER. What this file guards is that the two panes render the same ROW,
  /// cell for cell and in order. Which rows are on screen, and behind how many taps, is
  /// a PANE decision the two are allowed to differ on — batch controls already differ.
  /// The row disclosure below is still tapped identically on both, by the same key, and
  /// the "neither pane rendered NOTHING" case is what stops this parameter being used to
  /// paper over an empty pane. That case is what caught the fold in the first place.
  Future<List<String>> keysFrom(
    WidgetTester tester,
    Widget pane, {
    Finder? unfoldGroup,
  } ) async {
    sizePhone( tester );
    await tester.pumpWidget( MaterialApp( home: Scaffold( body: pane ) ) );
    await settle( tester );

    if ( unfoldGroup != null ) {
      await tester.tap( unfoldGroup );
      await settle( tester );
    }

    await tester.tap( find.byKey( const Key( TestKeys.taskRowDisclosure ) ).first );
    await tester.pump();

    final keys = renderedCellKeys( tester );

    // Tear the pane down while its bloc is still alive, so the pane's dispose runs
    // against a live bloc — and so no widget is left holding one at teardown.
    await tester.pumpWidget( const SizedBox.shrink() );
    await tester.pump();

    return keys;
  }

  /// 🔴 WHY THE CLOSE IS REGISTERED HERE AND NOT AWAITED IN THE BODY.
  ///
  /// `await bloc.close()` inside a `testWidgets` body NEVER RETURNS for any bloc
  /// carrying at least one `on<Event>` handler: `close()` waits for the handler
  /// subscriptions to cancel, that cancellation only completes on the REAL event loop,
  /// and the fake-async zone a `testWidgets` body runs in never turns it while the body
  /// is parked on an await. That is the hang documented at the top of this file.
  ///
  /// `addTearDown` sidesteps it for the same underlying reason `runAsync` did, one step
  /// later: teardown callbacks run AFTER the body, outside the fake-async zone, on the
  /// real loop. María suggested this form in review; it replaced
  /// `await tester.runAsync( () => bloc.close() )` once it was MEASURED rather than
  /// reasoned about — see the measurement note below.
  ///
  /// ⚠️ IT IS NOT A PURE SUBSTITUTION, AND THE DIFFERENCE IS THE PART WORTH CHECKING.
  /// The `runAsync` form closed each bloc INSIDE the body, before the next pane was
  /// built. This form leaves both panes' blocs open until the test ends, which means
  /// `TaskListBloc`'s `Timer.periodic` is still live when `flutter_test` runs its
  /// pending-timer check. Measured 2026-09-22: five tests green in 5.0 s, no
  /// "A Timer is still pending" — the pane's dispose cancels the poll before teardown
  /// is reached. That is a measurement about THIS file, not a general licence; a pane
  /// that leaked its timer would fail here, which is the behaviour you want.
  /// ⚠️ AND THE REGISTRATION ORDER BELOW IS THE PART THAT MAKES IT EVIDENCE.
  ///
  /// A bare `addTearDown( bloc.close )` is invisible: if it silently did nothing, every
  /// test here would still pass and the bloc would just leak. That is the same shape as
  /// the hollow mutation proof María found in this file — a control that cannot fail.
  ///
  /// `addTearDown` callbacks run **LIFO**, so the check registered FIRST runs LAST, after
  /// the close. `isClosed` is therefore read at the one moment it can discriminate.
  /// Proved by mutation 2026-09-22: commenting out the `bloc.close` line turns all five
  /// tests RED with "the teardown close did not run", and restoring it turns them green.
  B closedAtTeardown<B extends BlocBase<dynamic>>( B bloc ) {
    addTearDown( () => expect(
      bloc.isClosed,
      isTrue,
      reason: "the teardown close did not run — ${bloc.runtimeType} leaked out of this test",
    ) );
    addTearDown( bloc.close );
    return bloc;
  }

  Future<List<String>> taskListKeys( WidgetTester tester ) async {
    final dio  = makeDio( adapter );
    final bloc = closedAtTeardown(
      TaskListBloc( TaskListRepository( dio ), TaskWriteRepository( dio ) ),
    );
    return keysFrom(
      tester,
      BlocProvider<TaskListBloc>.value( value: bloc, child: const TaskListPane() ),
    );
  }

  Future<List<String>> holdingAreaKeys( WidgetTester tester ) async {
    final dio  = makeDio( adapter );
    final bloc = closedAtTeardown(
      HoldingAreaBloc( HoldingAreaRepository( dio ), TaskWriteRepository( dio ) ),
    );
    return keysFrom(
      tester,
      BlocProvider<HoldingAreaBloc>.value( value: bloc, child: const HoldingAreaPane() ),
      // The persona label, not the stored `created_by` — R1=B strips the session.
      unfoldGroup : find.byKey( const Key( '${TestKeys.holdingGroupTogglePrefix}Mr Radio' ) ),
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
      assertParity( taskList, holding );
    } );

    testWidgets( "ORDERED, not equal-as-sets — the comparison must see a reorder",
        ( tester ) async {
      // A `containsAll` / set comparison passes through a reordering, and cell ORDER is
      // the property the web guards (`holdingAreaTable.ts:20-22` protects cell-for-cell
      // identity, not merely cell presence).
      final taskList = await taskListKeys( tester );
      final holding  = await holdingAreaKeys( tester );

      assertParity( taskList, holding );
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
      // 🔴 DERIVED, NOT TYPED — `task_row_schema.dart:78-81` in this same tree says it
      // outright: "A count typed as a literal goes wrong silently." This assertion USED
      // to read `greaterThan( 5 )`, and María counted what that actually permits: the
      // schema carries 12 cells, 11 of them rendered as Text, so a pane could lose FIVE
      // of eleven and still pass. A loose bound on a derived quantity is the same defect
      // as a stale colspan, wearing a test's clothes.
      expect( taskList.length, RowSchema.cellCount - 1,
          reason: 'every schema cell but `actions`, which renders as controls not a Text' );
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

      // ONE pane gaining a cell, exactly as a wrapper at one call site would produce.
      final drifted = [ ...taskList ]..insert( 2, 'owner' );
      expect( () => assertParity( taskList, drifted ), throwsA( isA<TestFailure>() ),
          reason: 'one pane gaining a cell must break the comparison' );

      // A pure REORDER must break it too — the failure a set comparison sleeps through.
      final reordered = [ ...taskList ];
      final moved     = reordered.removeAt( 1 );
      reordered.insert( 3, moved );

      expect( () => assertParity( taskList, reordered ), throwsA( isA<TestFailure>() ) );
      expect( reordered.toSet(), taskList.toSet(),
          reason: 'identical as SETS — which is precisely why the check is ordered' );

      // 🔴 AND THE HONEST CASE MUST STILL PASS. Without this line, softening
      // `assertParity` into a no-op would satisfy neither throw above — so whoever
      // softened it would simply delete the two expectations and see green. This is the
      // line that makes deleting the proof louder than fixing it. María's addition.
      expect( () => assertParity( taskList, taskList ), returnsNormally );
    } );
  } );
}
