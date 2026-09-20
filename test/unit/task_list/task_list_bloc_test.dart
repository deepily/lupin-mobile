import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/fleet/data/task_write_repository.dart';
import 'package:lupin_mobile/features/task_list/data/task_list_repository.dart';
import 'package:lupin_mobile/features/task_list/domain/task_list_bloc.dart';

import '../_helpers/stub_dio.dart';

void main() {
  late StubAdapter adapter;
  late TaskListBloc bloc;

  setUp(() {
    adapter = StubAdapter();
    final dio = makeDio(adapter);
    bloc = TaskListBloc(
      TaskListRepository(dio),
      TaskWriteRepository(dio, actorEmail: () => "rick@example.com"),
    );
  });

  tearDown(() async => bloc.close());

  group("a cancellation is NOT a server-down", () {
    // 🔴 CHLOÉ'S DEFECT, GENERALISED. A poll cancelled because the pane went away is the
    // LIFECYCLE RULE WORKING. Painting it as an error tells the operator the arbiter is
    // down while the server is perfectly healthy — and it fires on the most ordinary
    // action there is, leaving the pane. Two costs: the operator chases a phantom
    // outage, and they learn to ignore the error line that will one day be real.
    test("a cancelled poll leaves no error on the state", () async {
      adapter.handlers["GET ${TaskListRepository.path}"] = (_) {
        throw DioException.requestCancelled(
          requestOptions: RequestOptions(path: TaskListRepository.path),
          reason: "pane hidden",
        );
      };

      bloc.add(const TaskListRefreshRequested());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.error, isNull,
          reason: "leaving a pane must not look like the server falling over");
      expect(bloc.state.loading, isFalse, reason: "and it must not spin forever either");
    });

    test("a REAL failure does set an error", () async {
      adapter.handlers["GET ${TaskListRepository.path}"] =
          (_) => jsonBody({"detail": "boom"}, status: 500);

      bloc.add(const TaskListRefreshRequested());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.error, isNotNull,
          reason: "swallowing cancellations must not swallow genuine failures too");
    });
  });

  group("the poll interval reads the connection", () {
    // 60 s is the WEB's number and a phone is not a browser tab. ~107 KB per terse poll
    // is ~6.4 MB per foreground hour on one pane — fine on Wi-Fi, rude on a metered
    // connection.
    test("defaults to 60 s off Wi-Fi-or-unknown", () {
      expect(bloc.pollInterval, const Duration(seconds: 60));
    });
  });

  group("group collapse is the operator's state", () {
    test("toggling collapses and re-expands", () async {
      bloc.add(const TaskListGroupToggled("sam"));
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.collapsed, contains("sam"));

      bloc.add(const TaskListGroupToggled("sam"));
      await Future<void>.delayed(Duration.zero);
      expect(bloc.state.collapsed, isNot(contains("sam")));
    });

    // A poll that silently re-expanded every group would undo the operator's work every
    // sixty seconds — collapse belongs to them, not to the refresh.
    test("a refresh does not re-expand collapsed groups", () async {
      adapter.handlers["GET ${TaskListRepository.path}"] =
          (_) => jsonBody({"tasks": [], "total": 0, "has_more": false,
                           "truncated": false, "warnings": []});

      bloc.add(const TaskListGroupToggled("sam"));
      await Future<void>.delayed(Duration.zero);
      bloc.add(const TaskListRefreshRequested());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.collapsed, contains("sam"));
    });
  });

  group("the incomplete banner is driven by the envelope", () {
    test("has_more sets incomplete", () async {
      adapter.handlers["GET ${TaskListRepository.path}"] =
          (_) => jsonBodyFromFixtureLike(hasMore: true, total: 16);

      bloc.add(const TaskListRefreshRequested());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.incomplete, isTrue);
      expect(bloc.state.total, 16);
    });

    test("a complete page does not raise it", () async {
      adapter.handlers["GET ${TaskListRepository.path}"] =
          (_) => jsonBodyFromFixtureLike(hasMore: false, total: 0);

      bloc.add(const TaskListRefreshRequested());
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(bloc.state.incomplete, isFalse);
    });
  });

  _writeDoorTests(() => adapter, () => bloc);
}

void _writeDoorTests(
  StubAdapter Function() adapterOf,
  TaskListBloc Function() blocOf,
) {
  group("both write doors, wired through the bloc", () {
    // §4.2 — the door is chosen by WHAT A CONTROL CHANGES, never by which pane it is in.
    test("a status verb goes through the TRANSITION door", () async {
      final seen = <String>[];
      adapterOf().handlers["POST /api/tasks/t1/transition"] = (opts) {
        seen.add((opts.data as Map)["to_status"] as String);
        return jsonBody({"status": "ok"});
      };
      adapterOf().handlers["GET ${TaskListRepository.path}"] =
          (_) => jsonBodyFromFixtureLike(hasMore: false, total: 0);

      blocOf().add(TaskListVerbPressed(taskId: "t1", verb: TaskVerb.approve()));
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(seen, ["queued"], reason: "approve is a STATUS change, not a field edit");
    });

    test("a priority change goes through the FIELD door", () async {
      final seen = <Map>[];
      adapterOf().handlers["PATCH /api/tasks/t1"] = (opts) {
        seen.add(opts.data as Map);
        return jsonBody({"status": "ok"});
      };
      adapterOf().handlers["GET ${TaskListRepository.path}"] =
          (_) => jsonBodyFromFixtureLike(hasMore: false, total: 0);

      blocOf().add(const TaskListFieldChanged(taskId: "t1", priority: "P0"));
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(seen.single["priority"], "P0");
      expect(seen.single.containsKey("status"), isFalse);
    });

    // 🔴 THE 202 IS NOT A FAILURE AND NOT A SUCCESS. The request succeeded and the change
    // did not happen — so the row goes BACK and the operator is told it is pending review.
    // Retrying would only file a second ticket.
    test("a 202 rolls the row back and says AWAITING, not failed", () async {
      adapterOf().handlers["GET ${TaskListRepository.path}"] = (_) => jsonBody({
        "tasks": [
          {"id": "t1", "title": "a row", "status": "not_approved",
           "priority": "P1", "owner_persona": "sam"},
        ],
        "total": 1, "has_more": false, "truncated": false, "warnings": [],
      });
      adapterOf().handlers["POST /api/tasks/t1/transition"] = (_) => jsonBody(
        {"status": "awaiting_human_approval", "ticket_id": "tk-9"}, status: 202,
      );

      blocOf().add(const TaskListRefreshRequested());
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(blocOf().state.model!.groups.single.tasks.length, 1);

      blocOf().add(TaskListVerbPressed(taskId: "t1", verb: TaskVerb.approve()));
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(blocOf().state.model!.groups.single.tasks.length, 1,
          reason: "the row must come BACK — a 202 did not approve it");
      expect(blocOf().state.error, contains("awaiting approval"));
      expect(blocOf().state.error, contains("tk-9"));
    });

    test("a failed write rolls the row back with the error", () async {
      adapterOf().handlers["GET ${TaskListRepository.path}"] = (_) => jsonBody({
        "tasks": [
          {"id": "t1", "title": "a row", "status": "not_approved",
           "priority": "P1", "owner_persona": "sam"},
        ],
        "total": 1, "has_more": false, "truncated": false, "warnings": [],
      });
      adapterOf().handlers["POST /api/tasks/t1/transition"] =
          (_) => jsonBody({"detail": "nope"}, status: 500);

      blocOf().add(const TaskListRefreshRequested());
      await Future<void>.delayed(const Duration(milliseconds: 60));
      blocOf().add(TaskListVerbPressed(taskId: "t1", verb: TaskVerb.approve()));
      await Future<void>.delayed(const Duration(milliseconds: 60));

      expect(blocOf().state.model!.groups.single.tasks.length, 1);
      expect(blocOf().state.error, isNotNull);
    });
  });
}

ResponseBody jsonBodyFromFixtureLike({required bool hasMore, required int total}) =>
    jsonBody({
      "tasks": const [], "total": total, "has_more": hasMore,
      "truncated": false, "warnings": const [],
    });
