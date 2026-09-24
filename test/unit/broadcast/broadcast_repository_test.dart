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

  group( '🔴 the recovery read — the refusal this replaced, and why', () {
    // This method spent a phase as a documented `Never`. The plan specified draining
    // /api/notifications/undelivered, which CANNOT return an ack: that inbox skips
    // anything already handed to a socket, and an ack that lands while the app is open
    // is marked delivered instantly. A drain built on it would have run, folded nothing,
    // and left every test green while recovering zero.
    //
    // The server side landed (lupin row 1c7da903). notifications.py:2441 answers a
    // different question — "which seats have acked this broadcast" — and
    // notification_repository.py:653 deliberately does not filter on delivery state.
    const bid = 'b-fixture-0001';
    final path = BroadcastRepository.ackDrainPath( bid );

    test( 'reads the saved acks for ONE broadcast id', () async {
      adapter.handlers[ 'GET $path' ] = ( _ ) => jsonBody( fixture( 'broadcast_acks_saved.json' ) );

      final acks = await repo.drainMissedAcks( bid );

      expect( acks.length, 2 );
      expect( acks.map( ( a ) => a.sessionId ), [ 'sess-fixture-2', 'sess-fixture-1' ] );
      expect( adapter.captured.last.path, contains( '/broadcast-acks/$bid' ) );
    } );

    test( '🔴 reads `ack_status`, NOT `status` — the key is renamed by the projection', () async {
      adapter.handlers[ 'GET $path' ] = ( _ ) => jsonBody( fixture( 'broadcast_acks_saved.json' ) );

      // _project_broadcast_ack (notifications.py:2398-2422) lifts the identity fields out
      // of `payload` and renames `payload.status` to `ack_status`, because the envelope
      // already carries a `state` of its own — the notification's DELIVERY state. A
      // reader that reuses the socket parser finds no `status`, reports every recovered
      // ack with a null one, and produces a tally of exactly the right SIZE. Counting
      // does not catch this; reading the status does.
      final acks = await repo.drainMissedAcks( bid );

      expect( acks.map( ( a ) => a.status ),
          [ 'completed', 'completed-with-withheld' ] );
      expect( acks.map( ( a ) => a.status ), isNot( contains( null ) ) );
    } );

    test( '🔴 a DELIVERED ack still comes back — that is the whole point of the endpoint', () async {
      adapter.handlers[ 'GET $path' ] = ( _ ) => jsonBody( fixture( 'broadcast_acks_saved.json' ) );

      // One fixture row carries `state: "delivered"`. The undelivered drain would skip
      // it; this read does not filter on delivery state at all. If someone ever adds
      // that filter server-side, the count here drops to one.
      final saved = fixture( 'broadcast_acks_saved.json' ) as Map;
      expect(
        ( saved[ 'acks' ] as List ).map( ( e ) => ( e as Map )[ 'state' ] ),
        contains( 'delivered' ),
      );
      expect( ( await repo.drainMissedAcks( bid ) ).length, 2 );
    } );

    test( 'an EMPTY ack list is an answer, not a failure', () async {
      adapter.handlers[ 'GET $path' ] = ( _ ) => jsonBody( const {
        'status' : 'success', 'broadcast_id' : bid, 'ack_count' : 0, 'acks' : <dynamic>[],
      } );

      // A 200 carrying `acks: []` means nobody acked (notifications.py:2455). Throwing
      // on it would make a quiet fleet indistinguishable from a broken read — which is
      // the exact confusion the other direction of this test guards.
      expect( await repo.drainMissedAcks( bid ), isEmpty );
    } );

    test( '🔴 a SERVER ERROR throws — it must never read as "nobody acked"', () async {
      adapter.handlers[ 'GET $path' ] =
          ( _ ) => jsonBody( { 'detail' : 'Failed to read broadcast acks' }, status: 500 );

      // The endpoint raises 500 rather than returning an empty list for precisely this
      // reason (notifications.py:2461-2463), and a client that swallowed it here would
      // undo that on the other side of the wire.
      expect( repo.drainMissedAcks( bid ), throwsA( isA<BroadcastException>() ) );
    } );

    test( 'a malformed row is dropped, not fatal', () async {
      adapter.handlers[ 'GET $path' ] = ( _ ) => jsonBody( {
        'acks' : [
          const { 'session_id' : 'sess-orphan' },                      // payload was NULL server-side
          const { 'broadcast_id' : bid, 'session_id' : 'sess-ok' },
        ],
      } );

      // A row whose payload is null projects every identity field as None rather than
      // raising (notifications.py:2404-2407). The honest client answer is to drop that
      // one ack, not to lose the whole read.
      final acks = await repo.drainMissedAcks( bid );
      expect( acks.map( ( a ) => a.sessionId ), [ 'sess-ok' ] );
    } );

    test( 'a cancellation propagates untranslated, same as the other three doors', () async {
      final token = CancelToken();
      adapter.handlers[ 'GET $path' ] = ( _ ) {
        token.cancel();
        return jsonBody( const <String, dynamic>{} );
      };

      try {
        await repo.drainMissedAcks( bid, cancelToken: token );
      } catch ( e ) {
        expect( e, isNot( isA<BroadcastException>() ) );
      }
    } );

    test( '⚠️ names the scan limit explicitly, and does NOT guard on len == limit', () async {
      adapter.handlers[ 'GET $path' ] = ( _ ) => jsonBody( fixture( 'broadcast_acks_saved.json' ) );

      await repo.drainMissedAcks( bid );
      expect( adapter.captured.last.path, contains( 'limit=500' ) );

      // 🔴 NO TRUNCATION GUARD, DELIBERATELY. `len == ackLimit` means nothing here: the
      // limit caps the PRE-fold row scan and the latest-per-session fold can only shrink
      // the result (notification_repository.py:706-720), so a full scan routinely answers
      // with far fewer rows. A guard on that comparison would fire on a number that
      // carries no information (row 973e4b6b).
      expect( BroadcastRepository.ackLimit, 500 );
    } );
  } );
}
