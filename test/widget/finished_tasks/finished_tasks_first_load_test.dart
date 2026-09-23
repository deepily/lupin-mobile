/// 🔴 MOUNTING THE PANE MUST FETCH. Regression guard for a bug found on hardware.
///
/// **What happened** (Rick, 2026-09-22, emulator walk-through item 7): open Finished Tasks
/// and it shows nothing but a spinner, forever. The logcat carried **no request to
/// `/api/tasks/events` at all** — the absence was the evidence, and it is what separated
/// "the fetch failed" from "the fetch never happened".
///
/// **The cause**: `FinishedTasksScreen` was a `StatelessWidget` whose `BlocBuilder` renders
/// a spinner for `FinishedTasksInitial`, and every dispatcher of `FinishedTasksRequested`
/// was user-initiated — refresh button, retry, pull-to-refresh, window slider. Nothing
/// fired on mount: not the screen, not the `BlocProvider`'s `create:`, not
/// `ServiceLocator.buildFinishedTasksBloc()`.
///
/// 🔴 **AND 15 WIDGET TESTS PASSED THROUGHOUT, BECAUSE THE HARNESS SENT THE EVENT ITSELF.**
/// `finished_tasks_pane_test.dart`'s `_host()` builds the bloc as
/// `FinishedTasksBloc( repo )..add( const FinishedTasksRequested() )`. Production
/// (`home_screen.dart`) builds it with a bare `create:` and no `..add`. So the suite proved
/// the table renders **given** a load, and the one thing it could not prove was that
/// anything asks for one. Third time tonight: the trigger and the render are different
/// things, and a test that supplies the trigger cannot test it.
///
/// ⇒ **This file mounts the screen the way the home screen mounts it** — bare `create:`,
/// no seeded event, no seeded state — and asserts data arrives anyway. Revert the screen
/// to a `StatelessWidget` and this goes red; that is the point of it.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/finished_tasks/data/finished_tasks_models.dart';
import 'package:lupin_mobile/features/finished_tasks/data/finished_tasks_repository.dart';
import 'package:lupin_mobile/features/finished_tasks/domain/finished_tasks_bloc.dart';
import 'package:lupin_mobile/features/finished_tasks/presentation/finished_tasks_screen.dart';

class _CountingRepo implements FinishedTasksRepository {
  int calls = 0;

  @override
  Future<FinishedFetchResult> fetchWindow( {
    required int days,
    required DateTime now,
    CancelToken? cancelToken,
  } ) async {
    calls += 1;
    return FinishedFetchResult(
      eventsByStatus : {
        "done": [
          FinishedTaskEvent(
            id         : 1,
            itemId     : "item-1",
            ts         : DateTime.now().subtract( const Duration( minutes: 7 ) ),
            actor      : "tiffany f19a8996",
            transition : "in_progress->done",
            reason     : "landed",
            title      : "A row that closed",
          ),
        ],
        "dropped"  : const [],
        "wont_fix" : const [],
      },
      failures   : const {},
      windowDays : clampWindowDays( days ),
    );
  }

  @override
  dynamic noSuchMethod( Invocation invocation ) => super.noSuchMethod( invocation );
}

void main() {
  /// Mounted EXACTLY as `home_screen.dart` mounts it: a bare `create:` with no trailing
  /// `..add(...)` and no pre-seeded state. Changing this to seed an event would restore
  /// the very defect this file exists to catch, so it is spelled out rather than helped.
  Widget productionHost( _CountingRepo repo ) {
    return MaterialApp(
      home: BlocProvider<FinishedTasksBloc>(
        create : ( _ ) => FinishedTasksBloc( repo ),
        child  : const FinishedTasksScreen(),
      ),
    );
  }

  Future<void> pumpPhone( WidgetTester tester, Widget app ) async {
    tester.view.physicalSize     = const Size( 360, 800 );
    tester.view.devicePixelRatio = 1.0;
    addTearDown( tester.view.reset );
    await tester.pumpWidget( app );
    await tester.pumpAndSettle();
  }

  testWidgets( '🔴 mounting the pane fetches, with nobody tapping anything', ( tester ) async {
    final repo = _CountingRepo();
    await pumpPhone( tester, productionHost( repo ) );

    expect( repo.calls, 1,
        reason: 'the pane must ask for its own data on mount — 0 here is the hardware bug: '
                'a spinner forever and not one request on the wire' );
  } );

  testWidgets( 'and the spinner is GONE, replaced by the row', ( tester ) async {
    await pumpPhone( tester, productionHost( _CountingRepo() ) );

    // The user-visible statement of the same fact. `repo.calls` could in principle be 1
    // while the state never left loading, and the symptom Rick reported was the spinner.
    expect( find.byType( CircularProgressIndicator ), findsNothing,
        reason: 'the reported symptom was "displays nothing but the spinner"' );
    expect( find.text( 'A row that closed' ), findsOneWidget );
  } );

  testWidgets( 'mounting fetches exactly ONCE, not once per rebuild', ( tester ) async {
    final repo = _CountingRepo();
    await pumpPhone( tester, productionHost( repo ) );

    // initState fires once per mount; a fix that dispatched from `build` instead would
    // pass the first test and quietly refetch on every rebuild — expensive, and invisible
    // until someone reads a server log.
    await tester.pump();
    await tester.pump( const Duration( milliseconds: 200 ) );
    await tester.pumpAndSettle();

    expect( repo.calls, 1, reason: 'a rebuild must not refetch' );
  } );
}
