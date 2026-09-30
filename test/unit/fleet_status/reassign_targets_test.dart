import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/fleet_status/data/fleet_models.dart';

/// The reassignment roster — ported from `taskListModel.ts:474`.
///
/// 🔴 THE FILTER IS THE POINT. Reassigning a row to an offline persona files the work
/// with NOBODY: the row moves, the board looks right, and the seat it now belongs to does
/// not exist. Nothing downstream catches that — the store accepts any string — so the
/// only place it can be prevented is here.
///
/// ─────────────────────────────────────────────────────────────────────────────────
/// 🔴 MUTATION MATRIX — MEASURED, NOT ASSERTED.
///
/// | Test                             | A: offline kept | B: no sort | C: unreachable kept |
/// |----------------------------------|-----------------|------------|---------------------|
/// | only live sessions are targets    | 🔴 RED          | 🔴 RED     | green               |
/// | returned alpha-sorted             | green           | 🔴 RED     | green               |
/// | the unreachable envelope → empty  | green           | green      | 🔴 RED              |
/// | a fleet with nobody live → empty  | 🔴 RED          | green      | green               |
///
///   A — the `isOffline` guard dropped
///   B — the sort removed (the arbiter's own order is not stable between reads)
///   C — the `isUnreachable` guard dropped
///
/// ⚠️ "only live sessions are targets" GOES RED UNDER B TOO, and that is worth saying
/// rather than tidying: it asserts an exact ordered list, so it detects the missing sort
/// as well as the missing filter. Useful — two detectors on one defect — but it means a
/// reader chasing that red must check the ORDER before concluding an offline seat leaked
/// through. The sort has its own test for exactly that reason.
void main() {
  FleetComposite build( List<Map<String, dynamic>> sessions, { String? status } ) =>
      FleetComposite.fromJson( <String, dynamic>{
        if ( status != null ) 'status' : status,
        'fleet_arbiter' : <String, dynamic>{ 'sessions' : sessions },
      } );

  Map<String, dynamic> seat( String? persona, { String? verdict } ) => <String, dynamic>{
        'persona'  : persona,
        'liveness' : <String, dynamic>{ if ( verdict != null ) 'verdict' : verdict },
      };

  test( 'only LIVE sessions become targets', () {
    final fleet = build( [
      seat( 'tiffany', verdict: 'live' ),
      seat( 'ghost',   verdict: 'offline' ),
      seat( 'chloe',   verdict: 'live' ),
    ] );

    expect( activeReassignTargets( fleet ), [ 'chloe', 'tiffany' ] );
  } );

  // ⚠️ SILENCE IS NOT A VERDICT. The arbiter says "offline" explicitly; a row that
  // carries no verdict stays LIVE, which is the same rule the fleet card paints by.
  // Reading a missing verdict as offline would empty the roster the moment the arbiter
  // trimmed its payload.
  test( 'a session with no verdict is live', () {
    expect( activeReassignTargets( build( [ seat( 'maria' ) ] ) ), [ 'maria' ] );
  } );

  test( 'blank and missing personas are dropped', () {
    final fleet = build( [
      seat( null,  verdict: 'live' ),
      seat( '',    verdict: 'live' ),
      seat( '   ', verdict: 'live' ),
      seat( 'sam', verdict: 'live' ),
    ] );

    expect( activeReassignTargets( fleet ), [ 'sam' ] );
  } );

  test( 'duplicates collapse', () {
    final fleet = build( [
      seat( 'sam', verdict: 'live' ),
      seat( 'sam', verdict: 'live' ),
    ] );

    expect( activeReassignTargets( fleet ), [ 'sam' ] );
  } );

  // The arbiter's own order is not stable across reads, so an unsorted roster would
  // reshuffle the owner dropdown under the operator's thumb between polls.
  test( 'returned alpha-sorted, case-insensitively', () {
    final fleet = build( [
      seat( 'Rachel',   verdict: 'live' ),
      seat( 'chloe',    verdict: 'live' ),
      seat( 'Mr Radio', verdict: 'live' ),
      seat( 'alice',    verdict: 'live' ),
    ] );

    expect( activeReassignTargets( fleet ), [ 'alice', 'chloe', 'Mr Radio', 'Rachel' ] );
  } );

  group( 'degrade-safe by contract, not by luck', () {
    test( 'null → empty', () {
      expect( activeReassignTargets( null ), isEmpty );
    } );

    // 🔴 `status: "unreachable"` IS A 200 ON PURPOSE. It means :7999 is fine and the
    // :8001 arbiter is not — the phone cannot see the fleet, so it does not know who
    // exists, and an empty roster is the honest answer.
    test( 'the unreachable envelope → empty', () {
      final fleet = build( [ seat( 'sam', verdict: 'live' ) ], status: 'unreachable' );
      expect( activeReassignTargets( fleet ), isEmpty );
    } );

    test( 'a malformed or missing sessions list → empty, never a throw', () {
      expect( activeReassignTargets( FleetComposite.fromJson( null ) ), isEmpty );
      expect( activeReassignTargets( FleetComposite.fromJson( 'not a map' ) ), isEmpty );
      expect(
        activeReassignTargets( FleetComposite.fromJson(
          <String, dynamic>{ 'fleet_arbiter' : <String, dynamic>{ 'sessions' : 'nope' } },
        ) ),
        isEmpty,
      );
    } );

    test( 'a fleet with nobody live → empty', () {
      final fleet = build( [ seat( 'ghost', verdict: 'offline' ) ] );
      expect( activeReassignTargets( fleet ), isEmpty );
    } );
  } );
}
