/// The server push-pause client (row 67ee93b0): what it sends, how it maps the
/// server's refusals, how it reads `resumes_at`. No live traffic: every call
/// lands on a stub adapter.
library;

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lupin_mobile/features/settings/data/push_pause_repository.dart';

import '../_helpers/stub_dio.dart';

void main() {
  late StubAdapter          adapter;
  late PushPauseRepository  repo;

  const key = "POST /api/fcm/push-pause";

  void stubPost( { int status = 200, dynamic body = const {} } ) {
    adapter = StubAdapter( { key: ( _ ) => jsonBody( body, status: status ) } );
    repo    = PushPauseRepository( makeDio( adapter ) );
  }

  group( 'request bodies', () {
    test( 'pause with minutes sends paused + minutes', () async {
      stubPost();
      await repo.pause( minutes: 120 );
      expect( adapter.captured.single.data, { "paused": true, "minutes": 120 } );
    } );

    test( 'pause with minutes left out omits the field entirely', () async {
      stubPost();
      await repo.pause();
      expect( adapter.captured.single.data, { "paused": true } );
      expect( ( adapter.captured.single.data as Map ).containsKey( "minutes" ), isFalse );
    } );

    test( 'resume sends only paused:false', () async {
      stubPost();
      await repo.resume();
      expect( adapter.captured.single.data, { "paused": false } );
    } );

    test( 'every write goes to the push-pause path', () async {
      stubPost();
      await repo.pause( minutes: 30 );
      expect( adapter.captured.single.path, "/api/fcm/push-pause" );
      expect( adapter.captured.single.method, "POST" );
    } );
  } );

  group( 'error mapping', () {
    for ( final c in [ 400, 401, 403 ] ) {
      test( '$c on pause becomes a PushPauseException carrying $c', () async {
        stubPost( status: c, body: { "detail": "server said $c" } );
        await expectLater(
          repo.pause( minutes: 5 ),
          throwsA( isA<PushPauseException>()
              .having( ( e ) => e.statusCode, 'statusCode', c )
              .having( ( e ) => e.message, 'message', "server said $c" ) ),
        );
      } );
    }

    test( 'only 403 is admin-only', () {
      expect( const PushPauseException( "x", statusCode: 403 ).isAdminOnly, isTrue );
      expect( const PushPauseException( "x", statusCode: 401 ).isAdminOnly, isFalse );
      expect( const PushPauseException( "x", statusCode: 400 ).isAdminOnly, isFalse );
      expect( const PushPauseException( "x" ).isAdminOnly, isFalse );
    } );

    test( '403 on resume and on GET map the same way', () async {
      adapter = StubAdapter( {
        key                        : ( _ ) => jsonBody( { "detail": "no" }, status: 403 ),
        "GET /api/fcm/push-pause"  : ( _ ) => jsonBody( { "detail": "no" }, status: 403 ),
      } );
      repo = PushPauseRepository( makeDio( adapter ) );
      await expectLater( repo.resume(),
          throwsA( isA<PushPauseException>().having( ( e ) => e.isAdminOnly, 'admin', true ) ) );
      await expectLater( repo.getState(),
          throwsA( isA<PushPauseException>().having( ( e ) => e.isAdminOnly, 'admin', true ) ) );
    } );

    test( 'a non-JSON error body falls back to the Dio message', () async {
      adapter = StubAdapter( { key: ( _ ) => ResponseBody.fromString( "boom", 500 ) } );
      repo    = PushPauseRepository( makeDio( adapter ) );
      await expectLater( repo.pause(),
          throwsA( isA<PushPauseException>().having( ( e ) => e.statusCode, 'sc', 500 ) ) );
    } );
  } );

  group( 'GET parsing', () {
    test( 'reads every field and turns resumes_at into a DateTime', () async {
      adapter = StubAdapter( { "GET /api/fcm/push-pause": ( _ ) => jsonBody( {
        "paused"       : true,
        "resumes_at"   : "2026-09-29T23:45:00+00:00",
        "set_by"       : "rick",
        "set_at"       : "2026-09-29T21:45:00+00:00",
        "push_enabled" : false,
      } ) } );
      repo = PushPauseRepository( makeDio( adapter ) );
      final s = await repo.getState();
      expect( s.paused, isTrue );
      expect( s.resumesAt!.toUtc(), DateTime.utc( 2026, 9, 29, 23, 45 ) );
      expect( s.setAt!.toUtc(),     DateTime.utc( 2026, 9, 29, 21, 45 ) );
      expect( s.setBy, "rick" );
      expect( s.pushEnabled, isFalse );
    } );

    test( 'null resumes_at means paused until resumed', () async {
      adapter = StubAdapter( { "GET /api/fcm/push-pause": ( _ ) => jsonBody( {
        "paused": true, "resumes_at": null, "set_by": "rick", "set_at": null, "push_enabled": false,
      } ) } );
      repo = PushPauseRepository( makeDio( adapter ) );
      final s = await repo.getState();
      expect( s.paused, isTrue );
      expect( s.resumesAt, isNull );
    } );

    test( 'not paused parses with no timestamps', () {
      final s = PushPauseState.fromJson( { "paused": false, "resumes_at": null, "push_enabled": true } );
      expect( s.paused, isFalse );
      expect( s.resumesAt, isNull );
    } );

    test( 'an unparseable resumes_at becomes null instead of throwing', () {
      expect( PushPauseState.fromJson( { "paused": true, "resumes_at": "soon" } ).resumesAt, isNull );
    } );
  } );
}
