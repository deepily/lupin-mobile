import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/fleet/presentation/task_row.dart';
import 'package:lupin_mobile/features/finished_tasks/data/finished_tasks_models.dart';
import 'package:lupin_mobile/features/finished_tasks/data/finished_tasks_repository.dart';
import 'package:lupin_mobile/features/finished_tasks/domain/finished_tasks_bloc.dart';
import 'package:lupin_mobile/features/finished_tasks/domain/finished_tasks_event.dart';
import 'package:lupin_mobile/features/finished_tasks/presentation/finished_tasks_screen.dart';

/// Widget tier for the Finished Tasks pane.
///
/// The load-bearing test in this file is `does NOT render the shared row`. Read its
/// comment before changing anything here.

// ── A repository that answers from memory, so no server is involved ──────────────
class _FakeRepo implements FinishedTasksRepository {
  final Map<String, List<FinishedTaskEvent>> byStatus;
  final Map<String, String>                  failures;
  int calls = 0;

  _FakeRepo( { required this.byStatus, this.failures = const {} } );

  @override
  Future<FinishedFetchResult> fetchWindow( {
    required int days,
    required DateTime now,
  } ) async {
    calls += 1;
    return FinishedFetchResult(
      eventsByStatus : byStatus,
      failures       : failures,
      windowDays     : clampWindowDays( days ),
    );
  }

  @override
  dynamic noSuchMethod( Invocation invocation ) => super.noSuchMethod( invocation );
}

FinishedTaskEvent _ev( int id, String status, { String? title, String? actor, String? reason } ) {
  return FinishedTaskEvent(
    id         : id,
    itemId     : "item-$id",
    ts         : DateTime.now().subtract( Duration( hours: id ) ),
    actor      : actor ?? "mr radio 8353ea70",
    transition : "in_progress->$status",
    reason     : reason,
    title      : title ?? "row $id",
  );
}

Widget _host( _FakeRepo repo ) {
  return MaterialApp(
    home: BlocProvider(
      create: ( _ ) => FinishedTasksBloc( repo )..add( const FinishedTasksRequested() ),
      child : const FinishedTasksScreen(),
    ),
  );
}

void main() {
  /// 🔴 EVERY TEST IN THIS FILE RENDERS AT 360x800, NOT THE 800x600 DEFAULT.
  ///
  /// Crew standard, Tiffany 2026-09-19, and this pane is the one that earned the
  /// argument for it: the cascade's §7.2 finding is that four columns plus a control
  /// leave about 90 dp for the title at 360 dp. A layout test at the harness default
  /// is 800 dp wide — wider than any phone this ships to — so it proves the layout
  /// works on a device nobody has, and a real overflow arrives green.
  setUp( () {} );

  Future<void> pumpPhone( WidgetTester tester, Widget app ) async {
    tester.view.physicalSize     = const Size( 360, 800 );
    tester.view.devicePixelRatio = 1.0;
    addTearDown( tester.view.reset );
    await tester.pumpWidget( app );
    await tester.pumpAndSettle();
  }

  group( "the four cells", () {
    testWidgets( "renders When, Title, Who and Why for a row", ( tester ) async {
      final repo = _FakeRepo( byStatus: {
        "done"     : [ _ev( 1, "done", title: "Ship the pane", reason: "landed" ) ],
        "dropped"  : const [],
        "wont_fix" : const [],
      } );
      await pumpPhone( tester, _host( repo ) );

      expect( find.byKey( const Key( "${TestKeys.finishedRowWhenPrefix}1" ) ),  findsOneWidget );
      expect( find.byKey( const Key( "${TestKeys.finishedRowTitlePrefix}1" ) ), findsOneWidget );
      expect( find.byKey( const Key( "${TestKeys.finishedRowWhoPrefix}1" ) ),   findsOneWidget );
      expect( find.byKey( const Key( "${TestKeys.finishedRowWhyPrefix}1" ) ),   findsOneWidget );
      expect( find.text( "Ship the pane" ), findsOneWidget );
    } );

    testWidgets( "Who shows a TWO-WORD persona without its session id", ( tester ) async {
      final repo = _FakeRepo( byStatus: {
        "done": [ _ev( 1, "done", actor: "mr radio 8353ea70" ) ],
      } );
      await pumpPhone( tester, _host( repo ) );
      expect( find.text( "mr radio" ), findsOneWidget );
    } );

    testWidgets( "a missing Why renders the em dash, not an empty cell", ( tester ) async {
      final repo = _FakeRepo( byStatus: {
        "done": [ _ev( 1, "done", reason: null ) ],
      } );
      await pumpPhone( tester, _host( repo ) );
      final why = tester.widget<Text>(
        find.byKey( const Key( "${TestKeys.finishedRowWhyPrefix}1" ) ),
      );
      expect( why.data, kFinishedUnmeasured );
    } );
  } );

  group( "the status glyph", () {
    testWidgets( "is a PREFIX inside the When cell, never a fifth cell", ( tester ) async {
      final repo = _FakeRepo( byStatus: {
        "done": [ _ev( 1, "done" ) ],
      } );
      await pumpPhone( tester, _host( repo ) );

      final glyph = find.byKey( const Key( "${TestKeys.finishedRowGlyphPrefix}1" ) );
      final when  = find.byKey( const Key( "${TestKeys.finishedRowWhenPrefix}1" ) );
      expect( glyph, findsOneWidget );

      // The glyph shares the When cell's horizontal band rather than occupying a
      // column of its own: same vertical centre, to the LEFT of the age.
      final glyphBox = tester.getRect( glyph );
      final whenBox  = tester.getRect( when );
      expect( glyphBox.right, lessThanOrEqualTo( whenBox.left + 1 ) );
      expect( ( glyphBox.center.dy - whenBox.center.dy ).abs(), lessThan( 6 ) );
    } );

    testWidgets( "is hidden from the screen reader — the status is in words instead", ( tester ) async {
      final handle = tester.ensureSemantics();
      final repo   = _FakeRepo( byStatus: {
        "done": [ _ev( 1, "done", actor: "krishna 420f5ec9" ) ],
      } );
      await pumpPhone( tester, _host( repo ) );

      // The row announces its status as a WORD…
      // The row announces its status as a WORD. Not anchored at the end: the row's
      // label legitimately continues with the cell texts underneath it.
      expect(
        find.bySemanticsLabel( RegExp( r"^Done, \d+h ago, by krishna" ) ),
        findsOneWidget,
      );
      // …and no node anywhere speaks the emoji — not the row glyph, and not the
      // filter pills either, which is a separate exclusion in the pill label.
      expect( find.bySemanticsLabel( RegExp( "✅" ) ), findsNothing );
      expect( find.bySemanticsLabel( RegExp( "🚫" ) ), findsNothing );
      handle.dispose();
    } );

    testWidgets( "the row keeps FOUR cells whichever filters are lit", ( tester ) async {
      final repo = _FakeRepo( byStatus: {
        "done"     : [ _ev( 1, "done" ) ],
        "wont_fix" : [ _ev( 2, "wont_fix" ) ],
      } );
      await pumpPhone( tester, _host( repo ) );

      Rect whenBoxOf( int id ) =>
          tester.getRect( find.byKey( Key( "${TestKeys.finishedRowWhenPrefix}$id" ) ) );
      final before = whenBoxOf( 1 );

      // Light a second filter — the grid must not change shape.
      await tester.tap( find.byKey( const Key( "${TestKeys.finishedStatusPillPrefix}wont_fix" ) ) );
      await tester.pumpAndSettle();

      expect( find.byKey( const Key( "${TestKeys.finishedRowWhenPrefix}2" ) ), findsOneWidget );
      expect( whenBoxOf( 1 ).width, before.width );
    } );
  } );

  group( "the filter pills", () {
    testWidgets( "only done is lit by default", ( tester ) async {
      final repo = _FakeRepo( byStatus: {
        "done"     : [ _ev( 1, "done" ) ],
        "dropped"  : [ _ev( 2, "dropped" ) ],
        "wont_fix" : [ _ev( 3, "wont_fix" ) ],
      } );
      await pumpPhone( tester, _host( repo ) );

      expect( find.byKey( const Key( "${TestKeys.finishedRowTitlePrefix}1" ) ), findsOneWidget );
      expect( find.byKey( const Key( "${TestKeys.finishedRowTitlePrefix}2" ) ), findsNothing );
      expect( find.byKey( const Key( "${TestKeys.finishedRowTitlePrefix}3" ) ), findsNothing );
    } );

    testWidgets( "an UNLIT pill still shows its own count", ( tester ) async {
      // Otherwise the only way to discover that rows were closed as won't-fix is
      // to light the pill — the discovery this pane exists to make unnecessary.
      final repo = _FakeRepo( byStatus: {
        "done"     : [ _ev( 1, "done" ) ],
        "wont_fix" : [ _ev( 2, "wont_fix" ), _ev( 3, "wont_fix" ) ],
        "dropped"  : const [],
      } );
      await pumpPhone( tester, _host( repo ) );

      expect( find.textContaining( "Won't-fix (2)" ), findsOneWidget );
    } );

    testWidgets( "a pill whose fetch FAILED shows the em dash, not zero", ( tester ) async {
      // "We do not know" must not render as a confident "none".
      final repo = _FakeRepo(
        byStatus : { "done": [ _ev( 1, "done" ) ], "dropped": const [] },
        failures : { "wont_fix": "boom" },
      );
      await pumpPhone( tester, _host( repo ) );

      expect( find.textContaining( "Won't-fix ($kFinishedUnmeasured)" ), findsOneWidget );
      expect( find.byKey( const Key( TestKeys.finishedPartialBanner ) ), findsOneWidget );
    } );

    testWidgets( "toggling a pill does NOT refetch", ( tester ) async {
      final repo = _FakeRepo( byStatus: {
        "done"     : [ _ev( 1, "done" ) ],
        "wont_fix" : [ _ev( 2, "wont_fix" ) ],
      } );
      await pumpPhone( tester, _host( repo ) );
      final callsAfterLoad = repo.calls;

      await tester.tap( find.byKey( const Key( "${TestKeys.finishedStatusPillPrefix}wont_fix" ) ) );
      await tester.pumpAndSettle();

      expect( repo.calls, callsAfterLoad );
    } );
  } );

  group( "window and refresh", () {
    testWidgets( "the window control is carried, defaulting to 1 day", ( tester ) async {
      final repo = _FakeRepo( byStatus: { "done": [ _ev( 1, "done" ) ] } );
      await pumpPhone( tester, _host( repo ) );

      expect( find.byKey( const Key( TestKeys.finishedWindowSlider ) ), findsOneWidget );
      expect( find.text( "1 day" ), findsWidgets );
    } );

    testWidgets( "a refresh BUTTON exists, because pull-to-refresh is a gesture a screen reader cannot perform", ( tester ) async {
      final repo = _FakeRepo( byStatus: { "done": [ _ev( 1, "done" ) ] } );
      await pumpPhone( tester, _host( repo ) );
      final callsAfterLoad = repo.calls;

      await tester.tap( find.byKey( const Key( TestKeys.finishedRefreshButton ) ) );
      await tester.pumpAndSettle();

      expect( repo.calls, callsAfterLoad + 1 );
    } );

    testWidgets( "a 128-character fleet title does not overflow at 360 dp", ( tester ) async {
      // The §7.2 finding, exercised rather than argued. Real fleet titles run past a
      // hundred characters and share a "[LUPIN-MOBILE] Phase N:" prefix; at the
      // harness's 800 dp default this passes whatever the layout does.
      final repo = _FakeRepo( byStatus: {
        "done": [ _ev(
          1, "done",
          title : "[LUPIN-MOBILE] Phase 2: Finished Tasks — own four-column table, "
                  "three terminal statuses, negative row assertion",
          reason: "landed on branch seat-rachel-finished-tasks with the whole pyramid green",
        ) ],
      } );
      await pumpPhone( tester, _host( repo ) );

      expect( tester.takeException(), isNull, reason: "a long title overflowed at 360 dp" );

      // And the title still gets the room: more than half the width, not the ~90 dp
      // that four-across would have left it.
      final titleBox = tester.getRect(
        find.byKey( const Key( "${TestKeys.finishedRowTitlePrefix}1" ) ),
      );
      expect( titleBox.width, greaterThan( 180 ) );
    } );

    testWidgets( "an empty window renders an empty state, not a blank screen", ( tester ) async {
      final repo = _FakeRepo( byStatus: { "done": const [], "dropped": const [], "wont_fix": const [] } );
      await pumpPhone( tester, _host( repo ) );

      expect( find.byKey( const Key( TestKeys.finishedEmptyState ) ), findsOneWidget );
    } );
  } );

  // ────────────────────────────────────────────────────────────────────────────
  group( "the shared row", () {
    /// 🔴 THE POINT OF THIS ITEM, AND IT IS ASSERTED NEGATIVELY ON PURPOSE.
    ///
    /// This pane must NOT render the shared `TaskRow`. Its rows are `task_events`
    /// and carry no `priority`, no `blocked`, no `accountable` and no `actions`, so
    /// the shared row would render ten fields this data does not have.
    ///
    /// The history is why the guard exists. The pre-cascade plan named Finished
    /// Tasks as the third pane sharing the row; Chloé found that wrong; I disagreed,
    /// measured `finishedTasksTable.ts` myself and retracted — and then found the
    /// gap had MOVED rather than closed. With the panes now documented as
    /// deliberately different and nothing holding them apart, §7.1's "Do not give
    /// this pane a row of its own" — a sentence about the HOLDING AREA, sitting
    /// under a heading called "The shared row" — reads to a cold reader as a mandate
    /// to unify. They unify, this pane gains ten empty fields, and every other test
    /// stays green.
    ///
    /// ⚠️ A NEGATIVE ASSERTION IS THE ONLY KIND THAT SURVIVES A WELL-MEANING
    /// REFACTOR, because it fails ON the refactor rather than after it.
    ///
    /// ⚠️ THIS WAS A NAME PREDICATE UNTIL PHASE 0 LANDED. `TaskRow` did not exist, so
    /// the guard compared `runtimeType.toString()` against the string "TaskRow" and
    /// needed a companion test plus a local stand-in class to prove it matched
    /// anything at all. Phase 0 is in this tree now, so the real type is importable and
    /// the assertion is TYPED — which cannot go vacuous under a rename, because a
    /// rename that broke it would not compile. The companion and the stand-in went with
    /// the predicate.
    testWidgets( "this pane does NOT render the shared TaskRow", ( tester ) async {
      final repo = _FakeRepo( byStatus: {
        "done"     : [ _ev( 1, "done" ), _ev( 2, "done" ) ],
        "dropped"  : [ _ev( 3, "dropped" ) ],
        "wont_fix" : [ _ev( 4, "wont_fix" ) ],
      } );
      await pumpPhone( tester, _host( repo ) );

      expect( find.byType( TaskRow ), findsNothing );

      // And it DOES render its own row, so the assertion above cannot be satisfied
      // by a pane that renders nothing at all.
      expect( find.byType( FinishedTaskRow ), findsWidgets );
    } );

  } );
}
