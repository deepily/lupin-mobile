/// The Trust Dashboard is hidden from the home screen — Rick, 2026-09-22:
/// *"go ahead and disable visibility of the trust Dashboard it's currently back burnered
/// so I don't need to see it as an option."*
///
/// **Why a test for an absence.** The feature has **two** doors — a `_NavCard` in the list
/// and a shield `IconButton` in the app bar — and closing one while leaving the other is
/// the obvious way to get this wrong. Hiding a card is also the kind of change a later
/// merge re-introduces without anyone noticing, because nothing about a restored card
/// looks like a regression.
///
/// ⚠️ THIS TEST IS PAIRED WITH `_kShowTrustDashboard` IN `home_screen.dart`, DELIBERATELY.
/// Flipping that flag back to `true` turns this file red, and that is the intended
/// behaviour: re-enabling the dashboard should be a two-place decision someone makes on
/// purpose, not a drift. When you flip the flag, flip this file with it.
///
/// ⚠️ AND IT IS HIDDEN, NOT REMOVED. `trust_dashboard_screen_test.dart` and
/// `trust_state_screen_test.dart` still mount the screen directly and still pass — this
/// file is about the door, not the room. It also does not touch the reason the feature is
/// back-burnered: `decision_proxy_state.dart:45` uses `props => [ …length ]`, so the
/// dashboard silently stops updating when trust changes in place at a constant count.
/// **That defect is unfixed and a closed door is not a fix.**
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/home/home_screen.dart';

void main() {
  /// 🔴 THE HEIGHT IS THE WHOLE TRICK, AND I GOT IT WRONG FIRST.
  ///
  /// An absence test against a lazy `ListView` is a trap in both directions: a card below
  /// the fold is never built, so `findsNothing` passes while the card exists — and
  /// *scrolling* to look for it is worse, because a drag past the card disposes it and
  /// `findsNothing` passes again. My first version dragged -4000 and therefore **could
  /// not fail**: with `_kShowTrustDashboard = true` it still passed, while the app-bar
  /// test correctly went red. Measured, not theorised.
  ///
  /// ⇒ A viewport tall enough to lay the entire list out at once. Nothing is scrolled,
  /// nothing is disposed, and an absence is an absence.
  Future<void> mountHome( WidgetTester tester, { double height = 4000 } ) async {
    tester.view.physicalSize     = Size( 360, height );
    tester.view.devicePixelRatio = 1.0;
    addTearDown( tester.view.resetPhysicalSize );
    addTearDown( tester.view.resetDevicePixelRatio );

    await tester.pumpWidget( const MaterialApp( home: LupinHomeScreen() ) );
    await tester.pump();
  }

  testWidgets( 'no Trust Dashboard card anywhere in the home list', ( tester ) async {
    await mountHome( tester );

    // Sanity first: if the list did not fully build, every absence below is vacuous. This
    // is the last card in the list, so seeing it means everything above it is laid out.
    expect( find.text( 'Broadcast' ), findsOneWidget,
        reason: 'precondition — the viewport must be tall enough to build the WHOLE list, '
                'or `findsNothing` proves nothing at all' );

    expect( find.text( 'Trust Dashboard' ), findsNothing,
        reason: 'the card is back-burnered and must not be offered' );
    expect( find.text( 'Manage decision proxy approvals' ), findsNothing,
        reason: 'the card subtitle is as visible as the title' );
  } );

  testWidgets( '🔴 and no shield in the app bar either — both doors, not one', ( tester ) async {
    await mountHome( tester );

    // The app bar is the door that survives a card deletion, because it is nowhere near
    // the card in the file. One tap is not "hidden".
    expect(
      find.descendant(
        of      : find.byType( AppBar ),
        matching: find.byTooltip( 'Trust' ),
      ),
      findsNothing,
      reason: 'hiding the card while leaving the app-bar shield would leave the feature '
              'one tap away and call it hidden',
    );
    expect( find.byIcon( Icons.shield_outlined ), findsNothing,
        reason: 'the shield icon is the Trust affordance; nothing else uses it here' );
  } );

  testWidgets( 'the rest of the home screen is intact — this hid one thing, not several', ( tester ) async {
    await mountHome( tester );

    // A guard that only asserts absences passes just as well on a blank screen. These are
    // the neighbours the edit sat between, so they are what proves the cut was surgical.
    for ( final label in <String>[ 'Job Queue', 'Notifications', 'Agentic Jobs' ] ) {
      expect( find.text( label ), findsOneWidget, reason: '$label should be untouched' );
    }

    // And the app bar keeps its other three actions — the shield was one of four.
    for ( final tip in <String>[ 'Inbox', 'Settings', 'Logout' ] ) {
      expect(
        find.descendant( of: find.byType( AppBar ), matching: find.byTooltip( tip ) ),
        findsOneWidget,
        reason: '$tip was not the one being hidden',
      );
    }
  } );
}
