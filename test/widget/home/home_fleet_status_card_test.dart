/// The home screen's Fleet Status destination — row a1962a5b, Phase 1.
///
/// ⚠️ NO pumpAndSettle IN THIS FILE. Once the Fleet Status route is open it
/// runs a 60-second `Timer.periodic`, so `pumpAndSettle` waits for a quiescent
/// frame a live poller will not produce and fails on "a Timer is still
/// pending" rather than on anything the test asserts. Every wait is an
/// explicit `pump( duration )`, and every test that opens the route pops it.
library;

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/fleet_status/data/fleet_models.dart';
import 'package:lupin_mobile/features/fleet_status/data/fleet_repository.dart';
import 'package:lupin_mobile/features/fleet_status/presentation/fleet_status_screen.dart';
import 'package:lupin_mobile/features/home/home_screen.dart';

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

  /// The row body says the pane must be legible at 360 dp, so the tests look at
  /// it there and never at the 800x600 default — a card that fits the default
  /// and overflows a real phone would otherwise ship green.
  Future<void> pumpHome( WidgetTester tester ) async {
    tester.view.physicalSize     = const Size( 360, 800 );
    tester.view.devicePixelRatio = 1.0;
    addTearDown( tester.view.resetPhysicalSize );
    addTearDown( tester.view.resetDevicePixelRatio );

    // Leave the route if a test opened it, or its 60-second timer is still
    // pending at teardown and the framework fails on that instead.
    addTearDown( () async {
      final open = find.byType( FleetStatusScreen );
      if ( open.evaluate().isNotEmpty ) {
        Navigator.of( tester.element( open ) ).pop();
        await tester.pump( const Duration( milliseconds: 50 ) );
      }
    } );

    // 🔴 NO BlocProvider ABOVE THIS SCREEN, AND THAT IS THE ASSERTION. Every
    // sibling card reads its bloc off an ancestor; this one must not, so the
    // home screen is pumped BARE. If the card were ever rewritten to
    // `BlocProvider.value( context.read<FleetStatusBloc>() )` like its
    // siblings, the tap below would throw ProviderNotFoundException here.
    await tester.pumpWidget( const MaterialApp( home: LupinHomeScreen() ) );
    await tester.pump();
  }

  Future<void> openRoute( WidgetTester tester ) async {
    await tester.pump();                                     // start the transition
    await tester.pump( const Duration( milliseconds: 400 ) ); // run it out
    await tester.pump();                                     // first build lands
  }

  Future<void> tapCard( WidgetTester tester ) async {
    final card = find.byKey( const Key( TestKeys.homeFleetStatusCard ) );
    await tester.scrollUntilVisible( card, 120, scrollable: find.byType( Scrollable ).first );
    await tester.tap( card );
  }

  testWidgets( "the card is on the home screen at 360 dp", ( tester ) async {
    await pumpHome( tester );

    await tester.scrollUntilVisible(
      find.byKey( const Key( TestKeys.homeFleetStatusCard ) ),
      120,
      scrollable: find.byType( Scrollable ).first,
    );

    expect( find.byKey( const Key( TestKeys.homeFleetStatusCard ) ), findsOneWidget );
    expect( find.text( "Fleet Status" ), findsOneWidget );
    expect( tester.takeException(), isNull, reason: "no overflow at 360 dp" );
  } );

  testWidgets( "tapping it opens the Fleet Status destination", ( tester ) async {
    await pumpHome( tester );
    await tapCard( tester );
    await openRoute( tester );

    expect( find.byType( FleetStatusScreen ), findsOneWidget );
  } );

  testWidgets( "the route builds its OWN bloc over the registered repository", ( tester ) async {
    await pumpHome( tester );

    // Before the tap the destination has never been opened, so no bloc exists
    // and nothing can have polled.
    expect( repo.stateCalls, 0, reason: "an unopened pane issues zero requests" );

    await tapCard( tester );
    await openRoute( tester );

    // The bloc the CARD built — not one handed in by this test — reached the
    // repository the locator holds. Point the card at a different construction
    // path and this stays 0.
    expect( repo.stateCalls, 1 );
    expect(
      find.byType( FleetStatusScreen ), findsOneWidget,
      reason: "reached without any FleetStatusBloc provided above the home "
              "screen — BlocProvider( create: ), not .value( context.read )",
    );
  } );

  testWidgets( "🔴 leaving the pane stops the poller", ( tester ) async {
    await pumpHome( tester );
    await tapCard( tester );
    await openRoute( tester );
    expect( repo.stateCalls, 1 );

    Navigator.of( tester.element( find.byType( FleetStatusScreen ) ) ).pop();
    await tester.pump( const Duration( milliseconds: 300 ) );
    await tester.pump( const Duration( seconds: 2 ) );

    expect(
      repo.stateCalls, 1,
      reason: "the route's disposal must cancel the timer. This is the whole "
              "reason the card departs from its siblings, so it is asserted "
              "from the card's own path and not only from a hand-built route.",
    );
    expect( find.byType( LupinHomeScreen ), findsOneWidget );
  } );
}
