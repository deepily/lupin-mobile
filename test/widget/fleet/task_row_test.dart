import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/fleet/data/task_row_model.dart';
import 'package:lupin_mobile/features/fleet/data/task_row_schema.dart';
import 'package:lupin_mobile/features/fleet/data/task_write_repository.dart';
import 'package:lupin_mobile/features/fleet/presentation/task_row.dart';

const _model = TaskRowModel(
  id: "abc123", title: "A very long row title that would truncate on a phone",
  status: "queued", itemClass: "bug", priority: "P1",
  accountableManager: "tiffany", createdBy: "Sam", project: "lupin-mobile",
  detail: "the detail",
);

Future<void> _pump(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

/// The ordered cell keys a rendered row actually produced.
///
/// 🔴 THIS IS THE CELL-IDENTITY HARNESS, AND IT IS THE PHASE 0 DELIVERABLE THAT THE
/// PANE TESTS WILL CALL. §10 test 1 asks for one fixed row model rendered through Task
/// List and Holding Area, asserting they produce the IDENTICAL ordered key list. Those
/// two panes are Phases 3 and 4, so what Phase 0 owes is the mechanism plus this reader
/// — the two-pane comparison lands with the second pane.
///
/// `find.byType( TaskRow )` is the wrong assertion and passes while the panes drift four
/// ways: a `pane:` parameter branching inside, different field subsets, a bespoke row
/// for a special case, or a wrapper. Reading the keys catches all four, because it
/// compares what was RENDERED rather than which class rendered it.
List<String> renderedCellKeys(WidgetTester tester) {
  return tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => (t.key as ValueKey<String>?)?.value)
      .whereType<String>()
      .where((k) => k.startsWith(TestKeys.taskRowCellPrefix))
      .map((k) => k.substring(TestKeys.taskRowCellPrefix.length))
      .toList();
}

void main() {
  group("cell identity", () {
    testWidgets("an expanded row renders the schema's cells in schema order",
        (tester) async {
      await _pump(tester, const TaskRow(model: _model));
      await tester.tap(find.byKey(const Key(TestKeys.taskRowDisclosure)));
      await tester.pumpAndSettle();

      final rendered = renderedCellKeys(tester);
      // `actions` is controls, not a Text cell — everything else is present and ordered.
      expect(rendered, RowSchema.keys.where((k) => k != "actions").toList());
    });

    // Two independently-constructed rows, each with its own State — a shared State would
    // make this pass for the wrong reason.
    testWidgets("two rows built from one model are cell-for-cell identical",
        (tester) async {
      await _pump(tester, TaskRow(key: UniqueKey(), model: _model));
      await tester.tap(find.byKey(const Key(TestKeys.taskRowDisclosure)));
      await tester.pumpAndSettle();
      final first = renderedCellKeys(tester);

      await _pump(tester, TaskRow(key: UniqueKey(), model: _model));
      await tester.tap(find.byKey(const Key(TestKeys.taskRowDisclosure)));
      await tester.pumpAndSettle();

      expect(renderedCellKeys(tester), first);
      expect(first, isNotEmpty, reason: "an empty list would match itself");
    });

    // The constructor is the mechanism. If a `pane:` parameter is ever added, this test
    // does not catch it — but adding one requires editing the constructor, which is
    // visible in review. Adding an enum case to a branch inside `build` is not.
    testWidgets("line 1 carries the title, not four more fields", (tester) async {
      await _pump(tester, const TaskRow(model: _model));

      // Collapsed: line 1 + line 2 only, and the title leads.
      final rendered = renderedCellKeys(tester);
      expect(rendered.first, "title");
      expect(rendered, isNot(contains("detail")));
    });
  });

  group("disclosure", () {
    // 🔴 COLLAPSED CONTROLS MUST BE ABSENT FROM THE SEMANTICS TREE, NOT MERELY INVISIBLE.
    // Under ruling 2 the disclosed row is the pane's PRIMARY VERB SURFACE. Hidden with
    // Opacity(0), a zero-height SizedBox, or Visibility(…, maintainSemantics: true),
    // TalkBack reads and can ACTIVATE every row's write verbs while the row looks
    // collapsed.
    //
    // ⚠️ The two idioms a Flutter developer reaches for first (Visibility, Offstage) both
    // drop the child by default, so the likeliest implementation is ACCIDENTALLY CORRECT
    // — which is exactly the condition under which something drifts unnoticed. Hence an
    // explicit assertion rather than trust in the default.
    testWidgets("no action node is reachable while collapsed", (tester) async {
      await _pump(tester, TaskRow(
        model: _model,
        verbs: [TaskVerb.approve(), TaskVerb.wontFix(reason: "no")],
      ));

      expect(find.byKey(const Key(TestKeys.taskRowControls)), findsNothing);
      expect(find.byKey(const Key("${TestKeys.taskRowVerbPrefix}approve")), findsNothing);

      final handle = tester.ensureSemantics();
      expect(
        find.bySemanticsLabel(RegExp("approve")),
        findsNothing,
        reason: "a collapsed verb that TalkBack can still activate is a mis-tap that "
                "looks impossible",
      );
      handle.dispose();
    });

    testWidgets("expanding reveals the controls", (tester) async {
      await _pump(tester, TaskRow(model: _model, verbs: [TaskVerb.approve()]));
      await tester.tap(find.byKey(const Key(TestKeys.taskRowDisclosure)));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key(TestKeys.taskRowControls)), findsOneWidget);
      expect(find.byKey(const Key("${TestKeys.taskRowVerbPrefix}approve")), findsOneWidget);
    });

    // ⚠️ `expanded:` carries STATE, not PURPOSE. Without a label TalkBack says
    // "button, collapsed" and the user never learns there are verbs behind it.
    testWidgets("the toggle carries both expanded state and an accessible name",
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, const TaskRow(model: _model));

      expect(find.bySemanticsLabel("Show row controls"), findsOneWidget);

      await tester.tap(find.byKey(const Key(TestKeys.taskRowDisclosure)));
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel("Hide row controls"), findsOneWidget);
      handle.dispose();
    });
  });

  group("destructive verbs arm, then confirm", () {
    testWidgets("a terminal verb does not fire on the first press", (tester) async {
      final fired = <String>[];
      await _pump(tester, TaskRow(
        model  : _model,
        verbs  : [TaskVerb.wontFix(reason: "no")],
        onVerb : (v) => fired.add(v.name),
      ));
      await tester.tap(find.byKey(const Key(TestKeys.taskRowDisclosure)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key("${TestKeys.taskRowVerbPrefix}wont_fix")));
      await tester.pumpAndSettle();
      expect(fired, isEmpty, reason: "terminal:true is armsTwice — done is append-only "
                                     "and a misclick cannot be undone");

      await tester.tap(find.byKey(const Key("${TestKeys.taskRowVerbPrefix}wont_fix")));
      await tester.pumpAndSettle();
      expect(fired, ["wont_fix"]);
    });

    testWidgets("a non-terminal verb fires on the first press", (tester) async {
      final fired = <String>[];
      await _pump(tester, TaskRow(
        model: _model, verbs: [TaskVerb.approve()], onVerb: (v) => fired.add(v.name),
      ));
      await tester.tap(find.byKey(const Key(TestKeys.taskRowDisclosure)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key("${TestKeys.taskRowVerbPrefix}approve")));
      await tester.pumpAndSettle();
      expect(fired, ["approve"]);
    });

    // 🔴 §10 test 4: ASSERT THE ANNOUNCEMENT, NOT THE LABEL CHANGE.
    //
    // In Flutter, changing a button's label in place is NOT announced — TalkBack focus
    // stays on the node, the text under it changes, and nothing is spoken
    // (semantics.dart:5351-5362: an update is announced only with liveRegion, "even if
    // the widget does not have accessibility focus"). A TalkBack user believes the first
    // tap missed and taps again — AND THAT IS THE TAP THAT FIRES THE TERMINAL ACTION.
    //
    // ⇒ Arm-twice without liveRegion makes a mis-tap harder for a sighted user and NO
    // harder for a TalkBack user, while being recorded as handled. That is strictly
    // worse than omitting it, because the omission would at least be visible.
    testWidgets("the armed label is a live region, so it is announced", (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, TaskRow(model: _model, verbs: [TaskVerb.wontFix(reason: "no")]));
      await tester.tap(find.byKey(const Key(TestKeys.taskRowDisclosure)));
      await tester.pumpAndSettle();

      final before = tester.getSemantics(
        find.byKey(const Key("${TestKeys.taskRowVerbPrefix}wont_fix")),
      );
      expect(before.hasFlag(SemanticsFlag.isLiveRegion), isFalse);

      await tester.tap(find.byKey(const Key("${TestKeys.taskRowVerbPrefix}wont_fix")));
      await tester.pumpAndSettle();

      final after = tester.getSemantics(
        find.byKey(const Key("${TestKeys.taskRowVerbPrefix}wont_fix")),
      );
      expect(
        after.hasFlag(SemanticsFlag.isLiveRegion),
        isTrue,
        reason: "an in-place label change is silent to TalkBack; without liveRegion the "
                "second tap fires the terminal action the user never knew was armed",
      );
      handle.dispose();
    });

    testWidgets("collapsing the row disarms it", (tester) async {
      final fired = <String>[];
      await _pump(tester, TaskRow(
        model  : _model,
        verbs  : [TaskVerb.wontFix(reason: "no")],
        onVerb : (v) => fired.add(v.name),
      ));
      await tester.tap(find.byKey(const Key(TestKeys.taskRowDisclosure)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key("${TestKeys.taskRowVerbPrefix}wont_fix")));
      await tester.pumpAndSettle();

      // Collapse and reopen — the arm must not survive.
      await tester.tap(find.byKey(const Key(TestKeys.taskRowDisclosure)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key(TestKeys.taskRowDisclosure)));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key("${TestKeys.taskRowVerbPrefix}wont_fix")));
      await tester.pumpAndSettle();
      expect(fired, isEmpty, reason: "a stale arm is a terminal action one tap away");
    });
  });
}
