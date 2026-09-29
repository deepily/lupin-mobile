/// GATE B — row 7cac3a17. Per-priority filtering of BACKGROUND wake
/// notifications, and the rule that makes it safe: a suppressed item is
/// SKIPPED, never consumed.
///
/// 🔴 THE CASE THAT FORCED THIS SHAPE (Tiffany's ruling, 2026-09-28). The first
/// design gated the single item `/next` returns. That hides an `urgent` behind
/// a switched-off `low`: the low sits at the head of the unplayed queue, we
/// must not mark it played, so every later wake re-fetches the same low and the
/// urgent never reaches the phone at all. Fetching the LIST and skipping to the
/// oldest ALLOWED item is what closes that hole.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:lupin_mobile/services/push/fcm_bootstrap.dart';
import 'package:lupin_mobile/services/push/fcm_wake_chain.dart';

void main() {
  late List<String> shownBodies;
  late List<String> markedPlayed;
  late List<String> spoken;
  late List<String> logs;
  late Set<String>  allowedPriorities;
  late List<Map<String, dynamic>> unplayed;

  Map<String, dynamic> wakePayload() =>
      { 'type': 'ws_wake', 'reason': 'undelivered' };

  Map<String, dynamic> item( String id, String priority, { String? at } ) => {
    'id'        : id,
    'message'   : 'body-$id',
    'priority'  : priority,
    'timestamp' : at ?? '2026-09-28T09:00:00-04:00',
    'sender_id' : 'claude.code@lupin.deepily.ai#a1b2c3d4',
  };

  FcmWakeChain buildChain() => FcmWakeChain(
    readCredentials        : () async => const FcmWakeCredentials(
        refreshToken: 'r', userEmail: 'e@x.com' ),
    exchangeForAccessToken : ( _ ) async => 'a',
    fetchUnplayed          : ( _, __ ) async => unplayed,
    showNotification       : ( _, body, __ ) async => shownBodies.add( body ),
    shouldSpeak            : ( _ ) async => true,
    ttsFraction            : () async => 1.0,
    speak                  : ( text ) async => spoken.add( text ),
    markPlayed             : ( id, __ ) async => markedPlayed.add( id ),
    backgroundAllowsAnyPriority : () async => allowedPriorities.isNotEmpty,
    priorityAllowed             : ( p ) async => allowedPriorities.contains( p ),
    log                    : logs.add,
  );

  setUp( () {
    shownBodies       = [];
    markedPlayed      = [];
    spoken            = [];
    logs              = [];
    allowedPriorities = { 'low', 'medium', 'high', 'urgent' };
    unplayed          = [ item( 'n-1', 'high' ) ];
  } );

  group( 'GATE B — a denied priority is skipped, never consumed', () {
    test( "TIFFANY'S CASE: a switched-off low at the head does not hide the urgent behind it", () async {
      allowedPriorities = { 'urgent' };
      unplayed = [
        item( 'the-low',    'low',    at: '2026-09-28T08:00:00-04:00' ),
        item( 'the-urgent', 'urgent', at: '2026-09-28T09:00:00-04:00' ),
      ];

      final outcome = await buildChain().handleWake( wakePayload() );

      expect( shownBodies, [ 'body-the-urgent' ],
              reason: 'the urgent must reach the phone even though an older, '
                      'denied item sits in front of it' );
      expect( outcome.shown, isTrue );
    } );

    test( 'the skipped low is NOT marked played, so it is still there when the app opens', () async {
      allowedPriorities = { 'urgent' };
      unplayed = [
        item( 'the-low',    'low',    at: '2026-09-28T08:00:00-04:00' ),
        item( 'the-urgent', 'urgent', at: '2026-09-28T09:00:00-04:00' ),
      ];

      await buildChain().handleWake( wakePayload() );

      expect( markedPlayed, [ 'the-urgent' ],
              reason: 'ONLY the item actually shown is consumed — suppression '
                      'is silence, never deletion' );
      expect( markedPlayed, isNot( contains( 'the-low' ) ) );
    } );

    test( 'several denied items in a row are all skipped and all left unplayed', () async {
      allowedPriorities = { 'high' };
      unplayed = [
        item( 'low-1',  'low',    at: '2026-09-28T08:00:00-04:00' ),
        item( 'med-1',  'medium', at: '2026-09-28T08:10:00-04:00' ),
        item( 'low-2',  'low',    at: '2026-09-28T08:20:00-04:00' ),
        item( 'high-1', 'high',   at: '2026-09-28T08:30:00-04:00' ),
        item( 'high-2', 'high',   at: '2026-09-28T08:40:00-04:00' ),
      ];

      final outcome = await buildChain().handleWake( wakePayload() );

      expect( shownBodies, [ 'body-high-1' ], reason: 'the OLDEST allowed one' );
      expect( markedPlayed, [ 'high-1' ] );
      expect( outcome.fetched, 5 );
      expect( outcome.detail, contains( 'skipped 3' ) );
    } );

    test( 'when EVERY waiting item is switched off: silence, and nothing consumed', () async {
      allowedPriorities = { 'urgent' };
      unplayed = [
        item( 'low-1', 'low' ),
        item( 'low-2', 'low' ),
      ];

      final outcome = await buildChain().handleWake( wakePayload() );

      // 🔴 NO FALLBACK NOTIFICATION EITHER. Every other empty-handed path in
      // this chain posts "New activity" to keep FCM from downgrading us. Here
      // the user has said in plain words that they do not want to hear about
      // these, and a rule about FCM's opinion of us cannot outrank that, or the
      // setting is decorative.
      expect( shownBodies, isEmpty );
      expect( spoken, isEmpty );
      expect( markedPlayed, isEmpty,
              reason: 'the whole queue survives for the foreground' );
      expect( outcome.shown, isFalse );
      expect( outcome.fetched, 2 );
      expect( outcome.detail, contains( 'suppressed' ) );
    } );

    test( 'nothing is suppressed when every priority is allowed — the default install', () async {
      unplayed = [ item( 'n-1', 'low' ), item( 'n-2', 'urgent' ) ];

      await buildChain().handleWake( wakePayload() );

      expect( shownBodies, [ 'body-n-1' ], reason: 'plain oldest-first' );
      expect( markedPlayed, [ 'n-1' ] );
    } );
  } );

  group( 'F3 — the fetch limit must not re-create head-of-line blocking', () {
    test( "POCHOLO'S CASE: 60 denied urgents at the head do not hide the allowed low behind them",
        ( ) async {
      // The server slices the HEAD of the queue (`notifications[:limit]`), so a
      // limit is "the oldest N", not "the newest N". At limit=50 this list would
      // arrive truncated to 60 denied items with the low never fetched at all —
      // and since denied items are correctly never consumed, the run in front of
      // it would never shrink. Same blocking the list fetch was built to kill,
      // one layer down, invisible to every test that used a short list.
      allowedPriorities = { 'low' };
      unplayed = [
        for ( var i = 0; i < 60; i++ )
          item( 'urgent-$i', 'urgent',
                at: '2026-09-28T08:00:00-04:00' ),
        item( 'the-low', 'low', at: '2026-09-28T09:00:00-04:00' ),
      ];

      final outcome = await buildChain().handleWake( wakePayload() );

      expect( shownBodies, [ 'body-the-low' ] );
      expect( markedPlayed, [ 'the-low' ] );
      expect( outcome.fetched, 61 );
      expect( outcome.detail, contains( 'skipped 60' ) );
    } );

    test( 'the fetch limit is large enough that the case above can reach the client at all', () {
      // The test above proves the CHAIN walks past 60. This one pins the number
      // that decides whether those 61 items are ever fetched, because the chain
      // cannot skip past an item the request never asked for.
      expect( kFcmWakeUnplayedLimit, greaterThanOrEqualTo( 500 ) );
    } );
  } );

  group( 'GATE B — ordering', () {
    test( 'the OLDEST allowed item wins, even when the server hands the list back newest first', () async {
      unplayed = [
        item( 'newest', 'high', at: '2026-09-28T10:00:00-04:00' ),
        item( 'middle', 'high', at: '2026-09-28T09:00:00-04:00' ),
        item( 'oldest', 'high', at: '2026-09-28T08:00:00-04:00' ),
      ];

      await buildChain().handleWake( wakePayload() );

      expect( shownBodies, [ 'body-oldest' ] );
      expect( markedPlayed, [ 'oldest' ] );
    } );

    test( 'oldest-allowed, not oldest-overall: the age ordering is applied BEFORE the filter', () async {
      allowedPriorities = { 'high' };
      unplayed = [
        // Handed back newest-first, and the oldest of the three is denied.
        item( 'new-high', 'high', at: '2026-09-28T10:00:00-04:00' ),
        item( 'mid-high', 'high', at: '2026-09-28T09:00:00-04:00' ),
        item( 'old-low',  'low',  at: '2026-09-28T08:00:00-04:00' ),
      ];

      await buildChain().handleWake( wakePayload() );

      expect( shownBodies, [ 'body-mid-high' ],
              reason: 'sort first, then take the first survivor — sorting after '
                      'filtering would have shown new-high' );
      expect( markedPlayed, [ 'mid-high' ] );
    } );
  } );

  group( 'GATE B — the priority read itself', () {
    test( 'an item with no priority field is treated as medium, as the rest of the chain does', () async {
      allowedPriorities = { 'medium' };
      unplayed = [ { 'id': 'n-1', 'message': 'body-n-1', 'timestamp': '2026-09-28T08:00:00-04:00' } ];

      await buildChain().handleWake( wakePayload() );

      expect( shownBodies, [ 'body-n-1' ] );
    } );

    test( 'the gate is asked per ITEM, not once per wake', () async {
      final asked = <String>[];
      allowedPriorities = { 'urgent' };
      unplayed = [
        item( 'a', 'low',    at: '2026-09-28T08:00:00-04:00' ),
        item( 'b', 'medium', at: '2026-09-28T08:10:00-04:00' ),
        item( 'c', 'urgent', at: '2026-09-28T08:20:00-04:00' ),
      ];
      final chain = FcmWakeChain(
        readCredentials        : () async => const FcmWakeCredentials(
            refreshToken: 'r', userEmail: 'e@x.com' ),
        exchangeForAccessToken : ( _ ) async => 'a',
        fetchUnplayed          : ( _, __ ) async => unplayed,
        showNotification       : ( _, body, __ ) async => shownBodies.add( body ),
        shouldSpeak            : ( _ ) async => false,
        ttsFraction            : () async => 1.0,
        speak                  : ( _ ) async {},
        markPlayed             : ( id, __ ) async => markedPlayed.add( id ),
        backgroundAllowsAnyPriority : () async => true,
        priorityAllowed             : ( p ) async {
          asked.add( p );
          return allowedPriorities.contains( p );
        },
        log                    : logs.add,
      );

      await chain.handleWake( wakePayload() );

      expect( asked, [ 'low', 'medium', 'urgent' ],
              reason: 'walked in age order and stopped at the first survivor' );
      expect( shownBodies, [ 'body-c' ] );
    } );

    test( 'the gate is re-read on EVERY wake — it is flipped in a screen this isolate never sees', () async {
      var reads = 0;
      unplayed  = [ item( 'n-1', 'high' ) ];
      final chain = FcmWakeChain(
        readCredentials        : () async => const FcmWakeCredentials(
            refreshToken: 'r', userEmail: 'e@x.com' ),
        exchangeForAccessToken : ( _ ) async => 'a',
        fetchUnplayed          : ( _, __ ) async => unplayed,
        showNotification       : ( _, __, ___ ) async {},
        shouldSpeak            : ( _ ) async => false,
        ttsFraction            : () async => 1.0,
        speak                  : ( _ ) async {},
        markPlayed             : ( _, __ ) async {},
        backgroundAllowsAnyPriority : () async => true,
        priorityAllowed             : ( _ ) async { reads++; return true; },
        log                    : logs.add,
      );

      await chain.handleWake( wakePayload() );
      await chain.handleWake( wakePayload() );

      expect( reads, 2, reason: 'a value read once and cached would be the stale one' );
    } );
  } );

  test( 'GATE A still short-circuits before any radio is spent', () async {
    allowedPriorities = {};   // nothing allowed at all
    var fetched = false;
    final chain = FcmWakeChain(
      readCredentials        : () async => fail( 'must not read credentials' ),
      exchangeForAccessToken : ( _ ) async => fail( 'must not exchange' ),
      fetchUnplayed          : ( _, __ ) async { fetched = true; return []; },
      showNotification       : ( _, __, ___ ) async => fail( 'must not show' ),
      shouldSpeak            : ( _ ) async => false,
      ttsFraction            : () async => 1.0,
      speak                  : ( _ ) async {},
      markPlayed             : ( _, __ ) async => fail( 'must not consume' ),
      backgroundAllowsAnyPriority : () async => allowedPriorities.isNotEmpty,
      priorityAllowed             : ( p ) async => allowedPriorities.contains( p ),
      log                    : logs.add,
    );

    final outcome = await chain.handleWake( wakePayload() );

    expect( fetched, isFalse );
    expect( outcome.shown, isFalse );
    expect( outcome.detail, 'background notifications off' );
  } );
}
