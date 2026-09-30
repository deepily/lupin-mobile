import 'dart:async';

import 'package:dio/dio.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/finished_tasks/data/finished_tasks_models.dart';
import 'package:lupin_mobile/features/finished_tasks/data/finished_tasks_repository.dart';
import 'package:lupin_mobile/features/finished_tasks/domain/finished_tasks_bloc.dart';
import 'package:lupin_mobile/features/finished_tasks/domain/finished_tasks_state.dart';
import 'package:lupin_mobile/features/fleet/domain/pane_polling_mixin.dart';

/// Finished Tasks polls — gap G7, and the two traps that come with it.
///
/// 🔴 THIS PANE FETCHED ONCE ON MOUNT AND NEVER AGAIN. It is the pane whose whole job is
/// showing what just got done, so "never again" meant an operator watching for a row to
/// close had to pull-to-refresh to see it. The bloc's own comment said a timer was
/// deliberately absent because there was no visibility signal to hang one on; there is
/// one now, so the gap closes by connecting them rather than by writing a timer.
///
/// ─────────────────────────────────────────────────────────────────────────────────
/// 🔴 MUTATION MATRIX — MEASURED, NOT ASSERTED. Four defects reintroduced, run, restored.
///
/// | Test                                  | A | B | C | D |
/// |---------------------------------------|---|---|---|---|
/// | a tick fetches while visible           |🔴 | . | . | . |
/// | a hidden pane fetches nothing          |🔴 | . | . | . |
/// | a tick does not blank the table        | . |🔴 | . | . |
/// | a failed tick keeps the rows           | . | . |🔴 | . |
/// | a failed FIRST load still shows why    | . | . | . |🔴 |
/// | mobile data slows this pane too        |🔴 | . | . | . |
///
///   A — `onPaneVisible` / `startPolling` removed from the screen (the G7 state)
///   B — the poll routed through `FinishedTasksRequested`, which emits Loading
///   C — `silent` hard-coded false, so one lost poll replaces the table with an error
///   D — `silent` hard-coded true, so a failed FIRST load leaves a spinner forever
///
/// ⚠️ C AND D ARE OPPOSITE DEFECTS AND BOTH ARE REACHABLE FROM A ONE-WORD EDIT. That is
/// why `silent` is a CONDITION (`state is FinishedTasksLoaded`) rather than a constant,
/// and why both directions are tested: a reader tidying "polls should be quiet" into a
/// literal `true` reintroduces the exact spinner-forever bug Rick found on hardware, and
/// the original at least had no test claiming it was fixed.

/// A repository whose every call is scripted. Records how many windows were asked for.
class _ScriptedRepo implements FinishedTasksRepository {
  int calls = 0;

  /// When non-null, the next fetch throws this instead of answering.
  Object? failWith;

  /// The title the next successful fetch reports, so a repaint is visible to a test.
  String title = 'a row that closed';

  final List<CancelToken?> tokens = [];

  @override
  Future<FinishedFetchResult> fetchWindow( {
    required int days,
    required DateTime now,
    CancelToken? cancelToken,
  } ) async {
    calls += 1;
    tokens.add( cancelToken );
    final failure = failWith;
    if ( failure != null ) throw failure;

    return FinishedFetchResult(
      eventsByStatus : <String, List<FinishedTaskEvent>>{
        'done' : [
          FinishedTaskEvent(
            id         : calls,
            itemId     : 'item-$calls',
            ts         : now,
            actor      : 'sam 54a8247c',
            transition : 'in_progress->done',
            reason     : 'landed',
            title      : title,
          ),
        ],
        'dropped'  : const [],
        'wont_fix' : const [],
      },
      failures   : const <String, String>{},
      windowDays : clampWindowDays( days ),
    );
  }

  @override
  dynamic noSuchMethod( Invocation invocation ) => super.noSuchMethod( invocation );
}

/// The bloc with its connection dictated and its lifecycle stream in the test's hand.
class _TestBloc extends FinishedTasksBloc {
  final StreamController<AppLifecycleState> lifecycle;
  final bool metered;

  _TestBloc( super.repo, this.lifecycle, { this.metered = false } );

  @override
  Stream<AppLifecycleState> get lifecycleStream => lifecycle.stream;

  @override
  bool get isMeteredConnection => metered;
}

void main() {
  late StreamController<AppLifecycleState> lifecycle;

  setUp( () => lifecycle = StreamController<AppLifecycleState>.broadcast() );
  tearDown( () => lifecycle.close() );

  group( 'the pane polls — G7', () {
    // 🔴 THE ASSERTION G7 NEEDED. Before this row the pane fetched on mount and the count
    // stayed at 1 for as long as it was open.
    test( 'a tick fetches again while the pane is visible', () {
      fakeAsync( ( async ) {
        final repo = _ScriptedRepo();
        final bloc = _TestBloc( repo, lifecycle )..startPolling();

        bloc.onPaneVisible();
        async.flushMicrotasks();
        expect( repo.calls, 1, reason: 'appearing is the first load' );

        async.elapse( const Duration( seconds: 61 ) );
        async.flushMicrotasks();
        expect( repo.calls, 2,
            reason: 'a pane that never polls again is G7 exactly — the pane whose job is '
                    'showing what just got done, showing what got done a while ago' );

        bloc.close();
        async.flushTimers();
      } );
    } );

    test( 'a pane that is not on screen fetches nothing at all', () {
      fakeAsync( ( async ) {
        final repo = _ScriptedRepo();
        final bloc = _TestBloc( repo, lifecycle )..startPolling();

        async.elapse( const Duration( minutes: 10 ) );
        async.flushMicrotasks();

        expect( repo.calls, 0,
            reason: 'the whole point of the visibility signal: a bloc that outlives its '
                    'route must not poll from behind another pane' );
        expect( bloc.isPolling, isFalse );

        bloc.close();
        async.flushTimers();
      } );
    } );

    test( 'leaving the pane stops it', () {
      fakeAsync( ( async ) {
        final repo = _ScriptedRepo();
        final bloc = _TestBloc( repo, lifecycle )..startPolling();

        bloc.onPaneVisible();
        async.flushMicrotasks();
        bloc.onPaneHidden();

        async.elapse( const Duration( minutes: 10 ) );
        async.flushMicrotasks();
        expect( repo.calls, 1 );

        bloc.close();
        async.flushTimers();
      } );
    } );

    // The mixin's contract: "hand the token to the Dio call, or the cancellation buys
    // nothing." This pane's repository had no token parameter at all before this row.
    test( 'the poll token reaches the repository', () {
      fakeAsync( ( async ) {
        final repo = _ScriptedRepo();
        final bloc = _TestBloc( repo, lifecycle )..startPolling();

        bloc.onPaneVisible();
        async.flushMicrotasks();

        expect( repo.tokens.single, isNotNull,
            reason: 'a null token here means cancelling the timer leaves the request '
                    'running, and the response still wakes a backgrounded app' );

        bloc.close();
        async.flushTimers();
      } );
    } );

    // 🔴 EVERY POLLED PANE, NOT JUST THE TASK PANES. G8 was Fleet Status polling at 60 s
    // on mobile data; a new pane that overrode nothing would have inherited the same bug.
    test( 'mobile data slows this pane too', () {
      fakeAsync( ( async ) {
        final repo = _ScriptedRepo();
        final bloc = _TestBloc( repo, lifecycle, metered: true )..startPolling();

        expect( bloc.pollInterval, PanePollingMixin.mobileInterval );

        bloc.onPaneVisible();
        async.flushMicrotasks();
        async.elapse( const Duration( seconds: 179 ) );
        async.flushMicrotasks();
        expect( repo.calls, 1, reason: '60 s would have fired twice more' );

        async.elapse( const Duration( seconds: 2 ) );
        async.flushMicrotasks();
        expect( repo.calls, 2 );

        bloc.close();
        async.flushTimers();
      } );
    } );
  } );

  group( 'a tick is not a request the operator made', () {
    // 🔴 A POLL MUST NOT REPLACE THE ROWS WITH A SPINNER. `FinishedTasksRequested` emits
    // `FinishedTasksLoading`, which the screen renders as a full-pane spinner — so
    // reusing it for the tick would blank the table every 60 seconds on a pane whose
    // entire job is being read.
    test( 'a tick never emits Loading over rows already on screen', () {
      fakeAsync( ( async ) {
        final repo   = _ScriptedRepo();
        final bloc   = _TestBloc( repo, lifecycle )..startPolling();
        final states = <FinishedTasksState>[];
        final sub    = bloc.stream.listen( states.add );

        bloc.onPaneVisible();
        async.flushMicrotasks();
        expect( bloc.state, isA<FinishedTasksLoaded>() );

        states.clear();
        repo.title = 'a newer row';
        async.elapse( const Duration( seconds: 61 ) );
        async.flushMicrotasks();

        expect( states.whereType<FinishedTasksLoading>(), isEmpty,
            reason: 'the operator is reading this table; a spinner every minute is the '
                    'pane taking itself away from them' );
        expect( states.whereType<FinishedTasksLoaded>(), isNotEmpty,
            reason: 'fresh rows must still paint — silence is about failure, not success' );

        sub.cancel();
        bloc.close();
        async.flushTimers();
      } );
    } );

    // 🔴 ONE LOST POLL MUST NOT DESTROY THE TABLE. The rows are still true; the network
    // is what failed. The next tick fixes it, or the operator pulls to refresh and asks
    // properly, and THEN they get told.
    test( 'a failed tick leaves the rows standing', () {
      fakeAsync( ( async ) {
        final repo = _ScriptedRepo();
        final bloc = _TestBloc( repo, lifecycle )..startPolling();

        bloc.onPaneVisible();
        async.flushMicrotasks();
        final loaded = bloc.state;
        expect( loaded, isA<FinishedTasksLoaded>() );

        repo.failWith = const FinishedTasksApiException( 'network went away' );
        async.elapse( const Duration( seconds: 61 ) );
        async.flushMicrotasks();

        expect( bloc.state, isA<FinishedTasksLoaded>(),
            reason: 'an error view over a good table is the pane punishing the operator '
                    'for a poll they did not ask for' );
        expect( bloc.state, same( loaded ) );

        bloc.close();
        async.flushTimers();
      } );
    } );

    // 🔴 THE OPPOSITE DEFECT, AND THE ONE THAT COSTS MORE. `onPaneVisible` fires the
    // first load, so if the poll path were unconditionally silent a failed first load
    // would leave `FinishedTasksInitial` on screen — which renders as a spinner forever.
    // That is precisely the hardware bug Rick found on 2026-09-22, re-entered through the
    // back door of a well-meant "polls should be quiet" rule.
    test( 'a failed FIRST load still tells the operator why', () {
      fakeAsync( ( async ) {
        final repo = _ScriptedRepo()..failWith = const FinishedTasksApiException( 'boom' );
        final bloc = _TestBloc( repo, lifecycle )..startPolling();

        bloc.onPaneVisible();
        async.flushMicrotasks();

        expect( bloc.state, isA<FinishedTasksError>(),
            reason: 'with no rows to keep, an error is real news — staying silent here is '
                    'the spinner-forever bug wearing a different hat' );
        expect( ( bloc.state as FinishedTasksError ).message, 'boom' );

        bloc.close();
        async.flushTimers();
      } );
    } );

    // A cancellation is the lifecycle rule working, not a failure to paint.
    test( 'a cancelled poll paints nothing at all', () {
      fakeAsync( ( async ) {
        final repo = _ScriptedRepo();
        final bloc = _TestBloc( repo, lifecycle )..startPolling();

        bloc.onPaneVisible();
        async.flushMicrotasks();
        final loaded = bloc.state;

        repo.failWith = DioException(
          requestOptions : RequestOptions( path: '/api/tasks/events' ),
          type           : DioExceptionType.cancel,
        );
        async.elapse( const Duration( seconds: 61 ) );
        async.flushMicrotasks();

        expect( bloc.state, same( loaded ),
            reason: 'the pane is going away; painting anything paints it on the way out' );

        bloc.close();
        async.flushTimers();
      } );
    } );
  } );
}
