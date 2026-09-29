// pending-capture tag REMOVED 2026-09-29: watchable_roster.json was captured, so C5.9 runs in the gate.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/fleet_status/data/fleet_models.dart';
import 'package:lupin_mobile/features/fleet_status/data/fleet_watchable_models.dart';
import 'package:lupin_mobile/features/fleet_status/presentation/fleet_status_pane.dart';

import '../../_helpers/fixture_loader.dart';

/// C5.9 — the **FIELD ARM**, against CAPTURED server output. Red until phase 1 emits.
///
/// 🔴 THIS FILE IS SUPPOSED TO BE RED RIGHT NOW, AND THAT IS THE RULING RATHER THAN A
/// DEFECT. C5.9's field arm requires the button be proven to render "iff the joined
/// projection row's `transcript_watchable` is true, read from the **captured** projection
/// and fleet-state fixtures, **not a stubbed row**" (F-Clayton-C4). Mr. Radio's phase 1
/// has not emitted a frame yet, so `test/fixtures/transcript/` does not exist and
/// `fixture_loader` throws `FileSystemException` on every test below.
///
/// §5 chose red over skipped on purpose: *"They are red, not skipped, until the capture
/// lands… So phase 3 cannot close with any row still pending, and nothing can quietly pass
/// without its fixture."* María ruled the same way on 2026-09-27 and added the mechanism:
/// the tag, so the per-slice merge gate can exclude these rows while a printed roster keeps
/// them visible.
///
/// ⇒ **The gate for a slice is `./flutter.sh test --exclude-tags pending-capture`**, plus
/// the roster from `./flutter.sh test --tags pending-capture`. **Phase 3 closes only on a
/// plain `./flutter.sh test` with zero exclusions.**
///
/// ⚠️ MARÍA'S FIRST CONDITION IS THE ONE THAT KEEPS THIS TAG HONEST: a test may carry it
/// ONLY IF ITS SOLE FAILURE IS `fixture_loader`'s missing-file `FileSystemException`. Any
/// other failure disqualifies the tag, and the Reviewer checks the failure signature of
/// every tagged test. So each test below loads its fixture on its FIRST line — before any
/// widget is pumped and before any assertion — so there is no second way for it to fail.
///
/// ⚠️ SLICE 2 THEREFORE DOES NOT SATISFY C5.9. Its tap arm and semantics arm are green in
/// `fleet_watch_button_test.dart`; the field arm is here, unexecuted. That is stated in
/// the slice report rather than rounded off.
///
/// ## What the capture script must record, for this file to go green
///
/// `src/scripts/capture-transcript-fixtures.py` (§5, "Real frames, not invented ones" —
/// the same shape as the six existing `capture-*-fixtures.py`), redacted per
/// `test/fixtures/README.md`:
///
///   - `transcript/watchable_roster.json` — one roster-projection body carrying
///     `transcript_watchable` **both true and false**, so the "iff" has both directions
///   - `transcript/fleet_state_recaptured.json` — a **re-captured** fleet-state body, whose
///     `session_id`s are the strings the roster's rows must join to at the SAME WIDTH
///
/// 🔴 AND THE JOIN IS THE POINT OF USING TWO CAPTURED BODIES RATHER THAN ONE. A stubbed
/// row proves the pane's `contains()` works. Two captured bodies prove the two SURFACES
/// agree on the id — which is A3.6's question, the one §3 says "phase 1 verifies rather
/// than assuming", because three id widths circulate in this fleet and a silent mismatch
/// shows up as a roster row that cannot be watched. If the capture lands and this file goes
/// red on the JOIN rather than on a missing file, that is the finding, not a test bug.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    required FleetComposite composite,
    required Set<String> watchable,
  } ) async {
    tester.view.physicalSize     = const Size( 360, 800 );
    tester.view.devicePixelRatio = 1.0;
    addTearDown( tester.view.resetPhysicalSize );
    addTearDown( tester.view.resetDevicePixelRatio );

    await tester.pumpWidget( MaterialApp(
      home: Scaffold(
        body: FleetStatusPane(
          composite           : composite,
          watchableSessionIds : watchable,
          onWatch             : ( _ ) {},
        ),
      ),
    ) );
    await tester.pumpAndSettle();
  }

  Finder watchFor( String who ) =>
      find.byKey( Key( "${ TestKeys.fleetStatusWatchPrefix }$who" ) );

  testWidgets( "the button renders iff the CAPTURED projection says watchable",
      ( tester ) async {
    // FIRST LINE, deliberately: the only way this test can fail today is the missing
    // fixture, which is what lets it carry the `pending-capture` tag.
    final roster    = FleetWatchableRoster.fromJson(
      loadFixture( "transcript/watchable_roster.json" ) );
    final composite = FleetComposite.fromJson(
      loadFixture( "transcript/fleet_state_recaptured.json" ) );

    final watchable = roster.watchableSessionIds;

    expect( watchable, isNotEmpty,
        reason: "the captured roster must carry at least one watchable seat, or this row "
                "cannot prove the TRUE direction" );
    expect( roster.rows.any( ( r ) => !r.transcriptWatchable ), isTrue,
        reason: "and at least one NOT-watchable seat, or it cannot prove the FALSE "
                "direction — an 'iff' needs both" );

    await pump( tester, composite: composite, watchable: watchable );

    for ( final session in composite.sessions ) {
      final id       = session.sessionId;
      final expected = id != null && watchable.contains( id );

      expect(
        watchFor( session.whoLabel ),
        expected ? findsOneWidget : findsNothing,
        reason: "seat ${ session.whoLabel } (id $id): the captured projection says "
                "watchable=$expected",
      );
    }
  } );

  testWidgets( "the two CAPTURED surfaces agree on the session id at one width (A3.6)",
      ( tester ) async {
    final roster    = FleetWatchableRoster.fromJson(
      loadFixture( "transcript/watchable_roster.json" ) );
    final composite = FleetComposite.fromJson(
      loadFixture( "transcript/fleet_state_recaptured.json" ) );

    final fleetIds  = composite.sessions
        .map( ( s ) => s.sessionId )
        .whereType<String>()
        .toSet();
    final rosterIds = roster.rows
        .map( ( r ) => r.sessionId )
        .whereType<String>()
        .toSet();

    expect( rosterIds, isNotEmpty );
    expect( fleetIds, isNotEmpty );

    // 🔴 THE FAILURE THIS ROW EXISTS TO CATCH IS A PREFIX MATCH THAT ISN'T ONE. If the
    // roster carries 8-hex ids and fleet-state carries full ones, every button silently
    // disappears and nothing else in the suite notices — the pane's join is exact string
    // equality, and hiding is its safe direction.
    expect(
      rosterIds.intersection( fleetIds ),
      isNotEmpty,
      reason: "the roster's session_ids and fleet-state's share no string. §3 pins both "
              "to the full stable_session_id; if the projection is emitting the 8-hex "
              "form, the phone can never light up a watch button and the client cannot "
              "tell that from 'nothing is watchable'. roster: $rosterIds — "
              "fleet-state: $fleetIds",
    );

    for ( final id in rosterIds ) {
      expect( id.length, greaterThan( 8 ),
          reason: "roster id '$id' is the 8-hex form, not the stable_session_id §3 pins "
                  "cc_session_id to" );
    }
  } );
}
