/// The Notifications inbox is hidden from the home screen — Rick, 2026-09-23: the inbox is
/// superfluous, it has been replaced by the Lupin Focus tab. Hide it, don't delete it.
///
/// ⚠️ PAIRED WITH `_kShowNotificationsInbox` IN `home_screen.dart`, DELIBERATELY — same
/// shape as `trust_dashboard_hidden_test.dart`. Flipping the flag back to `true` turns
/// this file red; flip both on purpose.
///
/// **Two doors, both asserted**: the grid card and the app-bar Inbox icon. Absences are
/// asserted by text and tooltip, never by `Icons.inbox_outlined` — the Holding Area card
/// uses that icon too, so an icon-based absence could never pass.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/home/home_screen.dart';

void main() {
  /// Tall enough to lay the whole lazy list out at once — see the trap documented in
  /// `trust_dashboard_hidden_test.dart`: a card below the fold is never built, so an
  /// absence against a short viewport proves nothing.
  Future<void> mountHome( WidgetTester tester ) async {
    tester.view.physicalSize     = const Size( 360, 4000 );
    tester.view.devicePixelRatio = 1.0;
    addTearDown( tester.view.resetPhysicalSize );
    addTearDown( tester.view.resetDevicePixelRatio );

    await tester.pumpWidget( const MaterialApp( home: LupinHomeScreen() ) );
    await tester.pump();
  }

  testWidgets( 'no Notifications card anywhere in the home grid', ( tester ) async {
    await mountHome( tester );

    expect( find.text( 'Broadcast' ), findsOneWidget,
        reason: 'precondition — the last card must be built, or `findsNothing` is vacuous' );

    expect( find.text( 'Notifications' ), findsNothing,
        reason: 'superseded by the Lupin Focus tab and must not be offered' );
    expect( find.text( 'View notification inbox' ), findsNothing,
        reason: 'the card subtitle is as visible as the title' );
  } );

  testWidgets( '🔴 and no Inbox icon in the app bar either — both doors, not one', ( tester ) async {
    await mountHome( tester );

    expect(
      find.descendant( of: find.byType( AppBar ), matching: find.byTooltip( 'Inbox' ) ),
      findsNothing,
      reason: 'hiding the card while leaving the app-bar icon leaves the inbox one tap away',
    );
  } );

  testWidgets( 'the neighbours survive — this hid one thing, not several', ( tester ) async {
    await mountHome( tester );

    // The Holding Area shares the inbox icon; it is the likeliest collateral damage.
    for ( final label in <String>[ 'Claude Code', 'Agentic Jobs', 'Holding Area' ] ) {
      expect( find.text( label ), findsOneWidget, reason: '$label should be untouched' );
    }
    for ( final tip in <String>[ 'Settings', 'Logout' ] ) {
      expect(
        find.descendant( of: find.byType( AppBar ), matching: find.byTooltip( tip ) ),
        findsOneWidget,
        reason: '$tip was not the one being hidden',
      );
    }
  } );
}
