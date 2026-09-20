import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/fleet_status/data/fleet_models.dart';

/// Fleet Status model tests.
///
/// ⚠️ THE FIXTURE IS A REAL CAPTURE, not a hand-written one. It came off
/// `GET /api/arbiter/fleet-state` on :7999 at 2026-09-19 20:4x EDT, through the
/// same reader the app uses. A hand-written fixture is better-formed than
/// reality in exactly the places a parser depends on the mess — this one
/// carries a null-persona session and nine mixed-case persona keys because the
/// live fleet did.
void main() {
  late Map<String, Object?> live;

  setUpAll( () {
    final f = File( "test/fixtures/fleet_status/fleet_state_live_2026.09.19.json" );
    live = jsonDecode( f.readAsStringSync() ) as Map<String, Object?>;
  } );

  group( "FleetComposite.fromJson — the real capture", () {
    test( "parses the live payload into ten sessions and nine persona records", () {
      final c = FleetComposite.fromJson( live );

      // Assert the loop found something BEFORE asserting anything about it —
      // a loop over nothing passes every assertion inside it.
      expect( c.sessions, isNotEmpty, reason: "fixture must carry sessions" );
      expect( c.sessions.length, 10 );
      expect( c.personas.length, 9 );
      expect( c.isUnreachable, isFalse );
      expect( c.appTimezone, "America/New_York" );
    } );

    test( "the exact-key persona join hits 9 of 10; the miss is the null-persona row", () {
      final c = FleetComposite.fromJson( live );

      final keyed = c.sessions.where(
        ( s ) => s.persona != null && c.personas.containsKey( s.persona ),
      ).toList();

      expect( keyed.length, 9, reason: "measured live 2026-09-19" );

      // NAME THE PATH: the one miss is the row with no persona at all, not a
      // case-mismatch. If a future capture fails this because of casing, that
      // is a real change in the producers, not a flaky test.
      final unkeyed = c.sessions.where( ( s ) => !keyed.contains( s ) ).toList();
      expect( unkeyed.single.persona, isNull );
    } );

    test( "A MATCHED KEY IS NOT A MEASURED ROW — the capture holds all three states", () {
      // 🔴 THIS IS WHY THE JOIN COUNT AND THE COLUMN COUNT DIFFER, and the
      // first cut of this test conflated them. Measured live 2026-09-19:
      //   7 rows fully measured
      //   1 row (sam)   window measured, pct NULL  → the two columns DISAGREE
      //   1 row (maria) both null                  → an IDLE persona
      //   1 row         no persona at all          → not in the map
      // The two window columns are not one fact, so each formatter takes its
      // own nullable and neither may stand in for the other.
      final c = FleetComposite.fromJson( live );

      final windowMeasured = c.sessions.where(
        ( s ) => c.contextFor( s ).windowSize != null,
      ).length;
      final pctMeasured = c.sessions.where(
        ( s ) => c.contextFor( s ).consumptionPctOfWindow != null,
      ).length;

      expect( windowMeasured, 8 );
      expect( pctMeasured,    7 );
      expect( windowMeasured == pctMeasured, isFalse,
          reason: "the two columns are independent and a fixture must prove it" );
    } );

    test( "a row with a window but no pct renders one column and an em dash in the other", () {
      final c   = FleetComposite.fromJson( live );
      final row = c.sessions.firstWhere( ( s ) => s.persona == "sam" );
      final ctx = c.contextFor( row );

      expect( formatWindowSize( ctx.windowSize ), "1M" );
      expect( formatConsumptionPct( ctx.consumptionPctOfWindow ), "—" );
    } );

    test( "an IDLE persona is present in the map but measures nothing", () {
      // CLAUDE.md's manager-tick rule states it: an IDLE persona returns null,
      // and a monitor that does not handle it explicitly is a monitor that lies.
      final c   = FleetComposite.fromJson( live );
      final row = c.sessions.firstWhere( ( s ) => s.persona == "maria" );
      final ctx = c.contextFor( row );

      expect( c.personas.containsKey( "maria" ), isTrue, reason: "the key IS there" );
      expect( formatWindowSize( ctx.windowSize ), "—" );
      expect( formatConsumptionPct( ctx.consumptionPctOfWindow ), "—" );
    } );

    test( "a null-persona session falls back to the short session id for Who", () {
      final c    = FleetComposite.fromJson( live );
      final row  = c.sessions.firstWhere( ( s ) => s.persona == null );

      expect( row.whoLabel.length, 8 );
      expect( row.whoLabel, row.sessionId!.substring( 0, 8 ) );
    } );
  } );

  group( "the unreachable envelope", () {
    // 🔴 The server returns this as an HTTP 200. A client that dispatches on
    // the HTTP status alone renders it as a fleet with zero seats.
    const envelope = {
      "status"         : "unreachable",
      "service"        : "lupin-arbiter-app",
      "detail"         : "ConnectError: [Errno 111] Connection refused",
      "health_watcher" : null,
      "fleet_arbiter"  : null,
    };

    test( "parses without throwing and flags itself", () {
      final c = FleetComposite.fromJson( envelope );
      expect( c.isUnreachable, isTrue );
      expect( c.sessions, isEmpty );
    } );

    test( "omits app_timezone, so the caller falls back to the device zone", () {
      final c = FleetComposite.fromJson( envelope );
      expect( c.appTimezone, isNull );
    } );

    test( "is distinguishable from a healthy fleet that simply has no seats", () {
      final empty = FleetComposite.fromJson( {
        "status"        : "ok",
        "app_timezone"  : "America/New_York",
        "fleet_arbiter" : { "sessions": <Object?>[] },
      } );

      // Both render an empty table; only one is a reason to restart something.
      expect( empty.sessions, isEmpty );
      expect( empty.isUnreachable, isFalse );
      expect( FleetComposite.fromJson( envelope ).isUnreachable, isTrue );
    } );
  } );

  group( "FleetComposite.fromJson — malformed input degrades rather than throws", () {
    test( "a non-map body yields an empty composite", () {
      expect( FleetComposite.fromJson( "nonsense" ).sessions, isEmpty );
      expect( FleetComposite.fromJson( null ).sessions, isEmpty );
    } );

    test( "a malformed sessions value yields an empty list", () {
      final c = FleetComposite.fromJson( {
        "fleet_arbiter": { "sessions": "not-a-list" },
      } );
      expect( c.sessions, isEmpty );
    } );

    test( "one malformed row cannot blank the rest of the pane", () {
      final c = FleetComposite.fromJson( {
        "fleet_arbiter": { "sessions": [ "garbage", { "persona": "chloe" } ] },
      } );
      expect( c.sessions.length, 2 );
      expect( c.sessions[ 0 ].whoLabel, "unknown" );
      expect( c.sessions[ 1 ].whoLabel, "chloe" );
    } );

    test( "a non-string persona key is dropped from the map", () {
      final c = FleetComposite.fromJson( {
        "context_pressure": { "personas": { 7: { "window_size": 1000000 } } },
      } );
      expect( c.personas, isEmpty );
    } );
  } );

  group( "FleetSession cell labels", () {
    test( "holding_on: the literal 'none' and empty both render an em dash", () {
      expect( FleetSession.fromJson( { "holding_on": "none" } ).holdingLabel, "—" );
      expect( FleetSession.fromJson( { "holding_on": "" } ).holdingLabel,     "—" );
      expect( FleetSession.fromJson( <String, Object?>{} ).holdingLabel,      "—" );
      expect( FleetSession.fromJson( { "holding_on": "user:rick" } ).holdingLabel, "user:rick" );
    } );

    test( "stuck renders a check or an em dash, truthy-coerced like the web", () {
      expect( FleetSession.fromJson( { "stuck": true } ).stuckLabel,  "✓" );
      expect( FleetSession.fromJson( { "stuck": false } ).stuckLabel, "—" );
      expect( FleetSession.fromJson( { "stuck": "yes" } ).stuckLabel, "—" );
      expect( FleetSession.fromJson( <String, Object?>{} ).stuckLabel, "—" );
    } );

    test( "role defaults to worker and state to unknown", () {
      expect( FleetSession.fromJson( <String, Object?>{} ).roleLabel,  "worker" );
      expect( FleetSession.fromJson( <String, Object?>{} ).stateLabel, "unknown" );
      expect( FleetSession.fromJson( { "role": "manager" } ).roleLabel, "manager" );
    } );

    test( "whoLabel prefers persona, then short id, then 'unknown'", () {
      expect( FleetSession.fromJson( { "persona": "chloe" } ).whoLabel, "chloe" );
      expect( FleetSession.fromJson( { "session_id": "42899779-d45a" } ).whoLabel, "42899779" );
      expect( FleetSession.fromJson( { "session_id": "short" } ).whoLabel, "short" );
      expect( FleetSession.fromJson( <String, Object?>{} ).whoLabel, "unknown" );
    } );

    test( "livenessDetail renders n/a for a missing age rather than dropping it", () {
      final s = FleetSession.fromJson( {
        "liveness": { "bridge_age_s": 23, "event_age_s": 23, "freshest_age_s": 22 },
      } );
      final detail = s.livenessDetail;

      expect( detail, contains( "bridge 23s" ) );
      expect( detail, contains( "commons n/a" ) );
      expect( detail, contains( "idle_prompt n/a" ) );
      // Five segments, so a gap is visible rather than the row silently shortening.
      expect( detail.split( " · " ).length, 5 );
    } );

    test( "offline is the exact string 'offline', and no verdict stays LIVE", () {
      // Ported from fleetModel.ts:155, :161-162. A hand-rolled predicate here
      // is dangerous because the verdict is FREE-FORM, not an enum: the live
      // fleet reported LIVE, "quiet 3m" and "stale 21m" on 2026-09-19, and a
      // stale seat is one the operator needs to chase, not one to hide.
      expect( FleetSession.fromJson( { "liveness": { "verdict": "offline" } } ).isOffline, isTrue );
      expect( FleetSession.fromJson( { "liveness": { "verdict": "LIVE" } } ).isOffline,    isFalse );
      expect( FleetSession.fromJson( { "liveness": { "verdict": "stale 21m" } } ).isOffline, isFalse );
      expect( FleetSession.fromJson( { "liveness": { "verdict": "quiet 3m" } } ).isOffline,  isFalse );
      // A row the arbiter has not judged stays visible rather than vanishing.
      expect( FleetSession.fromJson( <String, Object?>{} ).isOffline, isFalse );
      expect( FleetSession.fromJson( { "liveness": { "verdict": "OFFLINE" } } ).isOffline, isFalse,
          reason: "case matters — the server sends lowercase" );
    } );

    test( "the live capture hides nobody, and that is the correct answer", () {
      // A filter that never fires is worth proving rather than assuming: none
      // of the ten seats reported "offline", so the default view shows all ten.
      final c = FleetComposite.fromJson( live );
      expect( c.sessions, isNotEmpty );
      expect( c.sessions.where( ( s ) => s.isOffline ), isEmpty );
    } );

    test( "every live session in the real capture carries a verdict", () {
      final c = FleetComposite.fromJson( live );
      expect( c.sessions, isNotEmpty );
      for ( final s in c.sessions ) {
        expect( s.liveness.verdictLabel, isNotEmpty );
      }
    } );
  } );

  group( "FleetLiveness.fromJson", () {
    test( "a non-map input yields an all-null record", () {
      final l = FleetLiveness.fromJson( "nope" );
      expect( l.bridgeAgeS, isNull );
      expect( l.verdictLabel, "unknown" );
    } );

    test( "a non-numeric age is dropped to null rather than coerced", () {
      final l = FleetLiveness.fromJson( { "bridge_age_s": "23" } );
      expect( l.bridgeAgeS, isNull );
    } );

    test( "a non-string verdict is dropped to null", () {
      expect( FleetLiveness.fromJson( { "verdict": 7 } ).verdictLabel, "unknown" );
    } );
  } );

  group( "FleetContextRecord.fromJson", () {
    test( "a non-map input is the unmeasured state, not an error", () {
      final r = FleetContextRecord.fromJson( null );
      expect( r.consumptionPctOfWindow, isNull );
      expect( r.windowSize, isNull );
    } );

    test( "numeric fields are widened, not string-coerced", () {
      final r = FleetContextRecord.fromJson( {
        "consumption_pct_of_window": 32.8,
        "window_size"              : 1000000,
      } );
      expect( r.consumptionPctOfWindow, 32.8 );
      expect( r.windowSize, 1000000 );

      final bad = FleetContextRecord.fromJson( {
        "consumption_pct_of_window": "32.8",
        "window_size"              : "1000000",
      } );
      expect( bad.consumptionPctOfWindow, isNull );
      expect( bad.windowSize, isNull );
    } );
  } );

  group( "formatWindowSize — ported from fleetModel.ts:177-182", () {
    test( "exact millions and thousands compact; the rest print whole", () {
      expect( formatWindowSize( 1000000 ), "1M" );
      expect( formatWindowSize( 2000000 ), "2M" );
      expect( formatWindowSize( 200000 ),  "200K" );
      expect( formatWindowSize( 1000 ),    "1K" );
      expect( formatWindowSize( 1234 ),    "1234" );
    } );

    test( "null, zero and negative all render an em dash", () {
      expect( formatWindowSize( null ), "—" );
      expect( formatWindowSize( 0 ),    "—" );
      expect( formatWindowSize( -5 ),   "—" );
    } );
  } );

  group( "formatConsumptionPct — ported from fleetModel.ts:188-191", () {
    test( "null is the unmeasured em dash, not zero", () {
      // These are different facts: a seat at 0% is running and empty; a seat
      // with no record was never measured.
      expect( formatConsumptionPct( null ), "—" );
      expect( formatConsumptionPct( 0 ),    "0%" );
    } );

    test( "the backend's one-decimal rounding is printed, never re-rounded", () {
      expect( formatConsumptionPct( 32.8 ), "32.8%" );
      expect( formatConsumptionPct( 49.6 ), "49.6%" );
      expect( formatConsumptionPct( 8.0 ),  "8%" );
    } );
  } );
}
