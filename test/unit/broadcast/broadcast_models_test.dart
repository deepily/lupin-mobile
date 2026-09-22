import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/broadcast/data/broadcast_models.dart';

/// Phase 5 data layer.
///
/// Every test here is aimed at a defect this row has actually carried, not at the happy
/// path. The fixtures are real where they could be — see
/// `test/fixtures/commons/README-broadcast.md`, which labels each file captured or
/// transcribed, because a transcription trusted as a capture is its own failure mode.
void main() {
  Map<String, dynamic> fixture( String name ) =>
      jsonDecode( File( 'test/fixtures/commons/$name' ).readAsStringSync() )
          as Map<String, dynamic>;

  group( 'ActiveSessionRoster — the Send button reads this count', () {
    test( 'reads the live capture, and the COUNT is what it was on the wire', () {
      final roster = ActiveSessionRoster.fromJson( fixture( 'active_sessions.json' ) );

      // 🔴 THREE IS NOT A MAGIC NUMBER — it is how many sessions were live when the
      // capture ran, and the redactor is forbidden from changing it precisely because
      // this assertion exists. If someone "tidies" the fixture, this fails.
      expect( roster.count, 3 );
      expect( roster.isEmpty, isFalse );
      expect(
        roster.sessions.map( ( s ) => s.personaName ),
        containsAll( <String>[ 'Tiffany', 'maria', 'mr radio' ] ),
      );
    });

    test( 'an EMPTY fleet is an answer, not an exception', () {
      // Nobody online at 3am is the ordinary state and the exact case the Send button's
      // second condition exists for. A throw here would turn it into a failure banner.
      expect( ActiveSessionRoster.fromJson( const {} ).isEmpty, isTrue );
      expect( ActiveSessionRoster.fromJson( const { 'sessions' : [] } ).count, 0 );
      expect( ActiveSessionRoster.fromJson( const { 'sessions' : null } ).count, 0 );
    });

    test( 'a session missing its persona keeps the absence as null, not a placeholder', () {
      final roster = ActiveSessionRoster.fromJson( const {
        'sessions' : [ { 'session_id' : 'sess-1' } ],
      } );

      expect( roster.sessions.single.personaName, isNull );
      // The chip falls back to something renderable rather than the word "null".
      expect( roster.sessions.single.label, 'sess-1' );
    });
  });

  group( '🔴 BroadcastAck — the ack is in `payload`, and `message` is empty BY DESIGN', () {
    test( 'reads the producer-shaped frame', () {
      final frame = fixture( 'broadcast_ack_frame.json' );
      final notif = Map<String, dynamic>.from( frame[ 'notification' ] as Map );

      final ack = BroadcastAck.fromNotification( notif );

      expect( ack, isNotNull );
      expect( ack!.broadcastId, 'b-fixture-0001' );
      expect( ack.sessionId,    'sess-fixture-1' );
      expect( ack.personaName,  'maria' );
      expect( ack.status,       'acked' );
      expect( ack.bodySummary,  'On it — picking this up now.' );
    });

    test( '🔴 an EMPTY `message` does not make the ack empty — this is THE trap', () {
      final frame = fixture( 'broadcast_ack_frame.json' );
      final notif = Map<String, dynamic>.from( frame[ 'notification' ] as Map );

      // Every other notification in this app carries its content in `message`. This one
      // carries "" there by design, and a reader that trusts that habit sees a stream of
      // blank notifications, reports zero acks, and renders what looks like a fleet that
      // ignored the operator.
      expect( notif[ 'message' ], '' );
      expect( BroadcastAck.fromNotification( notif )!.bodySummary, isNotEmpty );
    });

    test( 'a frame of the wrong type is not an ack', () {
      expect(
        BroadcastAck.fromNotification( const { 'type' : 'task', 'payload' : { 'broadcast_id' : 'b1' } } ),
        isNull,
      );
    });

    test( 'a malformed frame is dropped, not fatal', () {
      // A socket frame is untrusted input arriving at arbitrary times; throwing here
      // would take down the stream for every other pane sharing it.
      for ( final bad in <Map<String, dynamic>>[
        { 'type' : 'commons_broadcast_ack' },
        { 'type' : 'commons_broadcast_ack', 'payload' : 'not-a-map' },
        { 'type' : 'commons_broadcast_ack', 'payload' : <String, dynamic>{} },
        { 'type' : 'commons_broadcast_ack', 'payload' : { 'broadcast_id' : '' } },
      ] ) {
        expect( BroadcastAck.fromNotification( bad ), isNull, reason: '$bad' );
      }
    });
  });

  group( '🔴 AckAggregate — the acceptance clause, in executable form', () {
    AckAggregate seeded() => const AckAggregate(
      broadcastId      : 'b1',
      recipientsAtSend : 14,
    );

    BroadcastAck ackFrom( String session ) =>
        BroadcastAck( broadcastId: 'b1', sessionId: session, personaName: session );

    test( 'folding is idempotent per session — a duplicate frame is not a second ack', () {
      final agg = seeded().fold( ackFrom( 's1' ) ).fold( ackFrom( 's1' ) );
      expect( agg.ackedCount, 1 );
    });

    test( 'an ack for another broadcast is ignored', () {
      final agg = seeded().fold(
        const BroadcastAck( broadcastId: 'OTHER', sessionId: 's9' ),
      );
      expect( agg.ackedCount, 0 );
    });

    test( 'while observed, the tally reads as an exact fraction', () {
      final agg = seeded().fold( ackFrom( 's1' ) ).fold( ackFrom( 's2' ) );
      expect( agg.summary, '2 of 14 acked' );
    });

    test( '🔴 once interrupted, the summary NEVER presents a denominator', () {
      final agg = seeded().fold( ackFrom( 's1' ) ).fold( ackFrom( 's2' ) ).interrupted();

      // This is the precise-looking lie the whole phase was written around. "2 of 14"
      // after a resume reads as twelve seats ignoring the operator; what actually
      // happened is that the phone was not listening.
      expect( agg.summary, isNot( contains( ' of 14' ) ) );
      expect( agg.summary, contains( 'At least 2' ) );
      expect( agg.summary, contains( 'could not be confirmed' ) );
    });

    test( '🔴 the wording is about THIS ATTEMPT, never about the world', () {
      final agg = seeded().interrupted();

      // Settled on store row 384591dd after the clause went through three wrong shapes.
      // "Acks are unavailable by design" becomes a silent lie the day the two stores are
      // bridged; "could not be confirmed" simply stops firing. A pane outlives the
      // condition that made its sentence true.
      expect( agg.summary, contains( 'could not be confirmed' ) );
      expect( agg.summary.toLowerCase(), isNot( contains( 'by design' ) ) );
      expect( agg.summary.toLowerCase(), isNot( contains( 'unavailable' ) ) );
    });

    test( '🔴 a LATER ack does not restore confidence', () {
      // An ack arriving after a reconnect proves the socket is back. It proves nothing
      // about the acks pushed while it was down, and those are not recoverable — they
      // are absent from /api/notifications/undelivered, and the io_tbl row written for
      // an ack never receives `payload` at all. Letting a late arrival clear the flag
      // would quietly re-manufacture the false precision this type prevents.
      final agg = seeded().interrupted().fold( ackFrom( 's3' ) );

      expect( agg.confidence, AckConfidence.interrupted );
      expect( agg.ackedCount, 1 );
      expect( agg.summary, contains( 'could not be confirmed' ) );
    });

    test( 'interrupted with zero acks says so without implying silence from the fleet', () {
      expect(
        seeded().interrupted().summary,
        'Acks could not be confirmed — the app was not listening for part of this broadcast.',
      );
    });
  });

  group( 'BroadcastSendResult — `queued` is not a delivery receipt', () {
    test( 'reads the queued shape', () {
      final r = BroadcastSendResult.fromJson( fixture( 'broadcast_send_queued.json' ) );

      expect( r.broadcastId,      'b-fixture-0001' );
      expect( r.recipients,       3 );
      expect( r.status,           'queued' );
      expect( r.noActiveSessions, isFalse );
      expect( r.hasFailures,      isFalse );
    });

    test( 'no-active-sessions is distinguishable from a failure', () {
      final r = BroadcastSendResult.fromJson( fixture( 'broadcast_send_no_sessions.json' ) );

      // The request was ACCEPTED and simply had no addressees. Collapsing this into an
      // error would tell the operator to retype a message the server already took.
      expect( r.noActiveSessions, isTrue );
      expect( r.recipients,       0 );
      expect( r.hasFailures,      isFalse );
    });

    test( '🔴 failed recipients are surfaced, because `queued` alone would hide them', () {
      final r = BroadcastSendResult.fromJson( const {
        'broadcast_id'      : 'b1',
        'recipients'        : 2,
        'failed_recipients' : [ 'sess-9' ],
        'status'            : 'queued',
      } );

      // Same shape as the 202 sentinel on the task panes: a status that says accepted,
      // read as a status that says delivered.
      expect( r.status,      'queued' );
      expect( r.hasFailures, isTrue );
    });
  });
}
