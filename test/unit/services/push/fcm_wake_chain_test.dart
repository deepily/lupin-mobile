/// AC-S5.3 — the §3.2.4 HANDLER-DOES-THE-WORK chain (USER-RULED shape (2)):
/// token-exchange → fetch → show → ONE speak, in order, using ONLY
/// constructor-injected seams; ZERO service-locator access (asserted by
/// running the chain against an EMPTY GetIt); speak-toggle prefs OFF ⇒
/// fetch + show fire, speak does NOT; spoken text = `message` field ONLY;
/// unknown types logged and ignored.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:lupin_mobile/services/push/fcm_wake_chain.dart';

void main() {
  group( 'FcmWakeChain (S5 §3.2.4)', () {
    late List<String> calls;     // ordered seam-call journal
    late List<String> logs;
    late List<String> spoken;
    late bool         speakAllowed;
    late Map<String, dynamic>? nextItem;

    Map<String, dynamic> wakePayload( { String reason = 'undelivered' } ) =>
        { 'type': 'ws_wake', 'reason': reason, 'ts': '2026-06-12T09:00:00Z' };

    Map<String, dynamic> wireItem() => {
      'id'       : 'n-77',
      'message'  : 'Build finished green.',
      'abstract' : 'A LONG abstract body that must NEVER be spoken.',
      'title'    : 'Mr. Radio',
      'priority' : 'high',
    };

    late FcmWakeChain chain;

    setUp( () {
      calls        = [];
      logs         = [];
      spoken       = [];
      speakAllowed = true;
      nextItem     = wireItem();

      chain = FcmWakeChain(
        readCredentials: () async {
          calls.add( 'creds' );
          return const FcmWakeCredentials(
            refreshToken : 'refresh-abc',
            userEmail    : 'rick@test.com',
          );
        },
        exchangeForAccessToken: ( refresh ) async {
          calls.add( 'exchange($refresh)' );
          return 'access-xyz';
        },
        fetchNextNotification: ( email, token ) async {
          calls.add( 'fetch($email,$token)' );
          return nextItem;
        },
        showNotification: ( title, body ) async {
          calls.add( 'show($title)' );
        },
        shouldSpeak: ( priority ) async {
          calls.add( 'prefs($priority)' );
          return speakAllowed;
        },
        speak: ( text ) async {
          calls.add( 'speak' );
          spoken.add( text );
        },
        markPlayed: ( id, token ) async {
          calls.add( 'played($id)' );
        },
        log: logs.add,
      );
    } );

    test( 'AC-S5.3 — ws_wake runs token-exchange → fetch → show → ONE speak, IN ORDER, with an EMPTY service locator', () async {
      // Zero-locator assertion: nothing is registered; if any seam (or the
      // chain itself) touched the locator, GetIt would throw.
      await GetIt.instance.reset();
      expect( GetIt.instance.allReadySync(), isTrue );

      final outcome = await chain.handleWake( wakePayload() );

      expect( calls, [
        'creds',
        'exchange(refresh-abc)',
        'fetch(rick@test.com,access-xyz)',
        'show(Mr. Radio)',
        'prefs(high)',
        'speak',
        'played(n-77)',
      ], reason: 'the §3.2.4 chain order is the contract' );
      expect( spoken, hasLength( 1 ), reason: 'strict fetch-one-SPEAK-ONE' );
      expect( outcome.handled, isTrue );
      expect( outcome.fetched, 1 );
      expect( outcome.shown, isTrue );
      expect( outcome.spoke, isTrue );
      expect( outcome.reason, 'undelivered' );
    } );

    test( 'AC-S5.3 — spoken text is the `message` field ONLY (never abstract)', () async {
      await chain.handleWake( wakePayload() );
      expect( spoken.single, 'Build finished green.' );
      expect( spoken.single.contains( 'abstract' ), isFalse );
    } );

    test( 'AC-S5.3 — speak-toggle prefs OFF: fetch + show fire, speak does NOT', () async {
      speakAllowed = false;
      final outcome = await chain.handleWake( wakePayload() );

      expect( calls.where( ( c ) => c.startsWith( 'fetch' ) ), hasLength( 1 ) );
      expect( calls.where( ( c ) => c.startsWith( 'show' )  ), hasLength( 1 ) );
      expect( calls.contains( 'speak' ), isFalse );
      expect( spoken, isEmpty );
      expect( outcome.shown, isTrue );
      expect( outcome.spoke, isFalse );
      expect( logs.any( ( l ) => l.contains( 'muted by speak-toggle prefs' ) ), isTrue );
    } );

    test( 'AC-S5.3 — unknown data-message type: logged and ignored, NO seam calls', () async {
      final outcome = await chain.handleWake(
          { 'type': 'mystery_frame', 'reason': 'whatever' } );

      expect( outcome.handled, isFalse );
      expect( calls, isEmpty, reason: 'no fetch, no show, no speak' );
      expect( logs.single, contains( 'unknown data-message type "mystery_frame"' ) );
    } );

    test( 'reason enum: reconnect-hint wakes run the same chain', () async {
      final outcome = await chain.handleWake( wakePayload( reason: 'reconnect-hint' ) );
      expect( outcome.handled, isTrue );
      expect( outcome.reason, 'reconnect-hint' );
    } );

    test( 'no stored credentials (never logged in): chain ends quietly, nothing fetched', () async {
      final quiet = FcmWakeChain(
        readCredentials        : () async => null,
        exchangeForAccessToken : ( _ ) async => fail( 'must not exchange' ),
        fetchNextNotification  : ( _, __ ) async => fail( 'must not fetch' ),
        showNotification       : ( _, __ ) async => fail( 'must not show' ),
        shouldSpeak            : ( _ ) async => true,
        speak                  : ( _ ) async => fail( 'must not speak' ),
        markPlayed             : ( _, __ ) async {},
        log                    : logs.add,
      );
      final outcome = await quiet.handleWake( wakePayload() );
      expect( outcome.handled, isTrue );
      expect( outcome.fetched, 0 );
      expect( outcome.detail, 'no credentials' );
    } );

    test( 'nothing undelivered (fetch returns null): no show, no speak', () async {
      nextItem = null;
      final outcome = await chain.handleWake( wakePayload() );
      expect( outcome.fetched, 0 );
      expect( calls.any( ( c ) => c.startsWith( 'show' ) ), isFalse );
      expect( spoken, isEmpty );
    } );

    test( 'chain never throws: a failing fetch logs and returns an error outcome', () async {
      final flaky = FcmWakeChain(
        readCredentials: () async => const FcmWakeCredentials(
            refreshToken: 'r', userEmail: 'e@x.com' ),
        exchangeForAccessToken : ( _ ) async => 'a',
        fetchNextNotification  : ( _, __ ) async => throw Exception( 'net down' ),
        showNotification       : ( _, __ ) async {},
        shouldSpeak            : ( _ ) async => true,
        speak                  : ( _ ) async {},
        markPlayed             : ( _, __ ) async {},
        log                    : logs.add,
      );
      final outcome = await flaky.handleWake( wakePayload() );
      expect( outcome.handled, isTrue );
      expect( outcome.detail, contains( 'error:' ) );
      expect( logs.any( ( l ) => l.contains( 'chain failed' ) ), isTrue );
    } );

    test( 'mark-played failure is best-effort (swallowed, logged); wake still succeeds', () async {
      final stubborn = FcmWakeChain(
        readCredentials: () async => const FcmWakeCredentials(
            refreshToken: 'r', userEmail: 'e@x.com' ),
        exchangeForAccessToken : ( _ ) async => 'a',
        fetchNextNotification  : ( _, __ ) async => wireItem(),
        showNotification       : ( _, __ ) async {},
        shouldSpeak            : ( _ ) async => true,
        speak                  : ( t ) async { spoken.add( t ); },
        markPlayed             : ( _, __ ) async => throw Exception( 'flaky 500' ),
        log                    : logs.add,
      );
      final outcome = await stubborn.handleWake( wakePayload() );
      expect( outcome.spoke, isTrue );
      expect( logs.any( ( l ) => l.contains( 'mark-played failed (best-effort)' ) ), isTrue );
    } );

    test( 'debug hook (§4): every wake logs reason + per-step chain outcome', () async {
      await chain.handleWake( wakePayload() );
      expect( logs.first, contains( 'reason=undelivered' ) );
      expect( logs.any( ( l ) => l.contains( 'exchange ok' ) ), isTrue,
          reason: 'the Phase-0 probe asserts this exact line on-device' );
      expect( logs.any( ( l ) => l.contains( 'fetched 1' ) ), isTrue );
      expect( logs.any( ( l ) => l.contains( 'shown' ) ), isTrue );
      expect( logs.any( ( l ) => l.contains( 'spoke' ) ), isTrue );
    } );
  } );
}
