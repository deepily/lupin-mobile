/// AC-S1.8 — `WebSocketService` exposes an OBSERVABLE connection state.
///
/// Three properties, asserted separately because they fail separately:
///   1. emits at ALL FIVE sites that mutate `_isConnected`;
///   2. distinct-until-changed, applied at the MUTATION site;
///   3. replays the CURRENT value on subscribe.
///
/// Property 1 is asserted STRUCTURALLY, on the source. That is deliberate and
/// is the stronger test here, not a shortcut: four of the five sites are
/// reachable only from inside a live socket's error and teardown paths, so a
/// behavioral test would cover two of five and read as if it covered all of
/// them — which is exactly the "looks observable and silently is not" failure
/// this criterion exists to prevent. The structural assertion goes red the
/// moment anyone reintroduces a raw assignment at any site, including a sixth
/// added later.
library;

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/services/websocket/websocket_service.dart';

void main() {
  group( 'AC-S1.8 property 1 — every mutation site publishes', () {
    final source = File( 'lib/services/websocket/websocket_service.dart' ).readAsStringSync();

    test( '`_isConnected` is assigned in exactly ONE place: the single writer', () {
      // The field declaration plus the one write inside `_setConnected`.
      // The `(?!=)` is load-bearing: without it the guard's own
      // `_isConnected == value` comparison counts as an assignment.
      final assignments = RegExp( r'_isConnected\s*=(?!=)' ).allMatches( source ).length;
      expect( assignments, 2,
          reason: 'a raw `_isConnected = ...` outside `_setConnected` bypasses the stream — '
                  'that is a site wired at zero of one, and it is silent' );
    } );

    test( 'there are exactly FIVE `_setConnected` call sites — the count AC-S1.8 names', () {
      final calls = RegExp( r'_setConnected\(' ).allMatches( source ).length;
      // 5 call sites + 1 declaration.
      expect( calls, 6,
          reason: 'AC-S1.8 counts five mutation sites (:120, :142, :279, :292, :365 at the time '
                  'of writing). A sixth is fine — route it through the writer and update this count.' );
    } );

    test( 'the single writer carries the distinct-until-changed guard', () {
      final writer = RegExp( r'void _setConnected\( bool value \) \{(.*?)\n  \}', dotAll: true )
          .firstMatch( source )?.group( 1 );
      expect( writer, isNotNull, reason: 'the single writer was renamed or removed' );
      expect( writer, contains( 'if ( _isConnected == value ) return;' ),
          reason: 'three of the five sites set false; without this guard one disconnect emits false repeatedly' );
    } );
  } );

  group( 'AC-S1.8 properties 2 and 3 — behavior', () {
    late WebSocketService ws;

    setUp( () { ws = WebSocketService( Dio() ); } );

    test( 'property 3 — a listener attached while ALREADY disconnected is told immediately', () async {
      // This is the criterion's own falsifier: an emit-only-on-change stream
      // gives this listener NOTHING, the button stays enabled, and the screen
      // never learns.
      expect( ws.isConnected, isFalse );
      final first = await ws.connectionStream.first.timeout( const Duration( seconds: 1 ) );
      expect( first, isFalse );
    } );

    test( 'property 3 — every NEW subscriber gets the replay, not just the first', () async {
      final a = await ws.connectionStream.first.timeout( const Duration( seconds: 1 ) );
      final b = await ws.connectionStream.first.timeout( const Duration( seconds: 1 ) );
      expect( [ a, b ], [ false, false ] );
    } );

    test( 'property 2 — a redundant transition to the SAME value emits nothing further', () async {
      final seen = <bool>[];
      final sub  = ws.connectionStream.listen( seen.add );
      await Future<void>.delayed( Duration.zero );
      expect( seen, [ false ], reason: 'the replay' );

      // disconnect() sets false; we are already false, so the guard must hold.
      await ws.disconnect();
      await ws.disconnect();
      await Future<void>.delayed( Duration.zero );

      expect( seen, [ false ],
          reason: 'without distinct-until-changed each disconnect re-emits false' );
      await sub.cancel();
    } );

    test( 'cancelling a subscriber does not disturb the others', () async {
      final seenA = <bool>[];
      final seenB = <bool>[];
      final subA  = ws.connectionStream.listen( seenA.add );
      final subB  = ws.connectionStream.listen( seenB.add );
      await Future<void>.delayed( Duration.zero );
      await subA.cancel();
      await ws.disconnect();
      await Future<void>.delayed( Duration.zero );

      expect( seenA, [ false ] );
      expect( seenB, [ false ] );
      await subB.cancel();
    } );

    test( 'a listener attached after dispose does not throw', () async {
      ws.dispose();
      await Future<void>.delayed( Duration.zero );
      // The replay still answers from the last known value; the underlying
      // broadcast controller being closed must not surface as a crash.
      expect( () => ws.connectionStream.listen( ( _ ) {} ), returnsNormally );
    } );
  } );
}
