import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/broadcast/data/broadcast_repository.dart';

import '../_helpers/stub_dio.dart';

/// The three doors, and what this pane must never ask them for.
void main() {
  late StubAdapter adapter;
  late BroadcastRepository repo;

  dynamic fixture( String name ) =>
      jsonDecode( File( 'test/fixtures/commons/$name' ).readAsStringSync() );

  setUp( () {
    adapter = StubAdapter();
    repo    = BroadcastRepository( makeDio( adapter ) );
  } );

  group( 'active sessions', () {
    test( 'reads the roster', () async {
      adapter.handlers[ 'GET ${BroadcastRepository.activeSessionsPath}' ] =
          ( _ ) => jsonBody( fixture( 'active_sessions.json' ) );

      expect( ( await repo.fetchActiveSessions() ).count, 3 );
    } );

    test( 'a transport failure is translated, not leaked as a DioException', () async {
      adapter.handlers[ 'GET ${BroadcastRepository.activeSessionsPath}' ] =
          ( _ ) => jsonBody( { 'detail' : 'boom' }, status: 500 );

      expect( repo.fetchActiveSessions(), throwsA( isA<BroadcastException>() ) );
    } );

    test( 'a CANCELLATION propagates untranslated, so the bloc can stay quiet', () async {
      // The lifecycle rule working is not a failure. Wrapping it in BroadcastException
      // would make every backgrounding paint an error banner on resume.
      final token = CancelToken();
      adapter.handlers[ 'GET ${BroadcastRepository.activeSessionsPath}' ] = ( _ ) {
        token.cancel();
        return jsonBody( const <String, dynamic>{} );
      };

      try {
        await repo.fetchActiveSessions( cancelToken: token );
      } catch ( e ) {
        expect( e, isNot( isA<BroadcastException>() ) );
      }
    } );
  } );

  group( '🔴 send — the two flags are NAMED, and a 429 is its own thing', () {
    test( 'sends require_ack and include_originator EXPLICITLY', () async {
      adapter.handlers[ 'POST ${BroadcastRepository.broadcastPath}' ] =
          ( _ ) => jsonBody( fixture( 'broadcast_send_queued.json' ) );

      await repo.send( message: 'all hands' );

      final body = adapter.captured.last.data as Map<String, dynamic>;
      // 🔴 NOT LEFT TO THE SERVER'S DEFAULTS. Both default to true server-side today;
      // if either default moves, a pane that omitted them changes behaviour silently and
      // the ack tally starts counting a different set of seats.
      expect( body[ 'require_ack' ],        isTrue );
      expect( body[ 'include_originator' ], isTrue );
      expect( body[ 'message' ],            'all hands' );
    } );

    test( 'omits broadcast_id when the caller did not supply one', () async {
      adapter.handlers[ 'POST ${BroadcastRepository.broadcastPath}' ] =
          ( _ ) => jsonBody( fixture( 'broadcast_send_queued.json' ) );

      await repo.send( message: 'x' );

      // The server mints one. Sending an explicit null would be a 409 collision magnet.
      expect(
        ( adapter.captured.last.data as Map<String, dynamic> ).containsKey( 'broadcast_id' ),
        isFalse,
      );
    } );

    test( '🔴 a 429 becomes BroadcastRateLimited, carrying Retry-After', () async {
      adapter.handlers[ 'POST ${BroadcastRepository.broadcastPath}' ] = ( _ ) =>
          ResponseBody.fromString(
            jsonEncode( { 'detail' : 'rate limit exceeded' } ),
            429,
            headers : {
              Headers.contentTypeHeader : [ Headers.jsonContentType ],
              'retry-after'             : [ '31' ],
            },
          );

      // "Slow down for 31 seconds" and "that did not send" call for different words on
      // screen. Collapsing them tells the operator to retype a message the server has.
      await expectLater(
        repo.send( message: 'x' ),
        throwsA( isA<BroadcastRateLimited>()
            .having( ( e ) => e.retryAfterSeconds, 'retryAfter', 31 ) ),
      );
    } );

    test( 'other errors stay BroadcastException', () async {
      adapter.handlers[ 'POST ${BroadcastRepository.broadcastPath}' ] =
          ( _ ) => jsonBody( { 'detail' : 'nope' }, status: 400 );

      expect( repo.send( message: 'x' ), throwsA( isA<BroadcastException>() ) );
    } );
  } );

  group( 'history', () {
    test( '🔴 asks for an EXPLICIT limit — the server default is 200', () async {
      adapter.handlers[ 'GET ${BroadcastRepository.historyPath}' ] =
          ( _ ) => jsonBody( fixture( 'broadcast_history.json' ) );

      await repo.fetchHistory();

      // Taking the default pulls 200 rows of live fleet traffic over a phone link to
      // render five. Measured while capturing the fixture: 144 KB.
      expect( adapter.captured.last.path, contains( 'limit=5' ) );
    } );

    test( 'a kill-switched endpoint is EMPTY, not an error', () async {
      adapter.handlers[ 'GET ${BroadcastRepository.historyPath}' ] =
          ( _ ) => jsonBody( fixture( 'broadcast_history_disabled.json' ) );

      // A feature the operator turned off is not a fault, and an error banner would
      // invite someone to go looking for a break that does not exist. Nor is it "no
      // activity" — the flag carries the difference to the pane (row a3ebeb18).
      final read = await repo.fetchHistory();
      expect( read.entries,  isEmpty );
      expect( read.disabled, isTrue );
    } );

    test( '🔴 an ABSENT `disabled` key reads as ENABLED', () async {
      adapter.handlers[ 'GET ${BroadcastRepository.historyPath}' ] =
          ( _ ) => jsonBody( fixture( 'broadcast_history.json' ) );

      // This is how the live endpoint actually answers — the key exists ONLY in the
      // disabled branch. A reader that required it would treat every healthy response
      // as malformed. Verified against the live capture, which carries no such key.
      expect(
        ( fixture( 'broadcast_history.json' ) as Map ).containsKey( 'disabled' ),
        isFalse,
      );
      final read = await repo.fetchHistory();
      expect( read.entries,  isNotEmpty );
      expect( read.disabled, isFalse );
    } );
  } );

  group( '🔴 the recovery read that must not exist', () {
    test( 'drainMissedAcks REFUSES rather than quietly returning nothing', () {
      // The plan specified draining /api/notifications/undelivered on resume. That drain
      // cannot return an ack: commons_broadcast_ack is pushed in-process and never
      // crosses the notify_user route where _persist_notification_sync lives, and the
      // io_tbl row it DOES produce never receives `payload` at all.
      //
      // ⇒ A drain implemented here would have run, returned nothing, folded nothing, and
      // left every test green while recovering zero acks. The refusal is the only
      // version that cannot be mistaken for working.
      expect( () => repo.drainMissedAcks(), throwsA( isA<UnsupportedError>() ) );
    } );
  } );
}
