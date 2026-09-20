import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/fleet_status/data/fleet_models.dart';
import 'package:lupin_mobile/features/fleet_status/data/fleet_repository.dart';
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
}
