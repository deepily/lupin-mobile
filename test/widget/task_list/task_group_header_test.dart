import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/task_list/presentation/task_group_header.dart';

Future<void> _pump(WidgetTester tester, Widget child) =>
    tester.pumpWidget(MaterialApp(home: Scaffold(body: child)));

void main() {
  group("TaskGroupHeader — the pane's SECOND disclosure surface", () {
    // 🔴 THE ROW'S ELLIPSIS HIDES VERBS; THIS HIDES ROWS. A screen-reader user who cannot
    // tell a collapsed group from an empty one is looking at a task list with work
    // silently missing, and nothing announces it. The COUNT IN THE LABEL is the part that
    // fixes that — "collapsed" alone does not say whether work is hidden or absent.
    testWidgets("announces owner AND count, expanded", (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, TaskGroupHeader(
        ownerLabel: "sam", count: 7, expanded: true, onToggle: () {},
      ));

      expect(find.bySemanticsLabel("sam, 7 tasks"), findsOneWidget);
      handle.dispose();
    });

    testWidgets("announces collapsed state, with the count still present",
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, TaskGroupHeader(
        ownerLabel: "sam", count: 7, expanded: false, onToggle: () {},
      ));

      final node = tester.getSemantics(
        find.byKey(const Key("${TestKeys.taskListGroupHeaderPrefix}sam")),
      );
      expect(node.hasFlag(SemanticsFlag.hasExpandedState), isTrue);
      expect(node.hasFlag(SemanticsFlag.isExpanded), isFalse);
      expect(node.label, contains("7 tasks"),
          reason: "a collapsed group and an empty one must not announce identically");
      handle.dispose();
    });

    testWidgets("is a button to a screen reader, not just tappable glass",
        (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, TaskGroupHeader(
        ownerLabel: "sam", count: 1, expanded: true, onToggle: () {},
      ));

      final node = tester.getSemantics(
        find.byKey(const Key("${TestKeys.taskListGroupHeaderPrefix}sam")),
      );
      expect(node.hasFlag(SemanticsFlag.isButton), isTrue);
      handle.dispose();
    });

    // ⚠️ The acceptance line here used to read "group header keyboard-operable", which a
    // PHONE CAN NEITHER SATISFY NOR FAIL. This is the phone-meaningful replacement and it
    // is testable, which was the whole point of the rewrite.
    testWidgets("singular vs plural reads correctly", (tester) async {
      expect(TaskGroupHeader.semanticLabel("sam", 1), "sam, 1 task");
      expect(TaskGroupHeader.semanticLabel("sam", 2), "sam, 2 tasks");
      expect(TaskGroupHeader.semanticLabel("sam", 0), "sam, 0 tasks");
    });

    testWidgets("a two-word persona keys and labels intact", (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, TaskGroupHeader(
        ownerLabel: "Mr. Radio", count: 3, expanded: true, onToggle: () {},
      ));

      expect(find.bySemanticsLabel("Mr. Radio, 3 tasks"), findsOneWidget);
      expect(
        find.byKey(const Key("${TestKeys.taskListGroupHeaderPrefix}Mr. Radio")),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets("tapping toggles", (tester) async {
      var taps = 0;
      await _pump(tester, TaskGroupHeader(
        ownerLabel: "sam", count: 1, expanded: true, onToggle: () => taps++,
      ));

      await tester.tap(find.byKey(const Key("${TestKeys.taskListGroupHeaderPrefix}sam")));
      expect(taps, 1);
    });

    // 🔴 48 dp is Android's minimum touch target. Below it, a collapse aimed at one group
    // lands on its neighbour — and a group header hides ROWS, so a mis-tap hides work.
    testWidgets("meets the 48 dp minimum touch target", (tester) async {
      await _pump(tester, TaskGroupHeader(
        ownerLabel: "sam", count: 1, expanded: true, onToggle: () {},
      ));

      final size = tester.getSize(
        find.byKey(const Key("${TestKeys.taskListGroupHeaderPrefix}sam")),
      );
      expect(size.height, greaterThanOrEqualTo(48.0));
    });
  });
}
