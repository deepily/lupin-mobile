/// The stop poke client (row ee68d5e7): what it sends, how it maps the server's
/// refusals, how it reads the answer. No live traffic: every call lands on a
/// stub adapter.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:lupin_mobile/features/settings/data/heartbeat_poke_repository.dart';

import '../_helpers/stub_dio.dart';

void main() {
  late StubAdapter              adapter;
  late HeartbeatPokeRepository  repo;

  const getKey = "GET /api/heartbeat/poke-mute";
  const putKey = "PUT /api/heartbeat/poke-mute";

  void stub( String key, { int status = 200, dynamic body = const { "muted": false } } ) {
    adapter = StubAdapter( { key: ( _ ) => jsonBody( body, status: status ) } );
    repo    = HeartbeatPokeRepository( makeDio( adapter ) );
  }

  group( 'requests', () {
    test( 'getState is a GET on the poke-mute path', () async {
      stub( getKey );
      await repo.getState();
      expect( adapter.captured.single.method, "GET" );
      expect( adapter.captured.single.path, "/api/heartbeat/poke-mute" );
    } );

    for ( final muted in [ true, false ] ) {
      test( 'setMuted( $muted ) PUTs exactly { muted: $muted }, a JSON boolean', () async {
        stub( putKey, body: { "muted": muted } );
        await repo.setMuted( muted );
        expect( adapter.captured.single.method, "PUT" );
        expect( adapter.captured.single.path, "/api/heartbeat/poke-mute" );
        expect( adapter.captured.single.data, { "muted": muted } );
        expect( ( adapter.captured.single.data as Map )["muted"], isA<bool>() );
      } );
    }

    test( 'setMuted returns the state the server answered with, not the one asked for', () async {
      stub( putKey, body: { "muted": false, "set_by": "rick", "set_at": "2026-10-02T15:00:00+00:00" } );
      final s = await repo.setMuted( true );
      expect( s.muted, isFalse );
      expect( s.setBy, "rick" );
    } );
  } );

  group( 'error mapping', () {
    for ( final c in [ 401, 403, 422, 500 ] ) {
      test( '$c on a write becomes a HeartbeatPokeException carrying $c', () async {
        stub( putKey, status: c, body: { "detail": "server said $c" } );
        await expectLater(
          repo.setMuted( true ),
          throwsA( isA<HeartbeatPokeException>()
              .having( ( e ) => e.statusCode, 'statusCode', c )
              .having( ( e ) => e.message, 'message', "server said $c" ) ),
        );
      } );
    }

    test( 'only 403 is admin-only', () {
      expect( const HeartbeatPokeException( "x", statusCode: 403 ).isAdminOnly, isTrue );
      expect( const HeartbeatPokeException( "x", statusCode: 401 ).isAdminOnly, isFalse );
      expect( const HeartbeatPokeException( "x", statusCode: 422 ).isAdminOnly, isFalse );
      expect( const HeartbeatPokeException( "x" ).isAdminOnly, isFalse );
    } );

    test( 'a failed read carries the status too', () async {
      stub( getKey, status: 500, body: { "detail": "boom" } );
      await expectLater( repo.getState(),
          throwsA( isA<HeartbeatPokeException>().having( ( e ) => e.statusCode, 'sc', 500 ) ) );
    } );

    test( 'a body with no detail falls back to a local message', () async {
      stub( putKey, status: 500, body: { "other": 1 } );
      await expectLater( repo.setMuted( true ),
          throwsA( isA<HeartbeatPokeException>()
              .having( ( e ) => e.message, 'message', "Could not change the stop poke switch" ) ) );
    } );
  } );

  group( 'reading the answer', () {
    test( 'the full shape', () {
      final s = HeartbeatPokeState.fromJson(
          { "muted": true, "set_by": "rick", "set_at": "2026-10-02T15:00:00+00:00" } );
      expect( s.muted, isTrue );
      expect( s.setBy, "rick" );
      expect( s.setAt!.isAtSameMomentAs( DateTime.utc( 2026, 10, 2, 15 ) ), isTrue );
      expect( s.setAt!.isUtc, isFalse );
    } );

    test( 'nulls for a switch nobody has flipped', () {
      final s = HeartbeatPokeState.fromJson( { "muted": false, "set_by": null, "set_at": null } );
      expect( s.muted, isFalse );
      expect( s.setBy, isNull );
      expect( s.setAt, isNull );
    } );

    test( 'anything but a JSON true reads as not muted', () {
      for ( final v in [ "true", 1, null, "yes" ] ) {
        expect( HeartbeatPokeState.fromJson( { "muted": v } ).muted, isFalse, reason: "$v" );
      }
      expect( HeartbeatPokeState.fromJson( {} ).muted, isFalse );
    } );

    test( 'an unparseable set_at reads as null', () {
      expect( HeartbeatPokeState.fromJson( { "muted": true, "set_at": "soon" } ).setAt, isNull );
    } );
  } );
}
