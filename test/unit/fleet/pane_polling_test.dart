import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/fleet/domain/pane_polling_mixin.dart';

/// A minimal pane bloc, standing in for the five real ones.
class _FakePaneBloc extends Bloc<int, int> with PanePollingMixin<int, int> {
  final StreamController<AppLifecycleState> lifecycle;

  int  polls = 0;
  final List<CancelToken> tokens = [];

  /// Completes only when the test says so, so a poll can be left deliberately in flight.
  Completer<void>? hold;

  _FakePaneBloc(this.lifecycle) : super(0);

  @override
  Stream<AppLifecycleState> get lifecycleStream => lifecycle.stream;

  @override
  Future<void> pollOnce(CancelToken token) async {
    polls++;
    tokens.add(token);
    if (hold != null) await hold!.future;
  }
}

void main() {
  late StreamController<AppLifecycleState> lifecycle;

  setUp(() => lifecycle = StreamController<AppLifecycleState>.broadcast());
  tearDown(() => lifecycle.close());

  // 🔴 THE GUARD ON §6.3, AND THE REASON PHASE 0 NEEDED A NAMED MECHANISM AT ALL.
  //
  // app.dart:248-278 registers seven BlocProviders at the APP ROOT, each a
  // ServiceLocator singleton, so a pane's bloc outlives its route. Five panes following
  // that pattern means five timers running whichever destination is showing — and the
  // pre-cascade test ("polling stops when backgrounded and refreshes once on resume")
  // PASSES WITH ALL FIVE RUNNING. This is the assertion that does not.
  test("with pane A on screen, pane B issues zero requests", () async {
    final a = _FakePaneBloc(lifecycle)..startPolling();
    final b = _FakePaneBloc(lifecycle)..startPolling();

    a.onPaneVisible();
    await Future<void>.delayed(Duration.zero);

    expect(a.polls, 1, reason: "the visible pane refreshes when it appears");
    expect(b.polls, 0, reason: "a pane that is not on screen must not poll at all");
    expect(a.isPolling, isTrue);
    expect(b.isPolling, isFalse);

    await a.close();
    await b.close();
  });

  test("hiding a pane stops it, showing its sibling starts that one", () async {
    final a = _FakePaneBloc(lifecycle)..startPolling();
    final b = _FakePaneBloc(lifecycle)..startPolling();

    a.onPaneVisible();
    await Future<void>.delayed(Duration.zero);
    a.onPaneHidden();
    b.onPaneVisible();
    await Future<void>.delayed(Duration.zero);

    expect(a.isPolling, isFalse);
    expect(b.isPolling, isTrue);
    expect(a.polls, 1, reason: "a hidden pane issues nothing further");

    await a.close();
    await b.close();
  });

  group("lifecycle: five states, not one", () {
    // app_lifecycle_service.dart:103-116 already switches on all five and the
    // pre-cascade plan named only `paused`. On Android `hidden` PRECEDES `paused`, and
    // `inactive` fires for a shade pull or an incoming-call banner. Stopping only on
    // `paused` stops too late.
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.detached,
    ]) {
      test("$state stops the timer", () async {
        final bloc = _FakePaneBloc(lifecycle)..startPolling();
        bloc.onPaneVisible();
        await Future<void>.delayed(Duration.zero);
        expect(bloc.isPolling, isTrue);

        lifecycle.add(state);
        await Future<void>.delayed(Duration.zero);

        expect(bloc.isPolling, isFalse, reason: "$state is not a foreground state");
        await bloc.close();
      });
    }

    test("resuming refreshes exactly once", () async {
      final bloc = _FakePaneBloc(lifecycle)..startPolling();
      bloc.onPaneVisible();
      await Future<void>.delayed(Duration.zero);
      final afterAppear = bloc.polls;

      lifecycle.add(AppLifecycleState.paused);
      await Future<void>.delayed(Duration.zero);
      lifecycle.add(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);

      expect(bloc.polls, afterAppear + 1);
      expect(bloc.isPolling, isTrue);
      await bloc.close();
    });

    test("a hidden pane does NOT start polling when the app resumes", () async {
      final bloc = _FakePaneBloc(lifecycle)..startPolling();

      lifecycle.add(AppLifecycleState.paused);
      lifecycle.add(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);

      expect(bloc.polls, 0);
      expect(bloc.isPolling, isFalse);
      await bloc.close();
    });
  });

  group("cancel the request, not just the timer", () {
    // 🔴 Cancelling a Timer.periodic does NOT cancel an outstanding HTTP request. That
    // response still arrives, still parses, and still wakes a backgrounded app — which
    // is exactly the wake-up the rule exists to prevent, with a multi-hundred-KB body
    // behind it.
    test("backgrounding cancels the in-flight token", () async {
      final bloc = _FakePaneBloc(lifecycle)..hold = Completer<void>();
      bloc.startPolling();
      bloc.onPaneVisible();
      await Future<void>.delayed(Duration.zero);

      expect(bloc.tokens.single.isCancelled, isFalse);

      lifecycle.add(AppLifecycleState.paused);
      await Future<void>.delayed(Duration.zero);

      expect(bloc.tokens.single.isCancelled, isTrue,
          reason: "stopping the timer alone leaves the response to land in a "
                  "backgrounded app");

      bloc.hold!.complete();
      await bloc.close();
    });

    test("hiding the pane cancels the in-flight token", () async {
      final bloc = _FakePaneBloc(lifecycle)..hold = Completer<void>();
      bloc.startPolling();
      bloc.onPaneVisible();
      await Future<void>.delayed(Duration.zero);

      bloc.onPaneHidden();
      await Future<void>.delayed(Duration.zero);

      expect(bloc.tokens.single.isCancelled, isTrue);
      bloc.hold!.complete();
      await bloc.close();
    });

    test("a poll landing on a slow predecessor does not queue a second request", () async {
      final bloc = _FakePaneBloc(lifecycle)..hold = Completer<void>();
      bloc.startPolling();
      bloc.onPaneVisible();
      await Future<void>.delayed(Duration.zero);
      expect(bloc.polls, 1);

      // A second visible signal while the first is still in flight.
      bloc.onPaneHidden();
      bloc.hold = null;
      bloc.onPaneVisible();
      await Future<void>.delayed(Duration.zero);

      expect(bloc.polls, 2, reason: "one request at a time, not a queue behind a "
                                    "connection that is already struggling");
      await bloc.close();
    });
  });

  test("startPolling is idempotent — a rebuild must not start a second timer", () async {
    final bloc = _FakePaneBloc(lifecycle)
      ..startPolling()
      ..startPolling()
      ..startPolling();
    bloc.onPaneVisible();
    await Future<void>.delayed(Duration.zero);

    expect(bloc.polls, 1);
    await bloc.close();
  });

  test("close stops the timer and cancels the request", () async {
    final bloc = _FakePaneBloc(lifecycle)..hold = Completer<void>();
    bloc.startPolling();
    bloc.onPaneVisible();
    await Future<void>.delayed(Duration.zero);

    await bloc.close();

    expect(bloc.isPolling, isFalse);
    expect(bloc.tokens.single.isCancelled, isTrue);
    bloc.hold!.complete();
  });
}
