/// The visibility contract, asserted against the FOUR REAL PANE BLOCS — row C5.13.
///
/// `test/unit/fleet/pane_polling_test.dart` proves the mixin's logic against
/// `_FakePaneBloc`, a bloc written for that file. It is the right test for the
/// mixin and it is not the test C5.13 asks for, because the thing §5 changes is
/// not the mixin in isolation — it is the mixin SPLIT IN TWO
/// (`PaneVisibilityMixin` + `PanePollingMixin`) underneath four production blocs
/// that mix it in and override parts of it.
///
/// Those four can diverge from the fake in ways the fake cannot show:
///   - `TaskListBloc` and `HoldingAreaBloc` reach `pollOnce` through an EVENT
///     (`add( …RefreshRequested )`), not a direct call, so a request is one
///     event-loop hop further away than the fake's;
///   - `FinishedTasksBloc` does the same and also owns a window/status filter;
///   - `FleetStatusBloc` calls its repository DIRECTLY inside `pollOnce`, and it
///     is the only one of the four that takes no `network` seam.
///
/// So this file asserts the contract where it is actually consumed, and it counts
/// REPOSITORY CALLS rather than `pollOnce` invocations — production's definition
/// of "this pane issued a request", and the only one that survives the indirection
/// above.
///
/// 🔴 THE LOAD-BEARING ROW IS "B", AND IT IS THE ONE THE EXTRACTION CAN QUIETLY
/// BREAK. `startPolling()` SUBSCRIBES AND DOES NOT POLL — the work begins at
/// `onPaneVisible()`. §5 C-6 i pins the matching invariant: after the split,
/// `isPolling` stays `_timer != null` and is NOT redefined as the visibility flag.
/// Redefine it and row B flips to true while nothing is polling; every other row
/// here still passes. That is why B asserts the count AND the flag.
///
/// Written and run GREEN on the pre-extraction sha `d0311a8`, so it is a
/// characterization test: it records today's behaviour so the extraction has
/// something that can disagree with it. A re-run after the extraction that is
/// still green is evidence; a re-run that was never red on a broken build is not,
/// which is why each row carries its own reason string.
library;

import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lupin_mobile/features/finished_tasks/data/finished_tasks_models.dart';
import 'package:lupin_mobile/features/finished_tasks/data/finished_tasks_repository.dart';
import 'package:lupin_mobile/features/finished_tasks/domain/finished_tasks_bloc.dart';
import 'package:lupin_mobile/features/fleet/data/task_row_model.dart';
import 'package:lupin_mobile/features/fleet/data/task_write_repository.dart';
import 'package:lupin_mobile/features/fleet_status/data/fleet_models.dart';
import 'package:lupin_mobile/features/fleet_status/data/fleet_repository.dart';
import 'package:lupin_mobile/features/fleet_status/domain/fleet_status_bloc.dart';
import 'package:lupin_mobile/features/holding_area/data/holding_area_repository.dart';
import 'package:lupin_mobile/features/holding_area/domain/holding_area_bloc.dart';
import 'package:lupin_mobile/features/task_list/data/new_ticket.dart';
import 'package:lupin_mobile/features/task_list/data/task_list_repository.dart';
import 'package:lupin_mobile/features/task_list/domain/task_list_bloc.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// The probe — what every pane must answer, however it is built
// ═══════════════════════════════════════════════════════════════════════════════

/// One pane under test, reduced to the five verbs the contract is written in.
///
/// The four blocs have different event types, different constructors and
/// different repositories, so they cannot share a static type beyond `Bloc`.
/// They CAN share this, which is the whole of what the contract needs.
abstract interface class _Pane {
  /// How many requests this pane's repository has been asked for.
  int get requests;

  /// The mixin's own predicate — `_timer != null` today (C-6 i).
  bool get polling;

  /// `startPolling()`: subscribe to the lifecycle stream. Does NOT poll.
  void begin();

  /// The route says the pane is on screen.
  void show();

  /// The route says the pane is off screen.
  void hide();

  Future<void> shut();
}

/// Counts reads so "this pane issued a request" is proven by the repository being
/// USED, the same discipline `fleet_status_wiring_test.dart` uses for its factory.
class _Counter {
  int calls = 0;
}

// ═══════════════════════════════════════════════════════════════════════════════
// Fake repositories — one per pane, each counting into the shared counter
// ═══════════════════════════════════════════════════════════════════════════════

const TaskListPage _emptyPage = TaskListPage(
  rows      : [],
  truncated : false,
  total     : 0,
  hasMore   : false,
  warnings  : [],
);

class _FakeTaskListRepo implements TaskListRepository {
  final _Counter counter;

  _FakeTaskListRepo( this.counter );

  @override
  Future<TaskListPage> fetch( { CancelToken? cancelToken } ) async {
    counter.calls++;
    return _emptyPage;
  }

  @override
  Future<TaskRowModel> lookup( String path ) =>
      throw UnimplementedError( "the visibility contract never looks a task up" );

  @override
  Future<NewTicketResponse> createTicket( Map<String, String> payload ) =>
      throw UnimplementedError( "the visibility contract never files a ticket" );
}

class _FakeHoldingAreaRepo implements HoldingAreaRepository {
  final _Counter counter;

  _FakeHoldingAreaRepo( this.counter );

  @override
  Future<TaskListPage> fetch( { CancelToken? cancelToken } ) async {
    counter.calls++;
    return _emptyPage;
  }
}

class _FakeFinishedTasksRepo implements FinishedTasksRepository {
  final _Counter counter;

  _FakeFinishedTasksRepo( this.counter );

  @override
  Future<List<FinishedTaskEvent>> fetchStatus( {
    required String status,
    required String since,
    int limit = kFinishedPageLimit,
    CancelToken? cancelToken,
  } ) async {
    counter.calls++;
    return const [];
  }

  @override
  Future<FinishedFetchResult> fetchWindow( {
    required int days,
    required DateTime now,
    CancelToken? cancelToken,
  } ) async {
    counter.calls++;
    return FinishedFetchResult(
      eventsByStatus : {
        for ( final status in kFinishedStatuses ) status : const <FinishedTaskEvent>[]
      },
      failures       : const {},
      windowDays     : days,
    );
  }
}

class _FakeFleetRepo implements FleetRepository {
  final _Counter counter;

  _FakeFleetRepo( this.counter );

  @override
  Future<FleetComposite> fetchState( { CancelToken? cancelToken } ) async {
    counter.calls++;
    return const FleetComposite( sessions: [], personas: {}, status: "ok" );
  }

  @override
  Future<Map<String, Object?>> fetchSizeCap( { CancelToken? cancelToken } ) async =>
      { "cap" : 9, "maximum" : 20 };

  @override
  Future<Map<String, Object?>> setSizeCap( int cap ) async =>
      { "cap" : cap, "maximum" : 20 };
}

/// A write repository that refuses every verb: the contract issues no writes, so a
/// call here is a test bug and should say so rather than quietly succeed.
class _NoWrites implements TaskWriteRepository {
  @override
  Future<void> patchFields( {
    required String id,
    String? priority,
    String? ownerPersona,
  } ) =>
      throw UnimplementedError( "the visibility contract never writes" );

  @override
  Future<void> transition( { required String id, required TaskVerb verb } ) =>
      throw UnimplementedError( "the visibility contract never writes" );
}

// ═══════════════════════════════════════════════════════════════════════════════
// The four real blocs, each with ONE override: the lifecycle test seam
// ═══════════════════════════════════════════════════════════════════════════════
//
// The seam is the STREAM, never the service: `AppLifecycleService` has a private
// constructor and cannot be faked, which is exactly why the mixin exposes an
// overridable `lifecycleStream` getter (`pane_polling_mixin.dart:86`). Nothing
// else about these blocs is changed — they are the production classes.

class _TaskListPane extends TaskListBloc implements _Pane {
  final Stream<AppLifecycleState> _lifecycle;
  final _Counter                  _counter;

  _TaskListPane( this._lifecycle, this._counter, TaskListRepository repo )
      : super( repo, _NoWrites() );

  @override
  Stream<AppLifecycleState> get lifecycleStream => _lifecycle;

  @override
  int get requests => _counter.calls;

  @override
  bool get polling => isPolling;

  @override
  void begin() => startPolling();

  @override
  void show() => onPaneVisible();

  @override
  void hide() => onPaneHidden();

  @override
  Future<void> shut() => close();
}

class _HoldingAreaPane extends HoldingAreaBloc implements _Pane {
  final Stream<AppLifecycleState> _lifecycle;
  final _Counter                  _counter;

  _HoldingAreaPane( this._lifecycle, this._counter, HoldingAreaRepository repo )
      : super( repo, _NoWrites() );

  @override
  Stream<AppLifecycleState> get lifecycleStream => _lifecycle;

  @override
  int get requests => _counter.calls;

  @override
  bool get polling => isPolling;

  @override
  void begin() => startPolling();

  @override
  void show() => onPaneVisible();

  @override
  void hide() => onPaneHidden();

  @override
  Future<void> shut() => close();
}

class _FinishedTasksPane extends FinishedTasksBloc implements _Pane {
  final Stream<AppLifecycleState> _lifecycle;
  final _Counter                  _counter;

  _FinishedTasksPane( this._lifecycle, this._counter, FinishedTasksRepository repo )
      : super( repo );

  @override
  Stream<AppLifecycleState> get lifecycleStream => _lifecycle;

  @override
  int get requests => _counter.calls;

  @override
  bool get polling => isPolling;

  @override
  void begin() => startPolling();

  @override
  void show() => onPaneVisible();

  @override
  void hide() => onPaneHidden();

  @override
  Future<void> shut() => close();
}

class _FleetStatusPane extends FleetStatusBloc implements _Pane {
  final Stream<AppLifecycleState> _lifecycle;
  final _Counter                  _counter;

  _FleetStatusPane( this._lifecycle, this._counter, FleetRepository repo )
      : super( repo );

  @override
  Stream<AppLifecycleState> get lifecycleStream => _lifecycle;

  @override
  int get requests => _counter.calls;

  @override
  bool get polling => isPolling;

  @override
  void begin() => startPolling();

  @override
  void show() => onPaneVisible();

  @override
  void hide() => onPaneHidden();

  @override
  Future<void> shut() => close();
}

// ═══════════════════════════════════════════════════════════════════════════════

typedef _PaneBuilder = _Pane Function(
  Stream<AppLifecycleState> lifecycle,
  _Counter                  counter,
);

/// Every pane bloc that mixes the visibility machine in, by the name a failure
/// should print.
final Map<String, _PaneBuilder> _panes = {
  "TaskListBloc"      : ( l, c ) => _TaskListPane( l, c, _FakeTaskListRepo( c ) ),
  "HoldingAreaBloc"   : ( l, c ) => _HoldingAreaPane( l, c, _FakeHoldingAreaRepo( c ) ),
  "FinishedTasksBloc" : ( l, c ) => _FinishedTasksPane( l, c, _FakeFinishedTasksRepo( c ) ),
  "FleetStatusBloc"   : ( l, c ) => _FleetStatusPane( l, c, _FakeFleetRepo( c ) ),
};

void main() {
  late StreamController<AppLifecycleState> lifecycle;

  setUp( () => lifecycle = StreamController<AppLifecycleState>.broadcast() );
  tearDown( () => lifecycle.close() );

  /// One event-loop settle. The two event-driven panes need the `add()` to be
  /// picked up before their repository is touched, so every assertion goes
  /// through this rather than a bare `Future.delayed`.
  Future<void> settle() => pumpEventQueue( times: 8 );

  for ( final entry in _panes.entries ) {
    final name  = entry.key;
    final build = entry.value;

    group( name, () {
      test( "A · a freshly built pane is not polling and has asked for nothing", () async {
        final counter = _Counter();
        final pane    = build( lifecycle.stream, counter );
        await settle();

        expect( pane.polling,  isFalse, reason: "$name polls before it has a route" );
        expect( pane.requests, 0,       reason: "$name hit its repository at construction" );

        await pane.shut();
      } );

      test( "B · startPolling SUBSCRIBES ONLY — it does not poll and does not flip isPolling",
          () async {
        final counter = _Counter();
        final pane    = build( lifecycle.stream, counter )..begin();
        await settle();

        expect( pane.requests, 0,
            reason: "$name issued a request from startPolling, which only subscribes — "
                    "the work begins at onPaneVisible" );
        expect( pane.polling, isFalse,
            reason: "$name reports isPolling true with no timer running. C-6 i: after the "
                    "PaneVisibilityMixin split, isPolling must stay `_timer != null` and "
                    "must NOT be redefined as the visibility flag" );

        await pane.shut();
      } );

      test( "C · onPaneVisible starts the timer and issues exactly one request", () async {
        final counter = _Counter();
        final pane    = build( lifecycle.stream, counter )..begin();
        pane.show();
        await settle();

        expect( pane.requests, 1, reason: "$name did not refresh once on becoming visible" );
        expect( pane.polling, isTrue, reason: "$name is visible but reports no timer" );

        await pane.shut();
      } );

      test( "D · a second startPolling does not start a second timer", () async {
        final counter = _Counter();
        final pane    = build( lifecycle.stream, counter )
          ..begin()
          ..begin()
          ..begin();
        pane.show();
        await settle();

        expect( pane.requests, 1,
            reason: "$name polled once per startPolling — a rebuild must not stack timers" );

        await pane.shut();
      } );

      test( "E · backgrounding stops it, foregrounding refreshes exactly once", () async {
        final counter = _Counter();
        final pane    = build( lifecycle.stream, counter )..begin();
        pane.show();
        await settle();
        expect( pane.requests, 1 );

        lifecycle.add( AppLifecycleState.paused );
        await settle();
        expect( pane.polling, isFalse, reason: "$name keeps its timer while backgrounded" );
        expect( pane.requests, 1,      reason: "$name polled while backgrounded" );

        lifecycle.add( AppLifecycleState.resumed );
        await settle();
        expect( pane.polling, isTrue, reason: "$name did not restart on resume" );
        expect( pane.requests, 2,
            reason: "$name refreshed ${counter.calls - 1} times on one resume, not once" );

        await pane.shut();
      } );

      test( "F · hiding the pane stops it; a hidden pane does not restart on resume",
          () async {
        final counter = _Counter();
        final pane    = build( lifecycle.stream, counter )..begin();
        pane.show();
        await settle();

        pane.hide();
        await settle();
        expect( pane.polling, isFalse, reason: "$name keeps polling off screen" );

        lifecycle.add( AppLifecycleState.paused );
        lifecycle.add( AppLifecycleState.resumed );
        await settle();

        expect( pane.polling, isFalse,
            reason: "$name came back on a resume while it was still off screen" );
        expect( pane.requests, 1,
            reason: "$name refreshed while hidden — the app coming back is not a route" );

        await pane.shut();
      } );

      test( "G · close leaves nothing running", () async {
        final counter = _Counter();
        final pane    = build( lifecycle.stream, counter )..begin();
        pane.show();
        await settle();

        await pane.shut();

        expect( pane.polling, isFalse, reason: "$name left a timer behind after close" );

        final before = pane.requests;
        lifecycle.add( AppLifecycleState.paused );
        lifecycle.add( AppLifecycleState.resumed );
        await settle();

        expect( pane.requests, before,
            reason: "$name answered a lifecycle event after close — its subscription "
                    "outlived it" );
      } );
    } );
  }
}
