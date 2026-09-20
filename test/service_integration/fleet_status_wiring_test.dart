/// The DI seam for Fleet Status — row a1962a5b, fleet-panes plan Phase 1.
///
/// `fleet_status_bloc_test` proves the bloc's LOGIC when a repository is handed
/// to it, and `fleet_status_screen_test` proves the route's lifecycle when a
/// factory is handed to it. Both hand in the dependency they exercise, so
/// neither can fail on production never supplying one — the exact shape of bug
/// 9adff476, which stayed invisible for weeks behind a green suite.
///
/// This file asserts the two things those files structurally cannot:
///   1. the production factory builds over the REGISTERED repository
///   2. it returns a FRESH bloc per call — never a singleton
///
/// (2) is the load-bearing one. Register `FleetStatusBloc` as a singleton in
/// `_initializeBLoCs` like every sibling bloc and the app still works, the
/// pane still renders, and its 60-second poller then runs for the whole life of
/// the process against a destination nobody is looking at.
///
/// It calls the extracted factory rather than `ServiceLocator.init()`, which
/// needs `path_provider` platform channels — the same reason
/// `quick_ask_probe_wiring_test` takes this route.
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:lupin_mobile/core/di/service_locator.dart';
import 'package:lupin_mobile/features/fleet_status/data/fleet_models.dart';
import 'package:lupin_mobile/features/fleet_status/data/fleet_repository.dart';

/// Counts reads so "the bloc was built over THIS repository" is proven by the
/// repository being USED, not by reading a private field.
class _CountingRepo implements FleetRepository {
  int stateCalls = 0;

  @override
  Future<FleetComposite> fetchState( { CancelToken? cancelToken } ) async {
    stateCalls++;
    return const FleetComposite( sessions: [], personas: {}, status: "ok" );
  }

  @override
  Future<Map<String, Object?>> fetchSizeCap( { CancelToken? cancelToken } ) async =>
      { "cap": 9, "maximum": 20 };

  @override
  Future<Map<String, Object?>> setSizeCap( int cap ) async =>
      { "cap": cap + 1, "maximum": 20 };
}

void main() {
  final getIt = GetIt.instance;
  late _CountingRepo repo;

  setUp( () {
    repo = _CountingRepo();
    getIt.registerSingleton<FleetRepository>( repo );
  } );

  tearDown( () async => getIt.reset() );

  test( "the production factory builds over the REGISTERED repository", () async {
    final bloc = ServiceLocator.buildFleetStatusBloc();
    addTearDown( bloc.close );

    await bloc.pollOnce( CancelToken() );

    expect(
      repo.stateCalls, 1,
      reason: "buildFleetStatusBloc must resolve FleetRepository from the "
              "locator. A bloc built over some other Dio would poll a "
              "different server and this count would stay 0.",
    );
  } );

  test( "🔴 every call returns a FRESH bloc — the pane bloc is NOT a singleton", () async {
    final a = ServiceLocator.buildFleetStatusBloc();
    final b = ServiceLocator.buildFleetStatusBloc();
    addTearDown( a.close );
    addTearDown( b.close );

    expect(
      identical( a, b ), isFalse,
      reason: "Route-scoping IS the zero-request guard. A singleton pane bloc "
              "outlives its route and keeps its 60-second timer polling a "
              "destination nobody is looking at — and the obvious test, "
              "'polling stops when backgrounded', passes with it running.",
    );
  } );
}
