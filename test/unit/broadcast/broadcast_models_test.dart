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

  group( '🔴 the recovery read, folded — per-broadcast identity and latest-wins', () {
    final sentAt = DateTime.utc( 2026, 9, 23, 16, 30 );

    AckAggregate seeded( { AckConfidence confidence = AckConfidence.observed } ) {
      final base = AckAggregate(
        broadcastId      : 'b-fixture-0001',
        recipientsAtSend : 3,
        sentAt           : sentAt,
      );
      return confidence == AckConfidence.interrupted ? base.interrupted() : base;
    }

    List<BroadcastAck> savedAcks() =>
        ( fixture( 'broadcast_acks_saved.json' )[ 'acks' ] as List )
            .map( ( e ) => BroadcastAck.fromSavedAck( Map<String, dynamic>.from( e as Map ) )! )
            .toList();

    test( 'reads the projected shape, ack_status and all', () {
      final acks = savedAcks();

      expect( acks.first.sessionId,   'sess-fixture-2' );
      expect( acks.first.personaName, 'tiffany' );
      expect( acks.first.status,      'completed' );
      expect( acks.first.bodySummary, 'Read it — merging after the suite.' );
      expect( acks.first.createdAt,   isNotNull );
    });

    test( 'a row with no broadcast_id is dropped rather than folded as a blank', () {
      expect( BroadcastAck.fromSavedAck( const { 'session_id' : 's1' } ), isNull );
      expect( BroadcastAck.fromSavedAck( const { 'broadcast_id' : '', 'session_id' : 's1' } ), isNull );
    });

    test( '🔴 acks for ANOTHER broadcast_id are ignored — the acceptance guard', () {
      // One client, one socket, many broadcasts. The saved read is scoped by id
      // server-side, but the aggregate must not depend on that: a pane holding
      // broadcast A while a read for B lands is a tally that silently counts strangers.
      final agg = seeded().reconciled( const [
        BroadcastAck( broadcastId: 'b-SOMEONE-ELSE', sessionId: 's9', personaName: 'cheech' ),
        BroadcastAck( broadcastId: 'b-fixture-0001', sessionId: 's1', personaName: 'sam' ),
      ] );

      expect( agg.ackedCount, 1 );
      expect( agg.acks.single.sessionId, 's1' );
    });

    test( '🔴 a seat already counted LIVE is not counted twice', () {
      // The recovery read returns every ack the broadcast has, including the ones this
      // client watched arrive. Appending rather than keying per seat would double the
      // tally of a broadcast that was fully observed and then merely resumed.
      final live = seeded().fold( const BroadcastAck(
        broadcastId: 'b-fixture-0001', sessionId: 'sess-fixture-1', personaName: 'maria',
      ) );
      expect( live.ackedCount, 1 );

      final merged = live.reconciled( savedAcks() );
      expect( merged.ackedCount, 2 );
      expect( merged.acks.map( ( a ) => a.sessionId ),
          containsAll( <String>[ 'sess-fixture-1', 'sess-fixture-2' ] ) );
    });

    test( '🔴 a seat\'s LATEST ack wins — the saved row replaces the live one', () {
      // A seat acks `pending` and later `completed`; the server folds to the latest
      // before the rows leave it (notification_repository.py:706-720). Keeping the live
      // frame instead would show a stale status beside a current count — the count is
      // right either way, which is why this needs asserting on the STATUS.
      final live = seeded().fold( const BroadcastAck(
        broadcastId : 'b-fixture-0001',
        sessionId   : 'sess-fixture-1',
        personaName : 'maria',
        status      : 'pending',
        bodySummary : '',
      ) );
      expect( live.acks.single.status, 'pending' );

      final merged = live.reconciled( savedAcks() );
      final maria  = merged.acksBySession[ 'sess-fixture-1' ]!;

      expect( maria.status,      'completed-with-withheld' );
      expect( maria.bodySummary, 'On it — picking this up now.' );
      expect( merged.ackedCount, 2 );
    });

    test( 'a seat the read does NOT name keeps what we saw live', () {
      // The read can race a frame. Dropping it would be a recovery that loses acks.
      final live = seeded().fold( const BroadcastAck(
        broadcastId: 'b-fixture-0001', sessionId: 'sess-late', personaName: 'sam',
      ) );

      expect( live.reconciled( savedAcks() ).acksBySession.containsKey( 'sess-late' ), isTrue );
    });

    test( '🔴 keepLive is the ONE exception to saved-wins — a seat that moved mid-read', () {
      // "The saved row is the latest" holds as of the moment the server answered, and a
      // network read is not instant. A seat that acks while the read is in flight lands
      // a frame newer than anything the response can carry.
      final live = seeded().fold( const BroadcastAck(
        broadcastId : 'b-fixture-0001',
        sessionId   : 'sess-fixture-1',
        status      : 'completed-while-you-were-asking',
      ) );

      final merged = live.reconciled( savedAcks(), keepLive: { 'sess-fixture-1' } );

      expect( merged.acksBySession[ 'sess-fixture-1' ]?.status,
          'completed-while-you-were-asking' );
      // Only that seat is exempt. The rest of the response still lands, or the exception
      // would quietly become a refusal of the whole read.
      expect( merged.acksBySession[ 'sess-fixture-2' ]?.status, 'completed' );
      expect( merged.ackedCount, 2 );
    });

    test( '🔴 a successful read RETIRES the interrupted state', () {
      final agg = seeded( confidence: AckConfidence.interrupted ).reconciled( savedAcks() );

      // The comment that said this was permanent was written about
      // /api/notifications/undelivered and was true of it. It stopped being true when
      // notifications.py:2441 landed.
      expect( agg.confidence, AckConfidence.recovered );
      expect( agg.summaryAt( sentAt ), isNot( contains( 'could not be confirmed' ) ) );
    });

    test( 'an EMPTY read still retires it — "nobody acked" is an answer the server gave', () {
      final agg = seeded( confidence: AckConfidence.interrupted ).reconciled( const [] );

      expect( agg.confidence, AckConfidence.recovered );
      expect( agg.ackedCount, 0 );
    });

    test( 'an already-observed tally is NOT demoted to a claim about a past moment', () {
      expect( seeded().reconciled( savedAcks() ).confidence, AckConfidence.observed );
    });
  });

  group( '🔴 expired vs partial — two different instructions to the operator', () {
    final sentAt = DateTime.utc( 2026, 9, 23, 16, 30 );

    AckAggregate withAcks( int n, { int recipients = 3 } ) {
      var agg = AckAggregate(
        broadcastId      : 'b1',
        recipientsAtSend : recipients,
        sentAt           : sentAt,
      );
      for ( var i = 0; i < n; i++ ) {
        agg = agg.fold( BroadcastAck( broadcastId: 'b1', sessionId: 's$i' ) );
      }
      return agg;
    }

    final inside = sentAt.add( const Duration( minutes: 4 ) );
    final after  = sentAt.add( const Duration( minutes: 6 ) );

    test( 'inside the window, a short tally is PARTIAL — more may still be coming', () {
      expect( withAcks( 1 ).outcomeAt( inside ), AckOutcome.partial );
    });

    test( '🔴 past the window, a short tally is EXPIRED — go chase somebody', () {
      expect( withAcks( 1 ).outcomeAt( after ), AckOutcome.expired );
      expect( withAcks( 1 ).summaryAt( after ), '1 of 3 acked — 2 did not answer in time.' );
    });

    test( 'every seat acked is COMPLETE, window or no window', () {
      expect( withAcks( 3 ).outcomeAt( inside ), AckOutcome.complete );
      expect( withAcks( 3 ).outcomeAt( after ),  AckOutcome.complete );
    });

    test( '🔴 an UNKNOWN send time is never treated as an elapsed one', () {
      // sentAt is null for any aggregate built without one. Defaulting an absent clock
      // to "long ago" would declare a broadcast expired the instant it was restored from
      // anywhere that did not carry the timestamp.
      const noClock = AckAggregate( broadcastId: 'b1', recipientsAtSend: 3 );

      expect( noClock.outcomeAt( DateTime.utc( 2030 ) ), AckOutcome.partial );
      expect( noClock.summary, '0 of 3 acked' );
    });

    test( '🔴 an INTERRUPTED tally is never described as complete, whatever the counts', () {
      // A floor that happens to reach the denominator is still a floor: those three acks
      // may be three of nine, with the six we did not see pushed at a dead socket.
      final agg = withAcks( 3 ).interrupted();

      expect( agg.summaryAt( after ), contains( 'could not be confirmed' ) );
      expect( agg.summaryAt( after ).toLowerCase(), isNot( contains( 'all ' ) ) );
      expect( agg.summaryAt( after ), isNot( contains( ' of 3' ) ) );
    });

    test( 'a recovered tally says where its number came from', () {
      final agg = withAcks( 2 ).interrupted().reconciled( const [] );

      expect( agg.summaryAt( inside ), contains( 'read back' ) );
      expect( agg.summaryAt( inside ), contains( '2 of 3' ) );
    });

    test( 'a recovered and COMPLETE tally says so plainly', () {
      final agg = withAcks( 3 ).interrupted().reconciled( const [] );

      expect( agg.summaryAt( inside ), 'All 3 acked — read back after the app stopped listening.' );
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
