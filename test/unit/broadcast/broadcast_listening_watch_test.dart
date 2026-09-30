import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/broadcast/data/broadcast_models.dart';
import 'package:lupin_mobile/features/broadcast/data/broadcast_repository.dart';
import 'package:lupin_mobile/features/broadcast/domain/broadcast_bloc.dart';

import '../_helpers/stub_dio.dart';

/// 🔴 THE HALF THAT MAKES THE ACCEPTANCE CLAUSE REAL.
///
/// `AckConfidence.interrupted` is the entire point of this pane, and every test of it so
/// far dispatched `BroadcastListeningInterrupted` by hand. That proves the FOLDING is
/// right and proves nothing about whether anything ever fires it. A guard nothing can
/// trigger is the shape this row has already been bitten by twice.
class _WatchableBloc extends BroadcastBloc {
  final Stream<AppLifecycleState> _lifecycle;

  _WatchableBloc( super.repo, this._lifecycle );

  @override
  Stream<AppLifecycleState> get lifecycleStream => _lifecycle;
}

void main() {
  late StubAdapter adapter;
  late StreamController<AppLifecycleState> lifecycle;
  late StreamController<bool> socket;

  dynamic fixture( String name ) =>
      jsonDecode( File( 'test/fixtures/commons/$name' ).readAsStringSync() );

  setUp( () {
    adapter   = StubAdapter();
    lifecycle = StreamController<AppLifecycleState>.broadcast();
    socket    = StreamController<bool>.broadcast();

    adapter.handlers[ 'GET ${BroadcastRepository.activeSessionsPath}' ] =
        ( _ ) => jsonBody( fixture( 'active_sessions.json' ) );
    adapter.handlers[ 'POST ${BroadcastRepository.broadcastPath}' ] =
        ( _ ) => jsonBody( fixture( 'broadcast_send_queued.json' ) );

    addTearDown( lifecycle.close );
    addTearDown( socket.close );
  } );

  /// The send fixture's broadcast id — the one the aggregate ends up holding.
  final ackPath = 'GET ${BroadcastRepository.ackDrainPath( 'b-fixture-0001' )}';

  Future<void> settle() => Future<void>.delayed( const Duration( milliseconds: 20 ) );

  Future<_WatchableBloc> sentBloc() async {
    final bloc = _WatchableBloc( BroadcastRepository( makeDio( adapter ) ), lifecycle.stream );
    addTearDown( bloc.close );
    bloc.startListeningWatch( socketStream: socket.stream );

    bloc.add( const BroadcastRosterRequested() );
    bloc.add( const BroadcastBodyChanged( 'all hands' ) );
    final deadline = DateTime.now().add( const Duration( seconds: 5 ) );
    while ( !bloc.state.canSend ) {
      if ( DateTime.now().isAfter( deadline ) ) fail( 'roster never loaded' );
      await Future<void>.delayed( const Duration( milliseconds: 5 ) );
    }
    bloc.add( const BroadcastSendConfirmed() );
    while ( bloc.state.aggregate == null ) {
      if ( DateTime.now().isAfter( deadline ) ) fail( 'send never landed' );
      await Future<void>.delayed( const Duration( milliseconds: 5 ) );
    }
    return bloc;
  }

  group( '🔴 what actually fires the interruption', () {
    for ( final state in <AppLifecycleState>[
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.detached,
    ] ) {
      test( 'leaving the foreground via $state breaks the window', () async {
        final bloc = await sentBloc();
        expect( bloc.state.aggregate!.confidence, AckConfidence.observed );

        lifecycle.add( state );
        await settle();

        expect( bloc.state.aggregate!.confidence, AckConfidence.interrupted );
        expect( bloc.state.aggregate!.summary, contains( 'could not be confirmed' ) );
      } );
    }

    test( '🔴 `inactive` does NOT — a shade pull is not a broken socket', () async {
      final bloc = await sentBloc();

      // Flutter delivers `inactive` for transient interruptions: a notification-shade
      // pull, an incoming-call banner. Those do not suspend delivery. Treating them as a
      // break would make the pane cry wolf on every shade pull, and a guard that fires
      // constantly is one people learn to ignore — which turns it into no guard at all.
      lifecycle.add( AppLifecycleState.inactive );
      await settle();

      expect( bloc.state.aggregate!.confidence, AckConfidence.observed );
      expect( bloc.state.aggregate!.summary, '0 of 3 acked' );
    } );

    test( 'a socket DROP breaks the window even in the foreground', () async {
      final bloc = await sentBloc();

      // A network blip while the operator is looking at the screen loses acks just as
      // completely as backgrounding does.
      socket.add( false );
      await settle();

      expect( bloc.state.aggregate!.confidence, AckConfidence.interrupted );
    } );

    test( '🔴 a socket RECONNECT whose read FAILS does not un-break it', () async {
      final bloc = await sentBloc();

      // No handler is registered for the ack path in this test, so the read 404s. That
      // is the whole point: a recovery that did not answer must leave the tally exactly
      // as interrupted as it found it. The tempting shape — catch, carry on — paints
      // "0 of 3 acked" in the confident voice after a read that never happened.
      socket.add( false );
      await settle();
      socket.add( true );
      await settle();

      expect( bloc.state.aggregate!.confidence, AckConfidence.interrupted );
      expect( bloc.state.aggregate!.summary, contains( 'could not be confirmed' ) );
    } );

    test( '🔴 a RECONNECT that reads back the saved acks DOES un-break it', () async {
      final bloc = await sentBloc();
      adapter.handlers[ ackPath ] = ( _ ) => jsonBody( fixture( 'broadcast_acks_saved.json' ) );

      socket.add( false );
      await settle();
      expect( bloc.state.aggregate!.confidence, AckConfidence.interrupted );

      socket.add( true );
      await settle();

      // The socket coming back is still not itself evidence about the acks pushed while
      // it was down. Going and READING those acks is — and that read is what the
      // reconnect now triggers (lupin row 1c7da903).
      expect( bloc.state.aggregate!.confidence, AckConfidence.recovered );
      expect( bloc.state.aggregate!.ackedCount, 2 );
      expect( bloc.state.aggregate!.summary,    isNot( contains( 'could not be confirmed' ) ) );
      expect( adapter.captured.last.path,       contains( 'broadcast-acks/b-fixture-0001' ) );
    } );

    test( '🔴 RESUMING reads them back too — the case a phone actually produces', () async {
      final bloc = await sentBloc();
      adapter.handlers[ ackPath ] = ( _ ) => jsonBody( fixture( 'broadcast_acks_saved.json' ) );

      // The ordinary phone story end to end: backgrounded, acks pushed at a suspended
      // socket, foregrounded again. Before this, that ended at "could not be confirmed"
      // and stayed there for good.
      lifecycle.add( AppLifecycleState.paused );
      await settle();
      expect( bloc.state.aggregate!.confidence, AckConfidence.interrupted );

      lifecycle.add( AppLifecycleState.resumed );
      await settle();

      expect( bloc.state.aggregate!.confidence, AckConfidence.recovered );
      expect( bloc.state.aggregate!.ackedCount, 2 );
    } );

    test( '🔴 a SERVER ERROR on resume is never shown as a complete tally', () async {
      final bloc = await sentBloc();
      adapter.handlers[ ackPath ] =
          ( _ ) => jsonBody( { 'detail' : 'Failed to read broadcast acks' }, status: 500 );

      lifecycle.add( AppLifecycleState.paused );
      await settle();
      lifecycle.add( AppLifecycleState.resumed );
      await settle();

      // A 500 is the endpoint refusing to pass off a failed query as "nobody acked"
      // (notifications.py:2461). Swallowing it here would undo that on this side of the
      // wire, and the pane would speak in the confident voice about a number it never got.
      expect( bloc.state.aggregate!.confidence, AckConfidence.interrupted );
      expect( bloc.state.aggregate!.summary,    contains( 'could not be confirmed' ) );
      expect( bloc.state.aggregate!.ackedCount, 0 );
    } );

    test( 'acks for ANOTHER broadcast never reach this tally, even from the read', () async {
      final bloc = await sentBloc();
      adapter.handlers[ ackPath ] = ( _ ) => jsonBody( {
        'acks' : [
          const {
            'broadcast_id' : 'b-SOMEONE-ELSE',
            'session_id'   : 'sess-stranger',
            'ack_status'   : 'completed',
          },
        ],
      } );

      lifecycle.add( AppLifecycleState.paused );
      await settle();
      lifecycle.add( AppLifecycleState.resumed );
      await settle();

      expect( bloc.state.aggregate!.ackedCount, 0 );
      expect( bloc.state.aggregate!.confidence, AckConfidence.recovered );
    } );

    test( 'the watch is idempotent — starting twice does not double-fire', () async {
      final bloc = await sentBloc();
      bloc.startListeningWatch( socketStream: socket.stream );
      await settle();

      lifecycle.add( AppLifecycleState.paused );
      await settle();

      // Not an assertion about the count of events — about the state being sane after a
      // re-registration, which a pane rebuild could plausibly cause.
      expect( bloc.state.aggregate!.confidence, AckConfidence.interrupted );
      expect( bloc.state.aggregate!.ackedCount, 0 );
    } );

    test( 'closing the bloc cancels both subscriptions', () async {
      final bloc = await sentBloc();
      await bloc.close();

      // Adding after close must not throw "emit after close". A leaked subscription here
      // would take down whatever stream it is attached to.
      lifecycle.add( AppLifecycleState.paused );
      socket.add( false );
      await settle();

      expect( bloc.isClosed, isTrue );
    } );
  } );
}
