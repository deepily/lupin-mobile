import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/task_list/data/task_list_repository.dart';

import '../_helpers/stub_dio.dart';
import '../../_helpers/fixture_loader.dart';

void main() {
  late StubAdapter adapter;
  late TaskListRepository repo;

  setUp(() {
    adapter = StubAdapter();
    repo    = TaskListRepository(makeDio(adapter));
  });

  group("the query — §12's reversal, kept", () {
    // 🔴 char_budget=0 is KEPT and terse=true is ADDED. The wrong version looks MORE
    // careful, which is why this is pinned rather than left to a comment.
    //
    // Dropping char_budget=0 does not trim gently — it applies RESPONSE_CHAR_BUDGET =
    // 100_000 against ~4,242-char rows, admitting about 23 of 500. The router's own note:
    // "the default budget cut it from 1100 available rows to 30".
    //
    // ⇒ terse=true is the lever: SMALLER ROWS, NOT FEWER ROWS.
    test("keeps char_budget=0 AND adds terse=true", () {
      expect(TaskListRepository.path, contains("char_budget=0"));
      expect(TaskListRepository.path, contains("terse=true"));
    });

    test("asks for the whole board, parked rows included", () {
      expect(TaskListRepository.path, contains("limit=500"));
      expect(TaskListRepository.path, contains("unscoped_audit=true"));
      // parked is OPEN work a human ruled not-now — hiding it makes the pane quietly
      // incomplete.
      expect(TaskListRepository.path, contains("hide_parked=false"));
    });
  });

  group("the envelope is READ, not discarded", () {
    // §10 tier 3. truncated / total / has_more exist so a short page cannot pass for a
    // complete one — a pane that renders `tasks` and drops these is silent truncation
    // with extra steps.
    test("parses truncated, total and has_more from a real captured page", () async {
      adapter.handlers["GET ${TaskListRepository.path}"] =
          (_) => jsonBodyFromFixture("tasks/task_list_terse.json");

      final page = await repo.fetch();

      final raw = loadFixture("tasks/task_list_terse.json");
      expect(page.total,    raw["total"]);
      expect(page.hasMore,  raw["has_more"]);
      expect(page.truncated, raw["truncated"]);
      expect(page.rows.length, (raw["tasks"] as List).length);
    });

    test("a page smaller than the matching set is INCOMPLETE", () async {
      adapter.handlers["GET ${TaskListRepository.path}"] =
          (_) => jsonBodyFromFixture("tasks/task_list_terse.json");

      final page = await repo.fetch();
      expect(page.isIncomplete, isTrue,
          reason: "captured live against a board larger than the page — the banner must "
                  "fire on this, not on a value someone chose");
    });

    test("a complete page is not flagged incomplete", () {
      final page = TaskListPage.fromJson(const {
        "tasks": [], "truncated": false, "total": 0, "has_more": false, "warnings": [],
      });
      expect(page.isIncomplete, isFalse);
    });

    // An empty not_approved result is NOT an error — §10 names this explicitly.
    test("an empty result is an empty page, not a throw", () async {
      adapter.handlers["GET ${TaskListRepository.path}"] =
          (_) => jsonBodyFromFixture("tasks/holding_area_empty.json");

      final page = await repo.fetch();
      expect(page.rows, isEmpty);
      expect(page.total, 0);
    });

    test("a missing envelope degrades rather than throwing", () {
      final page = TaskListPage.fromJson(const {});
      expect(page.rows, isEmpty);
      expect(page.total, 0);
      expect(page.truncated, isFalse);
    });
  });

  group("cancellation is not an error", () {
    // A cancelled poll is the lifecycle rule working. Translating it into a fetch failure
    // would paint "request failed" every time the user leaves the pane, and train them to
    // ignore the error line that matters.
    test("a cancellation rethrows as a cancellation, not a fetch exception", () async {
      final token = CancelToken();
      adapter.handlers["GET ${TaskListRepository.path}"] = (_) {
        token.cancel("pane hidden");
        throw DioException.requestCancelled(
          requestOptions: RequestOptions(path: TaskListRepository.path),
          reason: "pane hidden",
        );
      };

      await expectLater(
        repo.fetch(cancelToken: token),
        throwsA(isA<DioException>()
            .having((e) => CancelToken.isCancel(e), "isCancel", isTrue)),
      );
    });
  });
}
