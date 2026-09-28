import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/fleet_status/data/fleet_models.dart';
import 'package:lupin_mobile/features/fleet_status/data/fleet_repository.dart';
import 'package:lupin_mobile/features/fleet_status/data/fleet_watchable_models.dart';
import 'package:lupin_mobile/features/fleet_status/domain/fleet_status_bloc.dart';

/// A repository that counts calls and can be told to fail.
///
/// ⚠️ IT RETURNS DIFFERENT DATA PER CALL, on purpose. A fake that ignores its
/// input answers the same however the code behaves, and every assertion written
/// over it inherits that. This one's `stateCalls` is the thing under test in
/// the zero-request guard, so it must be able to disagree with itself.
class _FakeRepo implements FleetRepository {
  int stateCalls = 0;
  int capCalls   = 0;
  int putCalls   = 0;

  Object?   stateThrows;
  Object?   capThrows;
  Object?   putThrows;
  int       serverCap = 9;
  int       serverMax = 20;

  final FleetComposite composite;

  _FakeRepo( this.composite );

  @override
  Future<FleetComposite> fetchState( { CancelToken? cancelToken } ) async {
    stateCalls++;
    if ( stateThrows != null ) throw stateThrows!;
    return composite;
  }

  @override
  Future<Map<String, Object?>> fetchSizeCap( { CancelToken? cancelToken } ) async {
    capCalls++;
    if ( capThrows != null ) throw capThrows!;
    return { "cap": serverCap, "maximum": serverMax };
  }

  /// The roster the projection answers with. Defaults to `none` — "nothing is
  /// watchable" — which is what a non-admin caller genuinely gets.
  int                  watchableCalls = 0;
  Object?              watchableThrows;
  FleetWatchableRoster watchableRoster = FleetWatchableRoster.none;

  @override
  Future<FleetWatchableRoster> fetchWatchable( { CancelToken? cancelToken } ) async {
    watchableCalls++;
    if ( watchableThrows != null ) throw watchableThrows!;
    return watchableRoster;
  }

  @override
  Future<Map<String, Object?>> setSizeCap( int cap ) async {
    putCalls++;
    if ( putThrows != null ) throw putThrows!;
    // 🔴 THE SERVER DOES NOT ECHO. It re-reads the file and answers with what
    // it found, which is the whole reason the dial renders the reply rather
    // than its own input. This fake models that by answering a DIFFERENT
    // number from the one posted — if it echoed, the assertion below could not
    // fail and would be testing nothing.
    serverCap = cap + 1;
    return { "cap": serverCap, "maximum": serverMax };
  }
}

void main() {
  late FleetComposite live;

  setUpAll( () {
    final f = File( "test/fixtures/fleet_status/fleet_state_live_2026.09.19.json" );
    live = FleetComposite.fromJson( jsonDecode( f.readAsStringSync() ) );
  } );

  group( "polling is foreground-pane-only", () {
    test( "🔴 A HIDDEN PANE ISSUES ZERO REQUESTS", () async {
      // The guard §6.3 names. The obvious test — "polling stops when
      // backgrounded" — passes with every pane's timer still running, so the
      // assertion has to be about a pane that was never shown.
      final repo = _FakeRepo( live );
      final bloc = FleetStatusBloc( repo );

      bloc.startPolling();
      // Never told it is visible.
      await Future<void>.delayed( const Duration( milliseconds: 50 ) );

      expect( repo.stateCalls, 0, reason: "a pane off screen must not poll" );
      expect( bloc.isPolling, isFalse );
      await bloc.close();
    } );

    test( "becoming visible refreshes once, immediately", () async {
      final repo = _FakeRepo( live );
      final bloc = FleetStatusBloc( repo );

      bloc.startPolling();
      bloc.onPaneVisible();
      await Future<void>.delayed( const Duration( milliseconds: 50 ) );

      expect( repo.stateCalls, 1 );
      expect( bloc.isPolling, isTrue );
      await bloc.close();
    } );

    test( "going hidden stops the timer and issues nothing further", () async {
      final repo = _FakeRepo( live );
      final bloc = FleetStatusBloc( repo );

      bloc.startPolling();
      bloc.onPaneVisible();
      await Future<void>.delayed( const Duration( milliseconds: 50 ) );
      final afterVisible = repo.stateCalls;

      bloc.onPaneHidden();
      await Future<void>.delayed( const Duration( milliseconds: 50 ) );

      expect( bloc.isPolling, isFalse );
      expect( repo.stateCalls, afterVisible, reason: "no request after hiding" );
      await bloc.close();
    } );
  } );

  group( "a poll", () {
    test( "loads the composite and the dial together", () async {
      final repo = _FakeRepo( live );
      final bloc = FleetStatusBloc( repo );

      await bloc.pollOnce( CancelToken() );
      await Future<void>.delayed( Duration.zero );

      expect( bloc.state.composite?.sessions.length, 10 );
      expect( bloc.state.cap, 9 );
      expect( bloc.state.capMaximum, 20 );
      expect( bloc.state.error, isNull );
      // One request pair, so the dial cannot drift from the table by a poll.
      expect( repo.stateCalls, 1 );
      expect( repo.capCalls,   1 );
      await bloc.close();
    } );

    test( "a failed CAP read does not blank the table", () async {
      // The dial is one control; the table is the pane. They fetch together and
      // they fail apart.
      final repo = _FakeRepo( live )..capThrows = const FleetApiException( "cap down" );
      final bloc = FleetStatusBloc( repo );

      await bloc.pollOnce( CancelToken() );
      await Future<void>.delayed( Duration.zero );

      expect( bloc.state.composite?.sessions.length, 10 );
      expect( bloc.state.error, isNull, reason: "the table loaded fine" );
      await bloc.close();
    } );

    test( "a failed STATE read surfaces the server's words", () async {
      final repo = _FakeRepo( live )
        ..stateThrows = const FleetApiException( "arbiter proxy refused" );
      final bloc = FleetStatusBloc( repo );

      await bloc.pollOnce( CancelToken() );
      await Future<void>.delayed( Duration.zero );

      expect( bloc.state.error, "arbiter proxy refused" );
      await bloc.close();
    } );

    test( "🔴 A CANCELLED REQUEST CHANGES NO STATE", () async {
      // The pane went away mid-flight. Painting an error here would teach the
      // reader the arbiter is down when it is not — and onto a surface nobody
      // is looking at.
      final repo = _FakeRepo( live )..stateThrows = DioException(
        requestOptions : RequestOptions( path: "/api/arbiter/fleet-state" ),
        type           : DioExceptionType.cancel,
      );
      final bloc = FleetStatusBloc( repo );

      await bloc.pollOnce( CancelToken() );
      await Future<void>.delayed( Duration.zero );

      expect( bloc.state.error, isNull );
      expect( bloc.state.composite, isNull );
      await bloc.close();
    } );

    /// B1a, 2026-09-23 — Rick's 09-22 spinner. `composite == null && error == null`
    /// is the screen's spinner branch. A cancelled DIAL fetch used to escape the
    /// dial's own catch and hit the outer cancel-return, adding NEITHER state while
    /// holding a good table. Paired with the composite-cancel test above: that one
    /// must still add nothing, this one must now add Loaded. Mutation-proved: with
    /// the dial's `on DioException` removed, this goes RED.
    test( "🔴 A CANCELLED DIAL FETCH STILL LOADS THE TABLE — never neither state", () async {
      final repo = _FakeRepo( live );
      final bloc = FleetStatusBloc( repo );

      await bloc.pollOnce( CancelToken() );          // a good poll first: cap 9
      await Future<void>.delayed( Duration.zero );
      expect( bloc.state.cap, 9, reason: "setup" );

      repo
        ..serverCap = 4
        ..capThrows = DioException(
          requestOptions : RequestOptions( path: "/api/arbiter/fleet-size-cap" ),
          type           : DioExceptionType.cancel,
        );
      await bloc.pollOnce( CancelToken() );
      await Future<void>.delayed( Duration.zero );

      expect( bloc.state.composite?.sessions.length, 10, reason: "the table was in hand" );
      expect( bloc.state.error, isNull, reason: "a cancel is not a failure" );
      expect( bloc.state.cap, 9, reason: "the dial keeps its last known number" );
    } );

    test( "a dial cancel on the FIRST poll still leaves the pane out of the spinner", () async {
      final repo = _FakeRepo( live )..capThrows = DioException(
        requestOptions : RequestOptions( path: "/api/arbiter/fleet-size-cap" ),
        type           : DioExceptionType.cancel,
      );
      final bloc = FleetStatusBloc( repo );

      await bloc.pollOnce( CancelToken() );
      await Future<void>.delayed( Duration.zero );

      expect( bloc.state.composite == null && bloc.state.error == null, isFalse,
          reason: "that pair IS the spinner branch in fleet_status_screen.dart" );
      expect( bloc.state.cap, isNull, reason: "no number was ever known" );
    } );

    test( "an unreachable envelope loads as DATA, not as an error", () async {
      final repo = _FakeRepo( FleetComposite.fromJson( const {
        "status": "unreachable", "fleet_arbiter": null,
      } ) );
      final bloc = FleetStatusBloc( repo );

      await bloc.pollOnce( CancelToken() );
      await Future<void>.delayed( Duration.zero );

      expect( bloc.state.error, isNull, reason: "the fetch succeeded" );
      expect( bloc.state.composite?.isUnreachable, isTrue );
      await bloc.close();
    } );
  } );

  group( "setCap", () {
    test( "🔴 ADOPTS THE SERVER'S NUMBER, NOT THE ONE IT POSTED", () async {
      final repo = _FakeRepo( live )..serverCap = 5;
      final bloc = FleetStatusBloc( repo );

      await bloc.setCap( 7 );
      await Future<void>.delayed( Duration.zero );

      // The fake answers cap+1 precisely so an echo would be visible. If this
      // read 7, the dial would be showing a number the fleet is not enforcing.
      expect( bloc.state.cap, 8 );
      expect( repo.putCalls, 1 );
      await bloc.close();
    } );

    test( "a refusal re-reads live state and rethrows", () async {
      final repo = _FakeRepo( live )
        ..serverCap = 9
        ..putThrows = const FleetApiException( "cap exceeds the configured maximum" );
      final bloc = FleetStatusBloc( repo );

      await expectLater( bloc.setCap( 99 ), throwsA( isA<FleetApiException>() ) );
      await Future<void>.delayed( Duration.zero );

      // Re-read rather than guess: the handle must land on what is enforced.
      expect( repo.stateCalls, 1, reason: "the refusal triggered a re-read" );
      expect( bloc.state.cap, 9 );
      await bloc.close();
    } );
  } );

  // ═════════════════════════════════════════════════════════════════════════════════
  // THE WATCHABLE ROSTER — slice 2, §5 "Where it goes" / C5.9
  // ═════════════════════════════════════════════════════════════════════════════════

  group( "the watchable roster rides the same poll", () {
    // ⚠️ THE ROSTER IS FETCHED IN THE SAME PASS AS THE COMPOSITE AND THE DIAL, not on a
    // loop of its own — the same choice the dial already makes, so the buttons cannot drift
    // from the table by a poll interval.
    test( "one poll reads the composite, the dial AND the roster", () async {
      final repo = _FakeRepo( live )..watchableRoster = FleetWatchableRoster.fromJson( {
        "sessions": [ { "session_id": "seat-a", "transcript_watchable": true } ],
      } );
      final bloc = FleetStatusBloc( repo );

      await bloc.pollOnce( CancelToken() );
      await Future<void>.delayed( Duration.zero );

      expect( repo.stateCalls, 1 );
      expect( repo.capCalls, 1 );
      expect( repo.watchableCalls, 1 );
      expect( bloc.state.watchableSessionIds, { "seat-a" } );
      await bloc.close();
    } );

    test( "the default is an empty set — no roster, no buttons", () async {
      // `_FakeRepo` answers `none` unless a test says otherwise, which is what a non-admin
      // caller genuinely gets from the projection.
      final bloc = FleetStatusBloc( _FakeRepo( live ) );

      await bloc.pollOnce( CancelToken() );
      await Future<void>.delayed( Duration.zero );

      expect( bloc.state.watchableSessionIds, isEmpty );
      expect( bloc.state.error, isNull,
          reason: "an unavailable roster is not a pane error — it is the ordinary answer "
                  "for most callers, and the table must still load" );
      expect( bloc.state.composite?.sessions.length, 10 );
      await bloc.close();
    } );

    // 🔴 THE SAME SHAPE AS THE DIAL'S B1a CANCEL, AND THE SAME TRAP. A cancelled roster
    // fetch must not escape to the outer cancel-return, which adds NEITHER state while the
    // table is in hand — `composite == null && error == null` is the screen's spinner
    // branch. Mutation-proved: with the roster's `on DioException` arm removed, this goes
    // red on the table assertion.
    test( "🔴 A CANCELLED ROSTER FETCH STILL LOADS THE TABLE", () async {
      final repo = _FakeRepo( live )..watchableThrows = DioException(
        requestOptions : RequestOptions(
          path: FleetRepository.watchableRosterEndpoint ),
        type           : DioExceptionType.cancel,
      );
      final bloc = FleetStatusBloc( repo );

      await bloc.pollOnce( CancelToken() );
      await Future<void>.delayed( Duration.zero );

      expect( bloc.state.composite?.sessions.length, 10,
          reason: "the table was in hand before the roster was asked for" );
      expect( bloc.state.error, isNull, reason: "a cancel is not a failure" );
      expect( bloc.state.watchableSessionIds, isEmpty, reason: "and no buttons" );
      await bloc.close();
    } );

    test( "a NON-cancel DioException from the roster still fails the poll", () async {
      // `fetchWatchable` swallows these itself, so a real repository cannot produce one
      // here. This asserts the bloc does not ALSO swallow it — if the contract ever changes
      // so the repository raises, the poll must report rather than silently show a stale
      // table with no buttons and no explanation.
      final repo = _FakeRepo( live )..watchableThrows = DioException(
        requestOptions : RequestOptions(
          path: FleetRepository.watchableRosterEndpoint ),
        type           : DioExceptionType.connectionError,
        message        : "no route to host",
      );
      final bloc = FleetStatusBloc( repo );

      await bloc.pollOnce( CancelToken() );
      await Future<void>.delayed( Duration.zero );

      expect( bloc.state.error, isNotNull );
      await bloc.close();
    } );

    // 🔴 THE BUG I WROTE AND CAUGHT, ASSERTED AT THE BLOC RATHER THAN THE WIDGET. `setCap`
    // re-emits `Loaded` to carry the server's re-read of the dial and has nothing to say
    // about watchability. A `watchable` field that defaulted to `none` instead of null made
    // that emit empty the set — every watch button vanishing because the cap moved.
    test( "setCap's Loaded keeps the watchable set it did not fetch", () async {
      final repo = _FakeRepo( live )..watchableRoster = FleetWatchableRoster.fromJson( {
        "sessions": [ { "session_id": "seat-a", "transcript_watchable": true } ],
      } );
      final bloc = FleetStatusBloc( repo );

      await bloc.pollOnce( CancelToken() );
      await Future<void>.delayed( Duration.zero );
      expect( bloc.state.watchableSessionIds, { "seat-a" }, reason: "setup" );

      await bloc.setCap( 12 );
      await Future<void>.delayed( Duration.zero );

      expect( bloc.state.cap, 13, reason: "the fake re-reads, it does not echo" );
      expect( bloc.state.watchableSessionIds, { "seat-a" },
          reason: "the cap moved; watchability did not" );
      await bloc.close();
    } );

    // 🔴 THE SIBLING OF THE setCap BUG, AND POCHOLO FOUND IT AFTER I FIXED THE FIRST ONE.
    // I made the event's `watchable` field nullable-means-unknown, then initialised the
    // local in `pollOnce` to `FleetWatchableRoster.none` — a LEGAL VALUE — so a cancelled
    // roster fetch answered "nothing is watchable" and the reducer's `??` never fired. An
    // established roster was wiped and every watch button vanished, which is precisely the
    // conflation the field's own docstring forbids. He caught it with a probe, not a test:
    // good poll `{seat-alpha}`, then after a cancel `{}`.
    //
    // ⇒ "Nullable means unknown" has to hold at every ASSIGNMENT, not just at the
    // declaration. This row is the one that fails if the local goes back to a default.
    test( "🔴 A CANCELLED ROSTER FETCH KEEPS THE LAST KNOWN ROSTER", () async {
      final repo = _FakeRepo( live )..watchableRoster = FleetWatchableRoster.fromJson( {
        "sessions": [ { "session_id": "seat-alpha", "transcript_watchable": true } ],
      } );
      final bloc = FleetStatusBloc( repo );

      await bloc.pollOnce( CancelToken() );
      await Future<void>.delayed( Duration.zero );
      expect( bloc.state.watchableSessionIds, { "seat-alpha" }, reason: "setup" );

      // The pane went away mid-poll: the composite and the dial landed, the roster did not.
      repo.watchableThrows = DioException(
        requestOptions : RequestOptions(
          path: FleetRepository.watchableRosterEndpoint ),
        type           : DioExceptionType.cancel,
      );
      await bloc.pollOnce( CancelToken() );
      await Future<void>.delayed( Duration.zero );

      expect( bloc.state.watchableSessionIds, { "seat-alpha" },
          reason: "a cancellation says nothing about watchability. Answering `none` for it "
                  "makes every button vanish because the operator changed screens" );
      expect( bloc.state.composite?.sessions.length, 10,
          reason: "and the table still loaded — the roster fails apart from it" );
      await bloc.close();
    } );

    test( "a later poll that loses admin DOES empty the set", () async {
      // The other direction, so "keep what you have" cannot be read as "never clear". A
      // poll always supplies a roster, so a revoked role empties the set on the next one.
      final repo = _FakeRepo( live )..watchableRoster = FleetWatchableRoster.fromJson( {
        "sessions": [ { "session_id": "seat-a", "transcript_watchable": true } ],
      } );
      final bloc = FleetStatusBloc( repo );

      await bloc.pollOnce( CancelToken() );
      await Future<void>.delayed( Duration.zero );
      expect( bloc.state.watchableSessionIds, { "seat-a" }, reason: "setup" );

      repo.watchableRoster = FleetWatchableRoster.none;
      await bloc.pollOnce( CancelToken() );
      await Future<void>.delayed( Duration.zero );

      expect( bloc.state.watchableSessionIds, isEmpty,
          reason: "an admin role revoked between polls must take the buttons with it" );
      await bloc.close();
    } );
  } );
}
