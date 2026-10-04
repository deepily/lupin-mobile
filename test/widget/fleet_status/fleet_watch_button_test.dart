import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/fleet_status/data/fleet_models.dart';
import 'package:lupin_mobile/features/fleet_status/presentation/fleet_status_pane.dart';

/// C5.9 — the watch affordance on a fleet row. The TAP arm, the SEMANTICS arm, and every
/// way the button is supposed to be absent.
///
/// ⚠️ THE FIELD ARM IS NOT HERE. C5.9 requires the "renders iff `transcript_watchable`"
/// half be proven against the **captured** projection and fleet-state fixtures rather than
/// a stubbed row (F-Clayton-C4), and phase 1 has not emitted yet so there is nothing to
/// capture. That arm lives in `fleet_watch_button_captured_test.dart`, tagged
/// `pending-capture` and RED until the capture lands (María's B3 ruling). **This file does
/// not satisfy the field arm and must not be reported as doing so** — what it proves is
/// that the pane's join, the tap target and the semantics tree behave, given a roster.
///
/// These build the ASSEMBLED PANE, not `FleetRowCard` in isolation: a card can be correct,
/// complete and never mounted, and every test of the card alone stays green.
void main() {
  /// One seat, identified by the FULL session id — §3 pins `cc_session_id` to the seat's
  /// `stable_session_id`, and the roster join is exact string equality on it.
  const fullId = "6bf7cfa9-964e-4cef-a5d9-a804a4d75874";
  const who    = "maya";

  FleetComposite compositeWith( {
    String? sessionId = fullId,
    String? status    = "ok",
  } ) {
    return FleetComposite(
      status   : status,
      sessions : [
        FleetSession(
          sessionId : sessionId,
          persona   : who,
          state     : "working",
          role      : "implementer",
          liveness  : const FleetLiveness( verdict: "live", freshestAgeS: 3 ),
        ),
      ],
      personas : const {},
    );
  }

  /// The pane under test, on a real phone surface.
  Future<List<FleetSession>> pump(
    WidgetTester tester, {
    required FleetComposite composite,
    Set<String> watchable = const <String>{},
    bool        wireOnWatch = true,
  } ) async {
    // 🔴 360 dp, NOT THE 800x600 TEST DEFAULT. The row packs eight facts into three bands
    // at 360 dp, and the watch button is a ninth thing in band three's `Wrap`. A desktop
    // surface would hide a wrap-overflow that a phone shows.
    tester.view.physicalSize     = const Size( 360, 800 );
    tester.view.devicePixelRatio = 1.0;
    addTearDown( tester.view.resetPhysicalSize );
    addTearDown( tester.view.resetDevicePixelRatio );

    final watched = <FleetSession>[];

    await tester.pumpWidget( MaterialApp(
      home: Scaffold(
        body: FleetStatusPane(
          composite           : composite,
          watchableSessionIds : watchable,
          onWatch             : wireOnWatch ? watched.add : null,
        ),
      ),
    ) );
    await tester.pumpAndSettle();
    return watched;
  }

  Finder watchButton()   => find.byKey( const Key( "${ TestKeys.fleetStatusWatchPrefix }$who" ) );
  Finder livenessCell()  => find.byKey( const Key( "${ TestKeys.fleetStatusLivenessPrefix }$who" ) );

  group( "C5.9 tap arm", () {
    testWidgets( "the button opens the console for THAT row's seat", ( tester ) async {
      final watched = await pump(
        tester,
        composite : compositeWith(),
        watchable : const { fullId },
      );

      expect( watchButton(), findsOneWidget );
      await tester.tap( watchButton() );
      await tester.pumpAndSettle();

      expect( watched, hasLength( 1 ) );
      expect( watched.single.sessionId, fullId,
          reason: "the console must open for the row that was tapped, at the FULL id — "
                  "the stream cannot be keyed on an 8-character prefix" );
    } );

    // 🔴 THE HALF THAT WOULD HAVE BEEN BROKEN BY THE EARLIER DRAFT'S PLACEMENT. It put the
    // button "beside `Icons.info_outline`", which is INSIDE `_livenessCell`'s `InkWell` —
    // so a tap on it would also have been a tap on the liveness target.
    testWidgets( "tapping it does NOT fire onLivenessTap", ( tester ) async {
      await pump( tester, composite: compositeWith(), watchable: const { fullId } );

      await tester.tap( watchButton() );
      await tester.pumpAndSettle();

      expect( find.byKey( const Key( TestKeys.fleetStatusLivenessSheet ) ), findsNothing,
          reason: "the liveness sheet is the observable effect of onLivenessTap. If it is "
                  "on screen, the watch button is inside the liveness hit target" );
    } );

    testWidgets( "the liveness cell still opens the liveness sheet", ( tester ) async {
      // The other direction: adding a sibling must not have stolen the original target.
      await pump( tester, composite: compositeWith(), watchable: const { fullId } );

      await tester.tap( livenessCell() );
      await tester.pumpAndSettle();

      expect( find.byKey( const Key( TestKeys.fleetStatusLivenessSheet ) ), findsOneWidget );
    } );
  } );

  group( "C5.9 semantics arm", () {
    // 🔴 `_livenessCell` IS `Semantics( …, excludeSemantics: true )`, WHICH DROPS EVERY
    // DESCENDANT'S SEMANTICS. A button placed inside it is not merely mislabelled to a
    // screen reader — it is INVISIBLE. So the assertion is not "it has a label", it is
    // "its node is not under that one".
    testWidgets( "it is a button node, and NOT a descendant of the liveness node",
        ( tester ) async {
      // ⚠️ DISPOSED INLINE, NOT VIA `addTearDown`. The framework's
      // "a SemanticsHandle was active at the end of the test" check runs BEFORE tear-downs,
      // so `addTearDown( handle.dispose )` fails every semantics test it is used in. Cost
      // me two red runs; recorded so the next person does not pay it again.
      final handle = tester.ensureSemantics();

      await pump( tester, composite: compositeWith(), watchable: const { fullId } );

      final watchNode = find.bySemanticsLabel( "Watch console for $who" );
      expect( watchNode, findsOneWidget );

      final semantics = tester.getSemantics( watchNode );
      expect( semantics.hasFlag( SemanticsFlag.isButton ), isTrue,
          reason: "a screen reader must announce it as a button, not as text" );

      // The liveness node must be findable for the next assertion to mean anything: a
      // `find.descendant` whose `of:` matches nothing yields nothing, so `findsNothing`
      // would pass for the wrong reason.
      final livenessNode = find.bySemanticsLabel( RegExp( r"^Liveness " ) );
      expect( livenessNode, findsOneWidget,
          reason: "the control for the control — without a liveness node on screen the "
                  "descendant check below cannot fail" );

      // The negative control C5.9 names: moving the button inside `_livenessCell` must
      // fail this arm. Under `excludeSemantics: true` the watch label would not exist at
      // all, so `findsOneWidget` above already goes red in that build; this states the
      // structural rule directly so the reason is legible rather than a bare "not found".
      expect(
        find.descendant( of: livenessNode, matching: watchNode, matchRoot: true ),
        findsNothing,
        reason: "the watch button's semantics node is inside the liveness Semantics, "
                "whose excludeSemantics: true makes every descendant unreachable to a "
                "screen reader",
      );

      handle.dispose();
    } );

    testWidgets( "the liveness node keeps its own label", ( tester ) async {
      final handle = tester.ensureSemantics();

      await pump( tester, composite: compositeWith(), watchable: const { fullId } );

      // `FleetLiveness.verdictLabel` is `verdict ?? "unknown"` — the RAW server string,
      // not an upper-cased one. I asserted "LIVE" first and it went red; the label is
      // "live". Reading the getter beat guessing from the pane's visual style.
      expect( find.bySemanticsLabel( "Liveness live for $who" ), findsOneWidget,
          reason: "the new sibling must not have absorbed or renamed the existing target" );

      handle.dispose();
    } );
  } );

  group( "C5.9 — every way the button is ABSENT", () {
    // §5: "a missing field, a missing row, a 403 or a failed projection call all read as
    // not watchable, so the button hides rather than offering a watch the server would
    // refuse." All four arrive at the pane as the same thing: an id not in the set.
    testWidgets( "not watchable ⇒ no button", ( tester ) async {
      await pump( tester, composite: compositeWith(), watchable: const <String>{} );
      expect( watchButton(), findsNothing );
    } );

    testWidgets( "a DIFFERENT seat being watchable does not light this row up",
        ( tester ) async {
      await pump(
        tester,
        composite : compositeWith(),
        watchable : const { "some-other-session-id" },
      );
      expect( watchButton(), findsNothing,
          reason: "the join is per row. A set with anything in it must not be read as "
                  "'watching is available'" );
    } );

    // 🔴 THE ID-WIDTH CASE, MADE EXPLICIT. Three id widths circulate in this fleet and §3
    // pins the stream to the full one. A roster keyed on the 8-hex form must NOT light up
    // a row carrying the full id: the watch would be sent with an id the server does not
    // know. Hiding is the safe direction, and A3.6 is the server-side check that the two
    // surfaces actually agree.
    testWidgets( "an 8-hex roster entry does not match a full-id row", ( tester ) async {
      await pump(
        tester,
        composite : compositeWith(),
        watchable : const { "6bf7cfa9" },
      );
      expect( watchButton(), findsNothing,
          reason: "a prefix match here would send cc_transcript_watch with an id the "
                  "stream cannot resolve" );
    } );

    testWidgets( "a row with no session id can never be watchable", ( tester ) async {
      // An IDLE seat with no id: there is nothing to key a watch on, whatever the roster
      // says. The `!` in the screen's `_openConsole` relies on exactly this.
      await pump(
        tester,
        composite : compositeWith( sessionId: null ),
        watchable : const { fullId },
      );
      expect( watchButton(), findsNothing );
    } );

    testWidgets( "no onWatch wired ⇒ no button anywhere", ( tester ) async {
      await pump(
        tester,
        composite   : compositeWith(),
        watchable   : const { fullId },
        wireOnWatch : false,
      );
      expect( watchButton(), findsNothing,
          reason: "a button that cannot do anything must not be drawn" );
    } );

    // 🔴 `status: "unreachable"` IS AN HTTP 200 WITH NULL SECTIONS, and the pane renders
    // its own notice for it. There are no rows at all, so there is no button — stated as a
    // test because §5 names it ("no error, no dead button") and because a future refactor
    // that rendered rows under the notice would reintroduce it.
    testWidgets( "an unreachable arbiter shows the notice and no buttons", ( tester ) async {
      await pump(
        tester,
        composite : compositeWith( status: "unreachable" ),
        watchable : const { fullId },
      );

      expect( find.byKey( const Key( TestKeys.fleetStatusUnreachable ) ), findsOneWidget );
      expect( watchButton(), findsNothing );
    } );
  } );

  // The button is a thumb target, not a mouse target. 48 dp is Android's floor and well
  // above WCAG 2.2 SC 2.5.8's 24x24; the liveness cell next to it takes the same floor.
  testWidgets( "the button is at least 48 dp square", ( tester ) async {
    await pump( tester, composite: compositeWith(), watchable: const { fullId } );

    final size = tester.getSize( watchButton() );
    expect( size.width,  greaterThanOrEqualTo( 48.0 ) );
    expect( size.height, greaterThanOrEqualTo( 48.0 ) );
  } );

  // Band three is a `Wrap`, so a ninth item cannot overflow — but it can only not overflow
  // if it is really in the Wrap. A `RenderFlex overflowed` error would be caught by the
  // pump above; this asserts the row is still fully laid out at 360 dp with the button in.
  testWidgets( "adding the button does not overflow the row at 360 dp", ( tester ) async {
    await pump( tester, composite: compositeWith(), watchable: const { fullId } );

    expect( tester.takeException(), isNull );
    expect( find.byKey( const Key( "${ TestKeys.fleetStatusRowPrefix }$who" ) ), findsOneWidget );
  } );
}
