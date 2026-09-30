/// AC-S1.1 — `JobLifecycleState` agrees with a committed fixture of the
/// server's `STATE_TO_UI_CONTAINER`, asserted BIDIRECTIONALLY.
///
/// Both directions are load-bearing and are asserted SEPARATELY:
///   (a) alone passes when Dart has grown a member the server does not have;
///   (b) alone passes when the fixture has a key Dart cannot parse.
///
/// Scope limit, stated so nobody mistakes this for more than it is: this pins
/// Dart against a FIXTURE. It cannot detect the fixture going stale against
/// the live server — that is AC-G4, a parent-repo parity test, deliberately
/// not an S1 criterion and currently unowned.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/queue/domain/job_lifecycle.dart';

import '../../_helpers/fixture_loader.dart';

void main() {
  final fixture = ( loadFixture( 'queue/state_to_ui_container.json' )[ 'map' ] as Map )
      .map( ( k, v ) => MapEntry( k as String, v as String ) );

  group( 'AC-S1.1 — JobLifecycleState vs the server STATE_TO_UI_CONTAINER fixture', () {

    test( '(a) every FIXTURE key parses to an enum member carrying the fixture lane', () {
      expect( fixture, isNotEmpty, reason: 'fixture failed to load — the rest of this test would vacuously pass' );

      for ( final entry in fixture.entries ) {
        final parsed = JobLifecycleState.parse( entry.key );
        expect( parsed, isNotNull, reason: 'server state "${entry.key}" does not parse — Dart is missing a member' );
        expect( parsed!.lane.name, entry.value,
            reason: 'lane disagreement for "${entry.key}": Dart says ${parsed.lane.name}, server says ${entry.value}' );
      }
    } );

    test( '(b) every ENUM member appears as a fixture key', () {
      for ( final s in JobLifecycleState.values ) {
        expect( fixture.containsKey( s.name ), isTrue,
            reason: 'Dart has "${s.name}" but the server map does not — an invented state' );
      }
    } );

    test( 'the two directions cover the same set — neither side carries an extra', () {
      expect(
        JobLifecycleState.values.map( ( s ) => s.name ).toSet(),
        fixture.keys.toSet(),
      );
    } );

    test( 'stalled maps to todo, NOT dead — a stalled job is resumable', () {
      expect( fixture[ 'stalled' ], 'todo' );
      expect( JobLifecycleState.stalled.lane, JobLane.todo );
    } );

    test( 'unknown input returns null so the caller DROPS the frame', () {
      expect( JobLifecycleState.parse( 'teleported' ), isNull );
      expect( JobLifecycleState.parse( '' ),           isNull );
      expect( JobLifecycleState.parse( null ),         isNull );
      // Case matters: the wire is lowercase and we do not normalize, because a
      // casing mismatch is a server change we want to SEE, not absorb.
      expect( JobLifecycleState.parse( 'RUNNING' ),    isNull );
    } );
  } );

  group( 'AC-S1.1 — rank + terminal, the fold\'s two other primitives', () {

    test( 'rank is monotonic along the real transition path', () {
      expect( JobLifecycleState.pending.rank,   lessThan( JobLifecycleState.queued.rank ) );
      expect( JobLifecycleState.queued.rank,    lessThan( JobLifecycleState.running.rank ) );
      expect( JobLifecycleState.running.rank,   lessThan( JobLifecycleState.completed.rank ) );
      // stalled outranks running: it is LATER in time, even though its lane
      // walks back to todo.
      expect( JobLifecycleState.running.rank,   lessThan( JobLifecycleState.stalled.rank ) );
    } );

    test( 'every terminal outranks every non-terminal', () {
      final terminals    = JobLifecycleState.values.where( ( s ) =>  s.isTerminal );
      final nonTerminals = JobLifecycleState.values.where( ( s ) => !s.isTerminal );
      for ( final t in terminals ) {
        for ( final n in nonTerminals ) {
          expect( t.rank, greaterThan( n.rank ), reason: '$t must outrank $n' );
        }
      }
    } );

    test( 'isTerminal mirrors the server TERMINAL_STATES frozenset exactly', () {
      // job_state.py:65 — completed | failed | cancelled | interrupted.
      expect(
        JobLifecycleState.values.where( ( s ) => s.isTerminal ).map( ( s ) => s.name ).toSet(),
        { 'completed', 'failed', 'cancelled', 'interrupted' },
      );
    } );

    test( 'every terminal lands in done or dead; no terminal sits in todo or run', () {
      for ( final s in JobLifecycleState.values.where( ( s ) => s.isTerminal ) ) {
        expect( [ JobLane.done, JobLane.dead ], contains( s.lane ) );
      }
    } );
  } );
}
