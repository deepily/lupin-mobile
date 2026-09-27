import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/fleet_status/data/fleet_repository.dart';
import 'package:lupin_mobile/features/fleet_status/data/fleet_watchable_models.dart';

import '../_helpers/stub_dio.dart';

/// The watchable-roster projection — the model and the one read.
///
/// 🔴 EVERY TEST HERE IS ABOUT ONE RULE: **NOTHING BUT A LITERAL `true` MAKES A SEAT
/// WATCHABLE, AND NO FAILURE MODE RAISES.** §3: "a missing field counts as false — so an
/// older server, or a projection that forgot it, hides the affordance rather than offering
/// a watch that would be refused. That is the safe direction." §5 extends it to the call
/// itself: "a missing field, a missing row, a 403 or a failed projection call all read as
/// not watchable".
///
/// ⚠️ THESE USE HAND-BUILT BODIES, NOT CAPTURED ONES, AND THAT IS A STATED LIMIT. They
/// prove the parser obeys the contract as written in §3; they cannot prove the server
/// emits that shape, because phase 1 has not emitted yet. C5.9's field arm is the captured
/// half and it is `pending-capture` red until then.
void main() {
  const fullId = "6bf7cfa9-964e-4cef-a5d9-a804a4d75874";

  group( "FleetWatchableRow.fromJson", () {
    test( "a full row parses every field", () {
      final row = FleetWatchableRow.fromJson( {
        "session_id"           : fullId,
        "project"              : "lupin-mobile",
        "last_ts"              : "2026-09-27T22:00:00+00:00",
        "transcript_watchable" : true,
      } );

      expect( row.sessionId, fullId );
      expect( row.project, "lupin-mobile" );
      expect( row.lastTs, "2026-09-27T22:00:00+00:00" );
      expect( row.transcriptWatchable, isTrue );
    } );

    test( "a missing transcript_watchable is FALSE, not null and not an error", () {
      final row = FleetWatchableRow.fromJson( { "session_id": fullId } );

      expect( row.transcriptWatchable, isFalse,
          reason: "§3: a missing field counts as false, so an older server hides the "
                  "affordance instead of offering a watch it would refuse" );
    } );

    // 🔴 NO COERCION. A server whose `transcript_watchable` has become a string or an int
    // is a server whose contract has moved, and a truthy read would offer a watch on a
    // guess. Every one of these is false.
    for ( final bad in <Object?>[ "true", "yes", 1, 0, "1", <String>[], {}, null ] ) {
      test( "transcript_watchable: ${ bad.runtimeType } '$bad' is false", () {
        final row = FleetWatchableRow.fromJson( {
          "session_id"           : fullId,
          "transcript_watchable" : bad,
        } );
        expect( row.transcriptWatchable, isFalse );
      } );
    }

    test( "a non-Map row yields an empty, unwatchable row rather than throwing", () {
      // One malformed entry must not blank the whole roster — the same rule
      // `FleetSession.fromJson` follows for the fleet table.
      for ( final junk in <Object?>[ null, "a string", 7, <String>[] ] ) {
        final row = FleetWatchableRow.fromJson( junk );
        expect( row.sessionId, isNull );
        expect( row.transcriptWatchable, isFalse );
      }
    } );

    test( "an empty-string field reads as absent", () {
      final row = FleetWatchableRow.fromJson( {
        "session_id" : "",
        "project"    : "",
        "last_ts"    : "",
      } );
      expect( row.sessionId, isNull );
      expect( row.project, isNull );
      expect( row.lastTs, isNull );
    } );
  } );

  group( "FleetWatchableRoster.watchableSessionIds", () {
    test( "only rows that are BOTH watchable and identifiable are included", () {
      final roster = FleetWatchableRoster.fromJson( {
        "sessions": [
          { "session_id": "a-watchable", "transcript_watchable": true  },
          { "session_id": "b-not",       "transcript_watchable": false },
          { "session_id": "c-missing"                                   },
          // 🔴 TRUE BUT UNIDENTIFIABLE. A row with no id cannot be joined to any fleet
          // row, so carrying it would put an unmatchable entry in the set — and a `Set`
          // containing null would make `contains( id )` on a nullable id dangerous.
          { "transcript_watchable": true },
        ],
      } );

      expect( roster.watchableSessionIds, { "a-watchable" } );
    } );

    test( "an unreachable arbiter yields NO watchable ids", () {
      // fleet-state answers `{status: "unreachable"}` as an HTTP 200 with null sections,
      // and the projection inherits that envelope. A3.7 requires it be distinguishable
      // from an empty fleet — and it must not produce buttons either way.
      final roster = FleetWatchableRoster.fromJson( {
        "status"   : "unreachable",
        "sessions" : [ { "session_id": "a", "transcript_watchable": true } ],
      } );

      expect( roster.isUnreachable, isTrue );
      expect( roster.watchableSessionIds, isEmpty,
          reason: "a roster the arbiter could not produce must not light up any button, "
                  "even if rows somehow came with it" );
      expect( roster.unavailable, isFalse,
          reason: "the projection ANSWERED. Unreachable and unavailable are different "
                  "facts — one is the arbiter being down, the other is the read failing" );
    } );

    test( "an empty fleet is distinguishable from an unreachable one (A3.7)", () {
      final empty = FleetWatchableRoster.fromJson( { "status": "ok", "sessions": [] } );

      expect( empty.watchableSessionIds, isEmpty );
      expect( empty.isUnreachable, isFalse,
          reason: "both render no buttons, but only one is a reason to go and restart "
                  "something. Collapsing them is the silent-failure shape A3.7 forbids" );
      expect( empty.unavailable, isFalse );
    } );

    test( "`none` is unavailable and watches nothing", () {
      expect( FleetWatchableRoster.none.unavailable, isTrue );
      expect( FleetWatchableRoster.none.watchableSessionIds, isEmpty );
      expect( FleetWatchableRoster.none.isUnreachable, isFalse );
    } );

    test( "a non-Map body is an empty roster, NOT an unavailable one", () {
      // The call succeeded and said nothing. That is an empty fleet, not a broken read.
      final roster = FleetWatchableRoster.fromJson( "not a body" );
      expect( roster.rows, isEmpty );
      expect( roster.unavailable, isFalse );
    } );

    // TODO(OSQ-6) mirrors the parser's own: the projection's body shape is not final, so
    // both spellings are read rather than one guessed. The captured fixture will pin it.
    test( "rows are read from `sessions`, `rows`, or nested `fleet_arbiter.sessions`", () {
      for ( final body in <Map<String, Object?>>[
        { "sessions": [ { "session_id": "x", "transcript_watchable": true } ] },
        { "rows"    : [ { "session_id": "x", "transcript_watchable": true } ] },
        { "fleet_arbiter": { "sessions": [
            { "session_id": "x", "transcript_watchable": true } ] } },
      ] ) {
        expect( FleetWatchableRoster.fromJson( body ).watchableSessionIds, { "x" },
            reason: "body shape ${ body.keys.first } did not parse" );
      }
    } );
  } );

  group( "FleetRepository.fetchWatchable", () {
    late StubAdapter adapter;
    late FleetRepository repo;

    setUp( () {
      adapter = StubAdapter();
      repo    = FleetRepository( makeDio( adapter ) );
    } );

    // Read off the constant, never re-typed as a literal — the path is not final
    // (OSQ-6) and a hand-copied string here would keep passing after it moved.
    const key = "GET ${ FleetRepository.watchableRosterEndpoint }";

    test( "a 200 is parsed", () async {
      adapter.handlers[ key ] = ( _ ) => jsonBody( {
        "status"   : "ok",
        "sessions" : [ { "session_id": fullId, "transcript_watchable": true } ],
      } );

      final roster = await repo.fetchWatchable();

      expect( roster.watchableSessionIds, { fullId } );
      expect( roster.unavailable, isFalse );
    } );

    // 🔴 THE FOUR REFUSALS §5 NAMES, AND NOT ONE OF THEM THROWS. A raise here would break
    // the fleet table for every non-admin operator over a feature they cannot use anyway:
    // `pollOnce` fetches the roster in the same pass as the composite.
    for ( final status in <int>[ 401, 403, 404, 500 ] ) {
      test( "HTTP $status reads as nothing-watchable and does NOT throw", () async {
        adapter.handlers[ key ] = ( _ ) => jsonBody( { "detail": "nope" }, status: status );

        final roster = await repo.fetchWatchable();

        expect( roster.unavailable, isTrue );
        expect( roster.watchableSessionIds, isEmpty );
      } );
    }

    test( "an absent endpoint (the stub's own 404) reads as nothing-watchable", () async {
      // No handler registered at all — which is exactly a server that predates the
      // projection. This is the one that matters most today, because on every server
      // running right now the endpoint does not exist.
      final roster = await repo.fetchWatchable();

      expect( roster.unavailable, isTrue );
      expect( roster.watchableSessionIds, isEmpty );
    } );

    test( "a transport failure reads as nothing-watchable", () async {
      adapter.handlers[ key ] = ( options ) => throw DioException.connectionError(
        requestOptions : options,
        reason         : "no route to host",
      );

      final roster = await repo.fetchWatchable();

      expect( roster.unavailable, isTrue );
    } );

    // 🔴 A CANCELLATION IS THE ONE THING THAT PROPAGATES, and it must, because it is not
    // an answer about watchability — it is the pane going away. `pollOnce` distinguishes
    // the two: a cancelled roster keeps the table it already has.
    test( "a CANCELLED request rethrows rather than answering 'not watchable'", () async {
      final token = CancelToken();
      adapter.handlers[ key ] = ( options ) => throw DioException.requestCancelled(
        requestOptions : options,
        reason         : null,
      );

      await expectLater(
        repo.fetchWatchable( cancelToken: token ),
        throwsA( isA<DioException>().having(
          ( e ) => e.type, "type", DioExceptionType.cancel ) ),
      );
    } );

    test( "the cancel token reaches the request", () async {
      final token = CancelToken();
      adapter.handlers[ key ] = ( _ ) => jsonBody( { "sessions": <Object?>[] } );

      await repo.fetchWatchable( cancelToken: token );

      expect( adapter.captured.single.cancelToken, same( token ),
          reason: "an unhanded token buys nothing — the request must be cancellable when "
                  "the pane goes away mid-poll" );
    } );

    test( "a 200 carrying the unreachable envelope is parsed, not refused", () async {
      adapter.handlers[ key ] = ( _ ) => jsonBody( { "status": "unreachable" } );

      final roster = await repo.fetchWatchable();

      expect( roster.isUnreachable, isTrue );
      expect( roster.unavailable, isFalse,
          reason: "reading a deliberate 200 envelope as a failed read would lose the "
                  "distinction A3.7 exists to preserve" );
    } );
  } );
}
