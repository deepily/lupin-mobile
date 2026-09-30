/// Row 8e91d937 (Rick, "Show each", 2026-09-29): a wake drains up to
/// [kFcmWakeDrainMax] allowed unplayed items, oldest first, each its own
/// notification, marking each played only once it is shown.
///
/// The server wakes only for a NEW notification, so before this an item behind
/// the first stayed invisible until the app opened.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:lupin_mobile/services/push/fcm_wake_chain.dart';

void main() {
  late List<String> shownBodies;
  late List<String?> shownPayloads;
  late List<String> shownTitles;
  late List<String> markedPlayed;
  late List<String> spoken;
  late List<Map<String, dynamic>> unplayed;
  late Set<String> mutedIds;

  Map<String, dynamic> wake() => { 'type': 'ws_wake', 'reason': 'undelivered' };

  Map<String, dynamic> item( int n, { String priority = 'high' } ) => {
    'id'        : 'n-$n',
    'message'   : 'body-$n',
    'priority'  : priority,
    'timestamp' : '2026-09-28T09:${n.toString().padLeft( 2, '0' )}:00-04:00',
    'sender_id' : 'claude.code@lupin.deepily.ai#a1b2c3d${n % 10}',
  };

  FcmWakeChain chain( {
    Future<void> Function( String, String, String? )? show,
    Future<void> Function( String, String )?          mark,
    Duration budget = kFcmWakeShowBudget,
    Future<void> Function( String )? speakFn,
    Duration speakBudget      = kFcmWakeSpeakBudget,
    Duration markPlayedBudget = kFcmWakeMarkPlayedBudget,
    Duration handlerBudget    = kFcmWakeHandlerBudget,
  } ) => FcmWakeChain(
    readCredentials             : () async => const FcmWakeCredentials( refreshToken: 'r', userEmail: 'e@x.com' ),
    exchangeForAccessToken      : ( _ ) async => 'a',
    fetchUnplayed               : ( _, __ ) async => unplayed,
    showNotification            : show ?? ( title, body, payload ) async {
      shownTitles.add( title );
      shownBodies.add( body );
      shownPayloads.add( payload );
    },
    shouldSpeak                 : ( _ ) async => true,
    ttsFraction                 : () async => 1.0,
    speak                       : speakFn ?? ( text ) async => spoken.add( text ),
    markPlayed                  : mark ?? ( id, __ ) async => markedPlayed.add( id ),
    backgroundAllowsAnyPriority : () async => true,
    itemAllowed                 : ( _, i ) async => !mutedIds.contains( i[ 'id' ] ),
    log                         : ( _ ) {},
    showBudget                  : budget,
    speakBudget                 : speakBudget,
    markPlayedBudget            : markPlayedBudget,
    handlerBudget               : handlerBudget,
  );

  setUp( () {
    shownBodies   = [];
    shownPayloads = [];
    shownTitles   = [];
    markedPlayed  = [];
    spoken        = [];
    mutedIds      = {};
    unplayed      = [];
  } );

  test( '3 allowed items: 3 shown and 3 marked played, in order', () async {
    // Handed over newest-first: the drain still goes oldest-first.
    unplayed = [ item( 3 ), item( 2 ), item( 1 ) ];

    final outcome = await chain().handleWake( wake() );

    expect( shownBodies,  [ 'body-1', 'body-2', 'body-3' ] );
    expect( markedPlayed, [ 'n-1', 'n-2', 'n-3' ] );
    expect( outcome.shown, isTrue );
    expect( outcome.detail, contains( 'shown 3' ) );
  } );

  test( 'each notification carries its OWN sender label and tap payload', () async {
    unplayed = [ item( 1 ), item( 2 ) ];

    await chain().handleWake( wake() );

    expect( shownPayloads.length, 2 );
    expect( shownPayloads[ 0 ], isNotNull );
    expect( shownPayloads[ 0 ], isNot( shownPayloads[ 1 ] ),
            reason: 'one payload per item, never the first one reused' );
    expect( shownPayloads[ 0 ], contains( 'n-1' ) );
    expect( shownPayloads[ 1 ], contains( 'n-2' ) );
  } );

  test( '7 allowed items: 5 shown, the other 2 left unplayed', () async {
    unplayed = [ for ( var i = 1; i <= 7; i++ ) item( i ) ];

    final outcome = await chain().handleWake( wake() );

    expect( kFcmWakeDrainMax, 5 );
    expect( shownBodies,  [ for ( var i = 1; i <= 5; i++ ) 'body-$i' ] );
    expect( markedPlayed, [ for ( var i = 1; i <= 5; i++ ) 'n-$i' ] );
    expect( markedPlayed, isNot( contains( 'n-6' ) ) );
    expect( markedPlayed, isNot( contains( 'n-7' ) ) );
    expect( outcome.fetched, 7 );
  } );

  test( 'the budget expiring mid-drain leaves the rest unplayed', () async {
    unplayed = [ for ( var i = 1; i <= 4; i++ ) item( i ) ];

    // Each post eats 30ms of a 70ms budget: the third post is the last that can
    // start in time; the fourth is never attempted.
    // A post abandoned at the deadline may still complete later; it writes to
    // THIS test's list, not the shared one the next test's setUp replaces.
    final posted = <String>[];
    final outcome = await chain(
      budget : const Duration( milliseconds: 70 ),
      show   : ( title, body, payload ) async {
        await Future<void>.delayed( const Duration( milliseconds: 30 ) );
        posted.add( body );
      },
    ).handleWake( wake() );

    expect( posted.length, lessThan( 4 ), reason: 'the drain stopped early' );
    expect( posted.length, greaterThanOrEqualTo( 1 ) );
    expect( markedPlayed, [ for ( var i = 1; i <= markedPlayed.length; i++ ) 'n-$i' ],
            reason: 'only what was shown was consumed' );
    expect( markedPlayed, isNotEmpty );
    expect( markedPlayed.length, lessThanOrEqualTo( posted.length ) );
    expect( outcome.shown, isTrue );
  } );

  test( 'a post that hangs after the first item ends the drain; no fallback is added', () async {
    unplayed = [ item( 1 ), item( 2 ), item( 3 ) ];
    var calls = 0;

    final outcome = await chain(
      budget : const Duration( milliseconds: 50 ),
      show   : ( title, body, payload ) async {
        calls++;
        if ( calls == 2 ) return Completer<void>().future;   // wedged plugin
        shownTitles.add( title );
        shownBodies.add( body );
      },
    ).handleWake( wake() );

    expect( shownBodies, [ 'body-1' ], reason: 'no fallback posted on top of a real item' );
    expect( markedPlayed, [ 'n-1' ], reason: 'the wedged item is not consumed' );
    expect( outcome.shown, isTrue );
  } );

  test( 'a muted item in the middle is skipped and not consumed', () async {
    unplayed = [ item( 1 ), item( 2 ), item( 3 ) ];
    mutedIds = { 'n-2' };

    final outcome = await chain().handleWake( wake() );

    expect( shownBodies,  [ 'body-1', 'body-3' ] );
    expect( markedPlayed, [ 'n-1', 'n-3' ] );
    expect( outcome.detail, contains( 'skipped 1' ) );
  } );

  test( 'skipped items do not count against the cap of 5', () async {
    unplayed = [ for ( var i = 1; i <= 8; i++ ) item( i ) ];
    mutedIds = { 'n-1', 'n-2', 'n-3' };

    await chain().handleWake( wake() );

    expect( shownBodies, [ for ( var i = 4; i <= 8; i++ ) 'body-$i' ] );
  } );

  test( 'only ONE item is spoken, and it is the first', () async {
    unplayed = [ item( 1 ), item( 2 ), item( 3 ) ];

    final outcome = await chain().handleWake( wake() );

    expect( spoken, [ 'body-1' ] );
    expect( outcome.spoke, isTrue );
  } );

  test( 'a failing mark-played on one item does not stop the drain', () async {
    unplayed = [ item( 1 ), item( 2 ) ];

    await chain( mark: ( id, _ ) async {
      if ( id == 'n-1' ) throw StateError( 'server said no' );
      markedPlayed.add( id );
    } ).handleWake( wake() );

    expect( shownBodies,  [ 'body-1', 'body-2' ] );
    expect( markedPlayed, [ 'n-2' ] );
  } );

  test( 'one item still behaves exactly as before: detail id=..., one notification', () async {
    unplayed = [ item( 1 ) ];

    final outcome = await chain().handleWake( wake() );

    expect( shownBodies, [ 'body-1' ] );
    expect( outcome.detail, 'id=n-1' );
  } );

  // Row 5365750f: speak and mark-played draw down from ONE handler deadline.
  group( 'whole-handler deadline', () {
    const window = Duration( milliseconds: 300 );
    const slack  = Duration( milliseconds: 150 );

    Future<Duration> timed( Future<FcmWakeOutcome> Function() run ) async {
      final sw = Stopwatch()..start();
      await run().timeout( const Duration( seconds: 5 ),
          onTimeout: () => fail( 'handleWake hung' ) );
      return sw.elapsed;
    }

    test( 'a slow (never-finishing) speak cannot push the handler past its window', () async {
      unplayed = [ item( 1 ) ];
      final took = await timed( () => chain(
        speakFn          : ( _ ) => Completer<void>().future,
        speakBudget      : const Duration( seconds: 10 ),
        markPlayedBudget : const Duration( milliseconds: 100 ),
        handlerBudget    : window,
      ).handleWake( wake() ) );

      expect( took, lessThan( window + slack ) );
      expect( markedPlayed, [ 'n-1' ], reason: 'speech is cut short of the ledger write' );
    } );

    test( 'a never-finishing mark-played cannot push the handler past its window', () async {
      unplayed = [ item( 1 ), item( 2 ), item( 3 ), item( 4 ), item( 5 ) ];
      final took = await timed( () => chain(
        mark             : ( _, __ ) => Completer<void>().future,
        markPlayedBudget : const Duration( milliseconds: 100 ),
        handlerBudget    : window,
      ).handleWake( wake() ) );

      // Per-call budgets alone would allow 5 x 100 ms = 500 ms here.
      expect( took, lessThan( window + slack ) );
    } );

    test( 'slow-but-succeeding mark-played stops the drain, and never shows an item it cannot mark',
        () async {
      unplayed = [ item( 1 ), item( 2 ), item( 3 ), item( 4 ), item( 5 ) ];
      final took = await timed( () => chain(
        mark             : ( id, __ ) async {
          await Future<void>.delayed( const Duration( milliseconds: 80 ) );
          markedPlayed.add( id );
        },
        markPlayedBudget : const Duration( milliseconds: 100 ),
        handlerBudget    : window,
      ).handleWake( wake() ) );

      expect( took, lessThan( window + slack ) );
      expect( shownBodies.length, lessThan( 5 ), reason: 'the window ran out before the cap' );
      expect( markedPlayed.length, shownBodies.length,
          reason: 'every item shown was also marked — none left to be re-shown next wake' );
    } );
  } );
}
