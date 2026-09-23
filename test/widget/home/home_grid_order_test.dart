/// The Home grid follows the notification client and the multiplexer, top to
/// bottom — Rick, 2026-09-23: those two are in sync and this grid should match
/// them. The web's page order, read off the live notification client:
///
///   Submit Agentic Jobs · (Claude Code task) · Claude Code Notifications ·
///   Broadcast · Fleet Status · Finished Tasks · Task List · Holding Area ·
///   Job Queues
///
/// One exception, Rick's own: Lupin Focus goes FIRST, because it is the surface
/// he uses most. It is also the landing screen, underneath the grid, so its card
/// returns there instead of pushing a second copy.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/home/home_screen.dart';

void main() {
  const expected = <String>[
    'Lupin Focus', 'Agentic Jobs', 'Claude Code', 'Broadcast', 'Fleet Status',
    'Finished Tasks', 'Task List', 'Holding Area', 'Job Queue',
  ];

  Future<void> mountHome( WidgetTester tester ) async {
    // Tall enough to build the whole lazy list — see trust_dashboard_hidden_test.dart.
    tester.view.physicalSize     = const Size( 360, 4000 );
    tester.view.devicePixelRatio = 1.0;
    addTearDown( tester.view.resetPhysicalSize );
    addTearDown( tester.view.resetDevicePixelRatio );
  }

  testWidgets( 'cards run in the web clients\' order, top to bottom', ( tester ) async {
    await mountHome( tester );
    await tester.pumpWidget( const MaterialApp( home: LupinHomeScreen() ) );
    await tester.pump();

    final tops = <String, double>{
      for ( final t in expected ) t: tester.getTopLeft( find.text( t ) ).dy,
    };
    final actual = expected.toList()..sort( ( a, b ) => tops[ a ]!.compareTo( tops[ b ]! ) );
    expect( actual, expected );
  } );

  testWidgets( 'the Lupin Focus card goes BACK to the landing screen, not a second copy', ( tester ) async {
    await mountHome( tester );
    await tester.pumpWidget( MaterialApp(
      home: Builder( builder: ( context ) => Scaffold(
        body: Center( child: ElevatedButton(
          onPressed: () => Navigator.of( context ).push(
            MaterialPageRoute<void>( builder: ( _ ) => const LupinHomeScreen() ),
          ),
          child: const Text( 'LANDING' ),
        ) ),
      ) ),
    ) );
    await tester.tap( find.text( 'LANDING' ) );
    await tester.pumpAndSettle();
    expect( find.byType( LupinHomeScreen ), findsOneWidget, reason: 'setup: grid pushed' );

    await tester.tap( find.byKey( const Key( TestKeys.homeLupinFocusCard ) ) );
    await tester.pumpAndSettle();

    expect( find.byType( LupinHomeScreen ), findsNothing );
    expect( find.text( 'LANDING' ), findsOneWidget );
  } );
}
