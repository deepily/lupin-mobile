import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/home/home_screen.dart';

/// 🔴 THE GUARD FOR A DEFECT THAT SHIPPED FOUR TIMES.
///
/// Phases 2 through 5 each built a pane, tested it, merged it green — and none of them
/// could be opened on a phone. Measured 2026-09-22: `TaskListPane`, `HoldingAreaPane`,
/// `FinishedTasksScreen` and `BroadcastPane` were referenced ONLY by their own file and
/// their tests. No card, no route, no provider.
///
/// ⚠️ EVERY PANE TEST PASSED THE WHOLE TIME, AND THAT IS THE POINT. A pane test asserts
/// the pane works. It cannot assert that anyone can GET to the pane, because it mounts
/// the pane directly — which is exactly the reachability question it silently answers
/// "yes" to. Four suites were green about a feature nobody could reach.
///
/// ⇒ This file asserts the DOOR exists. It is deliberately dumb: it does not check that
/// the panes render, because four other suites already do that well. It checks the one
/// thing none of them can.
void main() {
  /// The home screen reads `AuthBloc` for some cards, so the ones under test here are
  /// only the four that do not — which is all of them. If that ever changes, this test
  /// will fail loudly rather than silently stop covering anything.
  Future<void> mountHome( WidgetTester tester ) async {
    tester.view.physicalSize     = const Size( 360, 800 );
    tester.view.devicePixelRatio = 1.0;
    addTearDown( tester.view.resetPhysicalSize );
    addTearDown( tester.view.resetDevicePixelRatio );

    await tester.pumpWidget( const MaterialApp( home: LupinHomeScreen() ) );
    await tester.pump();
  }

  testWidgets( '🔴 every fleet pane has a door on the home screen', ( tester ) async {
    await mountHome( tester );

    // Scroll the list so cards below the fold are built — the point is that the card
    // EXISTS, and a card off-screen in a ListView is still a reachable destination.
    for ( final entry in <String, String>{
      TestKeys.homeFleetStatusCard  : 'Fleet Status',
      TestKeys.homeTaskListCard     : 'Task List',
      TestKeys.homeHoldingAreaCard  : 'Holding Area',
      TestKeys.homeFinishedTasksCard: 'Finished Tasks',
      TestKeys.homeBroadcastCard    : 'Broadcast',
    }.entries ) {
      final card = find.byKey( Key( entry.key ) );
      await tester.scrollUntilVisible( card, 120, scrollable: find.byType( Scrollable ).first );
      expect(
        card,
        findsOneWidget,
        reason: '${entry.value} has no home-screen card — it would be unreachable, '
                'which is the exact defect this file exists to catch',
      );
    }
  } );

  testWidgets( 'each card is actually tappable, not just present', ( tester ) async {
    await mountHome( tester );

    // A card rendered with a null onTap looks identical in a `findsOneWidget` assertion
    // and goes nowhere. Presence is not reachability.
    for ( final key in <String>[
      TestKeys.homeTaskListCard,
      TestKeys.homeHoldingAreaCard,
      TestKeys.homeFinishedTasksCard,
      TestKeys.homeBroadcastCard,
    ] ) {
      final card = find.byKey( Key( key ) );
      await tester.scrollUntilVisible( card, 120, scrollable: find.byType( Scrollable ).first );

      final tile = find.descendant( of: card, matching: find.byType( ListTile ) );
      expect( tile, findsOneWidget, reason: key );
      expect(
        tester.widget<ListTile>( tile ).onTap,
        isNotNull,
        reason: '$key renders but does nothing when tapped',
      );
    }
  } );
}
