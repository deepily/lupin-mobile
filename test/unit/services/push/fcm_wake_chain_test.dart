/// AC-S5.3 — the §3.2.4 HANDLER-DOES-THE-WORK chain (USER-RULED shape (2)):
/// token-exchange → fetch → show → ONE speak, in order, using ONLY
/// constructor-injected seams; ZERO service-locator access (asserted by
/// running the chain against an EMPTY GetIt); speak-toggle prefs OFF ⇒
/// fetch + show fire, speak does NOT; spoken text = `message` field ONLY;
/// unknown types logged and ignored.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';

import 'package:lupin_mobile/services/push/fcm_wake_chain.dart';
import 'package:lupin_mobile/services/push/notification_tap_payload.dart';
import 'package:lupin_mobile/services/tts/tts_preview_truncator.dart';

void main() {
  group( 'FcmWakeChain (S5 §3.2.4)', () {
    late List<String> calls;     // ordered seam-call journal
    late List<String> logs;
    late List<String> spoken;
    late List<String?> shownPayloads;   // row d9bc6f6c — tap payloads, in order
    late List<String>  shownTitles2;    // row d9bc6f6c — titles, in order
    late bool         speakAllowed;
    late double       sliderFraction;
    late Map<String, dynamic>? nextItem;

    Map<String, dynamic> wakePayload( { String reason = 'undelivered' } ) =>
        { 'type': 'ws_wake', 'reason': reason, 'ts': '2026-06-12T09:00:00Z' };

    Map<String, dynamic> wireItem() => {
      'id'        : 'n-77',
      'message'   : 'Build finished green.',
      'abstract'  : 'A LONG abstract body that must NEVER be spoken.',
      // The item's own `title` — no longer what the notification shows (row
      // d9bc6f6c). It stays in the fixture on purpose: the title must come from
      // the SENDER fields, and a test whose item had no competing title could not
      // tell the difference.
      'title'     : 'Build status',
      'priority'  : 'high',
      'voice_persona' : { 'name': 'radio', 'display_name': 'Mr. Radio', 'icon': '📻' },
      // Row d9bc6f6c: the server sends this on every item (confirmed against
      // test/fixtures/notifications/notification-with-persona.json), and the tap
      // payload is built from it.
      'sender_id' : 'claude.code@lupin.deepily.ai#a1b2c3d4',
    };

    late FcmWakeChain chain;

    setUp( () {
      calls         = [];
      logs          = [];
      spoken        = [];
      shownPayloads = [];
      shownTitles2  = [];
      speakAllowed   = true;
      sliderFraction = 1.0;
      nextItem       = wireItem();

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
        showNotification: ( title, body, payload ) async {
          calls.add( 'show($title)' );
          shownPayloads.add( payload );
          shownTitles2.add( title );
        },
        shouldSpeak: ( priority ) async {
          calls.add( 'prefs($priority)' );
          return speakAllowed;
        },
        ttsFraction: () async => sliderFraction,
        speak: ( text ) async {
          calls.add( 'speak' );
          spoken.add( text );
        },
        markPlayed: ( id, token ) async {
          calls.add( 'played($id)' );
        },
        wakeNotificationsEnabled: () async => true,
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
        'show(📻 Mr. Radio)',
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

    // Rick 2026-09-18: he heard whole high-priority messages with the slider
    // at 0%. This path spoke the full `message` and never read the slider.
    test( 'the TTS slider at 0%: fetch + show fire, NOTHING is spoken — not even a short message', () async {
      sliderFraction = 0.0;
      final outcome = await chain.handleWake( wakePayload() );

      expect( calls.where( ( c ) => c.startsWith( 'show' ) ), hasLength( 1 ),
          reason: 'the notification still appears; only the speech is off' );
      expect( spoken, isEmpty );
      expect( outcome.spoke, isFalse );
      expect( calls.contains( 'played(n-77)' ), isTrue,
          reason: 'still marked played, so the next wake does not re-fetch it' );
      expect( logs.any( ( l ) => l.contains( 'muted by the TTS slider at 0%' ) ), isTrue );
    } );

    test( 'the TTS slider at 20%: a long message is cut exactly as the foreground cuts it', () async {
      sliderFraction = 0.2;
      const long = 'The build finished on the third attempt. The flake was in the '
                   'websocket teardown. Nothing else changed in this run at all.';
      nextItem = { ...wireItem(), 'message': long };

      await chain.handleWake( wakePayload() );

      expect( spoken.single, 'The build finished on the third attempt.' );
      expect( spoken.single, TtsPreviewTruncator.previewFor( long, 0.2 ),
          reason: 'one truncator, both paths' );
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

    // ── Row 8ff78c69 slice 2: a ws_wake ALWAYS ends in a visible notification ──
    // FCM downgrades high-priority messages that don't produce one (expert C4).

    test( 'no stored credentials: nothing fetched, but a SIGN-IN fallback is shown', () async {
      final shownBodies = <String>[];
      final quiet = FcmWakeChain(
        readCredentials        : () async => null,
        exchangeForAccessToken : ( _ ) async => fail( 'must not exchange' ),
        fetchNextNotification  : ( _, __ ) async => fail( 'must not fetch' ),
        showNotification       : ( _, body, __ ) async => shownBodies.add( body ),
        shouldSpeak            : ( _ ) async => true,
        ttsFraction            : () async => 1.0,
        speak                  : ( _ ) async => fail( 'must not speak' ),
        markPlayed             : ( _, __ ) async {},
        wakeNotificationsEnabled: () async => true,
        log                    : logs.add,
      );
      final outcome = await quiet.handleWake( wakePayload() );
      expect( outcome.handled, isTrue );
      expect( outcome.fetched, 0 );
      expect( outcome.detail, 'no credentials' );
      expect( outcome.shown, isTrue );
      expect( shownBodies, [ kFcmWakeSignedOutBody ] );
    } );

    test( 'nothing undelivered (fetch returns null): the fallback is shown, nothing spoken', () async {
      nextItem = null;
      final outcome = await chain.handleWake( wakePayload() );
      expect( outcome.fetched, 0 );
      expect( outcome.shown, isTrue );
      expect( calls.where( ( c ) => c.startsWith( 'show' ) ), [ 'show($kFcmWakeFallbackTitle)' ] );
      expect( spoken, isEmpty );
    } );

    test( 'a failing token exchange still shows the fallback', () async {
      final shownBodies = <String>[];
      final broken = FcmWakeChain(
        readCredentials: () async => const FcmWakeCredentials(
            refreshToken: 'r', userEmail: 'e@x.com' ),
        exchangeForAccessToken : ( _ ) async => throw Exception( 'refresh expired' ),
        fetchNextNotification  : ( _, __ ) async => fail( 'must not fetch' ),
        showNotification       : ( _, body, __ ) async => shownBodies.add( body ),
        shouldSpeak            : ( _ ) async => true,
        ttsFraction            : () async => 1.0,
        speak                  : ( _ ) async => fail( 'must not speak' ),
        markPlayed             : ( _, __ ) async {},
        wakeNotificationsEnabled: () async => true,
        log                    : logs.add,
      );
      final outcome = await broken.handleWake( wakePayload() );
      expect( outcome.shown, isTrue );
      expect( shownBodies, [ kFcmWakeFallbackBody ] );
    } );

    test( 'a failure AFTER the real notification does not add a fallback on top', () async {
      final shownTitles = <String>[];
      final played      = <String>[];
      final loud = FcmWakeChain(
        readCredentials: () async => const FcmWakeCredentials(
            refreshToken: 'r', userEmail: 'e@x.com' ),
        exchangeForAccessToken : ( _ ) async => 'a',
        fetchNextNotification  : ( _, __ ) async => wireItem(),
        showNotification       : ( title, _, __ ) async => shownTitles.add( title ),
        shouldSpeak            : ( _ ) async => true,
        ttsFraction            : () async => 1.0,
        speak                  : ( _ ) async => throw Exception( 'tts engine gone' ),
        markPlayed             : ( id, __ ) async => played.add( id ),
        wakeNotificationsEnabled: () async => true,
        log                    : logs.add,
      );
      final outcome = await loud.handleWake( wakePayload() );
      expect( outcome.shown, isTrue );
      expect( outcome.fetched, 1 );
      expect( shownTitles, [ '📻 Mr. Radio' ], reason: 'exactly one notification, the real one' );
      // 🔴 THE ASSERTION THIS TEST WAS MISSING (review F1, row 8ff78c69). The
      // speak throw above used to escape to the outer catch and skip the
      // dedupe, and nothing here noticed because markPlayed was a stub that
      // recorded nothing. Journal it: the item MUST still be marked played, or
      // /next keeps handing back this same id and no later notification is ever
      // seen.
      expect( played, [ 'n-77' ],
          reason: 'a dead TTS engine must not strand the queue head' );
      expect( outcome.spoke, isFalse, reason: 'it did not speak — it threw' );
      expect( logs.any( ( l ) => l.contains( 'speak failed (best-effort)' ) ), isTrue );
    } );

    test( 'F1 — a throwing PREFS read is just as best-effort: the item is still marked played',
        () async {
      // The prefs lookups sit in the same block as the utterance, and a failed
      // SharedPreferences read in a fresh isolate is no more entitled to strand
      // the queue than a failed utterance is.
      final played = <String>[];
      final noPrefs = FcmWakeChain(
        readCredentials: () async => const FcmWakeCredentials(
            refreshToken: 'r', userEmail: 'e@x.com' ),
        exchangeForAccessToken : ( _ ) async => 'a',
        fetchNextNotification  : ( _, __ ) async => wireItem(),
        showNotification       : ( _, __, ___ ) async {},
        shouldSpeak            : ( _ ) async => throw Exception( 'prefs unavailable' ),
        ttsFraction            : () async => 1.0,
        speak                  : ( _ ) async {},
        markPlayed             : ( id, __ ) async => played.add( id ),
        wakeNotificationsEnabled: () async => true,
        log                    : logs.add,
      );
      final outcome = await noPrefs.handleWake( wakePayload() );
      expect( played, [ 'n-77' ] );
      expect( outcome.shown, isTrue );
      expect( outcome.spoke, isFalse );
      expect( outcome.detail, 'id=n-77',
          reason: 'a best-effort speak failure is not a chain error' );
    } );

    test( 'a failing notification plugin is reported as shown=false, never thrown', () async {
      final dead = FcmWakeChain(
        readCredentials        : () async => null,
        exchangeForAccessToken : ( _ ) async => 'a',
        fetchNextNotification  : ( _, __ ) async => null,
        showNotification       : ( _, __, ___ ) async => throw Exception( 'plugin not initialized' ),
        shouldSpeak            : ( _ ) async => true,
        ttsFraction            : () async => 1.0,
        speak                  : ( _ ) async {},
        markPlayed             : ( _, __ ) async {},
        wakeNotificationsEnabled: () async => true,
        log                    : logs.add,
      );
      final outcome = await dead.handleWake( wakePayload() );
      expect( outcome.shown, isFalse );
      expect( logs.any( ( l ) => l.contains( 'fallback notification failed' ) ), isTrue );
    } );

    test( 'chain never throws: a failing fetch logs and returns an error outcome', () async {
      final flaky = FcmWakeChain(
        readCredentials: () async => const FcmWakeCredentials(
            refreshToken: 'r', userEmail: 'e@x.com' ),
        exchangeForAccessToken : ( _ ) async => 'a',
        fetchNextNotification  : ( _, __ ) async => throw Exception( 'net down' ),
        showNotification       : ( _, __, ___ ) async {},
        shouldSpeak            : ( _ ) async => true,
        ttsFraction            : () async => 1.0,
        speak                  : ( _ ) async {},
        markPlayed             : ( _, __ ) async {},
        wakeNotificationsEnabled: () async => true,
        log                    : logs.add,
      );
      final outcome = await flaky.handleWake( wakePayload() );
      expect( outcome.handled, isTrue );
      expect( outcome.detail, contains( 'error:' ) );
      expect( logs.any( ( l ) => l.contains( 'chain failed' ) ), isTrue );
      expect( outcome.shown, isTrue, reason: 'slice 2: a failed fetch still ends in a notification' );
    } );

    test( 'mark-played failure is best-effort (swallowed, logged); wake still succeeds', () async {
      final stubborn = FcmWakeChain(
        readCredentials: () async => const FcmWakeCredentials(
            refreshToken: 'r', userEmail: 'e@x.com' ),
        exchangeForAccessToken : ( _ ) async => 'a',
        fetchNextNotification  : ( _, __ ) async => wireItem(),
        showNotification       : ( _, __, ___ ) async {},
        shouldSpeak            : ( _ ) async => true,
        ttsFraction            : () async => 1.0,
        speak                  : ( t ) async { spoken.add( t ); },
        markPlayed             : ( _, __ ) async => throw Exception( 'flaky 500' ),
        wakeNotificationsEnabled: () async => true,
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

    // ─────────────────────────────────────────────────────────────────────────
    // Row d9bc6f6c — the tap payload. Without it a tap is only an app launch,
    // which is the bug Rick reported from the phone.
    group( 'tap payload (row d9bc6f6c)', () {
      test( 'a shown item carries its OWN id and sender_id', () async {
        await chain.handleWake( wakePayload() );

        expect( shownPayloads, hasLength( 1 ) );
        final decoded = NotificationTapPayload.decode( shownPayloads.single );
        expect( decoded, isNotNull,
            reason: 'the payload must be decodable by the main isolate that reads '
                    'it back off the launch intent' );
        expect( decoded!.notificationId, 'n-77' );
        expect( decoded.senderId, 'claude.code@lupin.deepily.ai#a1b2c3d4' );
        expect( decoded.isRoutable, isTrue );
      } );

      test( 'the payload comes from the ITEM SHOWN, not from the wake frame', () async {
        // 🔴 `/next` returns the OLDEST unplayed item, which need not be the one
        // that triggered this push (Tiffany, 2026-09-28). So the notification on
        // the lock screen and the conversation its tap opens agree only if both
        // are read off the same map. Here the wake frame names a DIFFERENT seat;
        // the payload must ignore it.
        nextItem = {
          ...wireItem(),
          'id'        : 'n-oldest',
          'sender_id' : 'claude.code@lupin.deepily.ai#01d35747',
        };

        await chain.handleWake( {
          'type'      : 'ws_wake',
          'reason'    : 'undelivered',
          'sender_id' : 'claude.code@lupin.deepily.ai#deadbeef',
          'id'        : 'n-trigger',
        } );

        final decoded = NotificationTapPayload.decode( shownPayloads.single );
        expect( decoded!.notificationId, 'n-oldest' );
        expect( decoded.senderId, 'claude.code@lupin.deepily.ai#01d35747' );
      } );

      test( 'an item with no sender_id shows, but is not routable', () async {
        nextItem = { ...wireItem() }..remove( 'sender_id' );

        final outcome = await chain.handleWake( wakePayload() );

        expect( outcome.shown, isTrue, reason: 'the notification still posts' );
        final decoded = NotificationTapPayload.decode( shownPayloads.single );
        expect( decoded!.isRoutable, isFalse );
      } );

      test( 'the NOTHING-UNDELIVERED fallback carries NO payload', () async {
        nextItem = null;

        final outcome = await chain.handleWake( wakePayload() );

        expect( outcome.shown, isTrue );
        expect( shownPayloads.single, isNull,
            reason: 'a fallback stands for "something happened" with no item '
                    'behind it — there is no conversation for a tap to open, and '
                    'an id-less payload would occupy the tap router\'s one slot '
                    'for nothing' );
      } );

      test( 'the TITLE is the sender, not the item\'s own title', () async {
        // 🔴 Tiffany's ruling, 2026-09-28. A notification arriving with the phone
        // face down said WHAT happened and not WHO said it, so finding out meant
        // opening the app and tabbing through personas. The item here carries a
        // perfectly good `title` of its own ('Build status') and it is NOT what
        // shows — which is the whole change.
        await chain.handleWake( wakePayload() );

        expect( shownTitles2, [ '📻 Mr. Radio' ] );
      } );

      test( 'no persona ⇒ the PROJECT, with no hash', () async {
        nextItem = { ...wireItem() }..remove( 'voice_persona' );

        await chain.handleWake( wakePayload() );

        expect( shownTitles2, [ 'lupin' ],
            reason: 'the sender id is claude.code@lupin.deepily.ai#a1b2c3d4, and '
                    'the hash is dropped because nobody reads eight hex '
                    'characters off a lock screen' );
      } );

      test( 'the FALLBACK notification keeps its generic title', () async {
        nextItem = null;

        await chain.handleWake( wakePayload() );

        expect( shownTitles2, [ kFcmWakeFallbackTitle ],
            reason: 'there is no item, so there is no sender to name' );
      } );

      test( 'NEGATIVE CONTROL: a chain whose seam drops the payload loses the tap',
          () async {
        // Proof the assertions above test the PLUMBING and not the codec. This is
        // the pre-fix production wiring, reproduced exactly: a show() that
        // ignores its third argument.
        final dropping = <String?>[];
        final blind = FcmWakeChain(
          readCredentials        : () async => const FcmWakeCredentials(
              refreshToken: 'r', userEmail: 'rick@test.com' ),
          exchangeForAccessToken : ( _ ) async => 'access',
          fetchNextNotification  : ( _, __ ) async => wireItem(),
          showNotification       : ( _, __, ___ ) async => dropping.add( null ),
          shouldSpeak            : ( _ ) async => false,
          ttsFraction            : () async => 1.0,
          speak                  : ( _ ) async {},
          markPlayed             : ( _, __ ) async {},
          wakeNotificationsEnabled: () async => true,
          log                    : logs.add,
        );

        await blind.handleWake( wakePayload() );

        expect( NotificationTapPayload.decode( dropping.single ), isNull,
            reason: 'and a tap on that notification can route nowhere, which is '
                    'exactly the reported symptom' );
      } );
    } );
  } );

  group( 'F2 — a wake that HANGS still ends in a visible notification (row 8ff78c69)', () {
    // The failure these cover is the one that used to be invisible: a call that
    // never returns and never throws never reaches the catch arm where the
    // fallback lives, so the shade stayed empty and Android reclaimed the
    // isolate in silence. Transport timeouts cannot cover it on their own —
    // secure storage, prefs and the notification plugin are all on this path and
    // none of them is Dio. `showBudget` is injected in milliseconds so the proof
    // costs no wall clock.
    late List<String> logs;
    late List<String> shownBodies;

    Map<String, dynamic> wakePayload() => { 'type': 'ws_wake', 'reason': 'undelivered' };
    Map<String, dynamic> wireItem() => {
      'id': 'n-77', 'message': 'Build finished green.', 'title': 'Mr. Radio', 'priority': 'high',
    };

    /// A future that never completes — the half-open socket, the wedged plugin.
    Future<T> never<T>() => Completer<T>().future;

    setUp( () {
      logs        = [];
      shownBodies = [];
    } );

    FcmWakeChain chainWith( {
      Future<FcmWakeCredentials?> Function()? readCredentials,
      Future<String> Function( String )?      exchange,
      Future<Map<String, dynamic>?> Function( String, String )? fetch,
      Future<void> Function( String, String, String? )? show,
    } ) => FcmWakeChain(
      readCredentials: readCredentials ??
          () async => const FcmWakeCredentials(
              refreshToken: 'r', userEmail: 'e@x.com' ),
      exchangeForAccessToken : exchange ?? ( _ ) async => 'a',
      fetchNextNotification  : fetch ?? ( _, __ ) async => wireItem(),
      showNotification       : show ?? ( _, body, __ ) async => shownBodies.add( body ),
      shouldSpeak            : ( _ ) async => false,
      ttsFraction            : () async => 1.0,
      speak                  : ( _ ) async {},
      markPlayed             : ( _, __ ) async {},
      wakeNotificationsEnabled: () async => true,
      log                    : logs.add,
      showBudget             : const Duration( milliseconds: 40 ),
      fallbackBudget         : const Duration( milliseconds: 40 ),
    );

    test( 'a credential read that never returns: the fallback goes out anyway', () async {
      final outcome = await chainWith( readCredentials: never ).handleWake( wakePayload() );
      expect( outcome.shown, isTrue, reason: 'a hang must still reach the shade' );
      expect( shownBodies, [ kFcmWakeFallbackBody ] );
      expect( outcome.detail, contains( 'timeout' ) );
      expect( logs.any( ( l ) => l.contains( 'gave up after' ) ), isTrue,
          reason: 'the hang is named in the log, not silent' );
    } );

    test( 'a token exchange that never returns: the fallback goes out anyway', () async {
      final outcome = await chainWith( exchange: ( _ ) => never() ).handleWake( wakePayload() );
      expect( outcome.shown, isTrue );
      expect( shownBodies, [ kFcmWakeFallbackBody ] );
      expect( outcome.fetched, 0 );
    } );

    test( 'a fetch that never returns: the fallback goes out anyway', () async {
      final outcome = await chainWith( fetch: ( _, __ ) => never() ).handleWake( wakePayload() );
      expect( outcome.shown, isTrue );
      expect( shownBodies, [ kFcmWakeFallbackBody ] );
    } );

    test( 'the budget is shared across steps, not granted per call', () async {
      // Three slow-but-not-hung steps that together exceed the budget: a
      // per-call timeout would let this run 3x the window and still be
      // reclaimed by Android. One deadline stops it.
      Future<T> slow<T>( T v ) => Future.delayed( const Duration( milliseconds: 30 ), () => v );
      final outcome = await chainWith(
        readCredentials: () => slow( const FcmWakeCredentials(
            refreshToken: 'r', userEmail: 'e@x.com' ) ),
        exchange : ( _ ) => slow( 'a' ),
        fetch    : ( _, __ ) => slow( wireItem() ),
      ).handleWake( wakePayload() );
      expect( outcome.detail, contains( 'timeout' ),
          reason: '3 x 30ms must not fit in a 40ms budget' );
      expect( outcome.shown, isTrue );
    } );

    test( 'a WEDGED notification plugin is reported shown=false, and does not hang the handler',
        () async {
      // The fallback goes out through the same seam, so without its own budget
      // the catch arm would hang on exactly what it is there to recover from.
      final outcome = await chainWith( show: ( _, __, ___ ) => never() )
          .handleWake( wakePayload() )
          .timeout( const Duration( seconds: 2 ),
              onTimeout: () => fail( 'handleWake hung on a wedged plugin' ) );
      expect( outcome.shown, isFalse, reason: 'honest: nothing reached the shade' );
      expect( logs.any( ( l ) => l.contains( 'fallback notification failed' ) ), isTrue );
    } );
  } );

  group( 'the wake-notification switch (Rick 2026-09-28, row 1af7b3de)', () {
    late List<String> calls;
    late List<String> logs;
    late bool         wakeEnabled;

    Map<String, dynamic> wakePayload() => { 'type': 'ws_wake', 'reason': 'undelivered' };

    FcmWakeChain switchedChain() => FcmWakeChain(
      readCredentials: () async {
        calls.add( 'creds' );
        return const FcmWakeCredentials( refreshToken: 'r', userEmail: 'e@x.com' );
      },
      exchangeForAccessToken : ( _ ) async { calls.add( 'exchange' ); return 'a'; },
      fetchNextNotification  : ( _, __ ) async {
        calls.add( 'fetch' );
        return { 'id': 'n-77', 'message': 'm', 'title': 't', 'priority': 'high' };
      },
      showNotification : ( _, __, ___ ) async => calls.add( 'show' ),
      shouldSpeak      : ( _ ) async { calls.add( 'prefs' ); return true; },
      ttsFraction      : () async => 1.0,
      speak            : ( _ ) async => calls.add( 'speak' ),
      markPlayed       : ( _, __ ) async => calls.add( 'played' ),
      wakeNotificationsEnabled : () async => wakeEnabled,
      log              : logs.add,
    );

    setUp( () {
      calls       = [];
      logs        = [];
      wakeEnabled = true;
    } );

    test( 'OFF: the wake is a complete no-op — no fetch, no show, no speak', () async {
      wakeEnabled = false;
      final outcome = await switchedChain().handleWake( wakePayload() );
      expect( calls, isEmpty,
          reason: 'not one seam may run: off must cost no radio and no battery' );
      expect( outcome.handled, isTrue, reason: 'handled, just deliberately silent' );
      expect( outcome.shown, isFalse );
      expect( outcome.spoke, isFalse );
      expect( outcome.detail, 'wake notifications off' );
      expect( logs.any( ( l ) => l.contains( 'OFF in settings' ) ), isTrue );
    } );

    test( 'OFF: NOTHING is marked played, so the queue survives for the foreground',
        () async {
      // The distinction that makes this a mute and not a delete. The server's
      // unplayed queue is what the app re-hydrates from on open; marking items
      // played with nothing shown would lose them permanently.
      wakeEnabled = false;
      await switchedChain().handleWake( wakePayload() );
      expect( calls, isNot( contains( 'played' ) ) );
      expect( calls, isNot( contains( 'fetch' ) ) );
    } );

    test( 'ON (the default): the chain runs exactly as before the switch existed',
        () async {
      await switchedChain().handleWake( wakePayload() );
      expect( calls, [ 'creds', 'exchange', 'fetch', 'show', 'prefs', 'speak', 'played' ] );
    } );

    test( 'the switch is read on EVERY wake, never cached across them', () async {
      // It is flipped in a foreground screen while the background isolate is
      // long dead, so a value read once and held would be the stale one.
      var reads = 0;
      final chain = FcmWakeChain(
        readCredentials: () async => const FcmWakeCredentials(
            refreshToken: 'r', userEmail: 'e@x.com' ),
        exchangeForAccessToken : ( _ ) async => 'a',
        fetchNextNotification  : ( _, __ ) async => null,
        showNotification       : ( _, __, ___ ) async {},
        shouldSpeak            : ( _ ) async => false,
        ttsFraction            : () async => 1.0,
        speak                  : ( _ ) async {},
        markPlayed             : ( _, __ ) async {},
        wakeNotificationsEnabled : () async { reads++; return true; },
        log                    : logs.add,
      );
      await chain.handleWake( wakePayload() );
      await chain.handleWake( wakePayload() );
      expect( reads, 2 );
    } );
  } );

  group( 'C1 — a HUNG speak must not strand the ledger (Chloé, row 8ff78c69)', () {
    // F1 fixed the THROWING engine. A try/catch cannot see a HANG: speak awaits
    // awaitSpeakCompletion, so a wedged engine parked the handler until Android
    // reclaimed the isolate, and mark-played never ran — F1's permanent
    // head-of-line block arriving through a different door.
    late List<String> logs;
    late List<String> played;

    Map<String, dynamic> wakePayload() => { 'type': 'ws_wake', 'reason': 'undelivered' };
    Map<String, dynamic> wireItem() => {
      'id': 'n-77', 'message': 'Build finished green.', 'title': 't', 'priority': 'high',
    };
    Future<T> never<T>() => Completer<T>().future;

    setUp( () { logs = []; played = []; } );

    FcmWakeChain chainWith( {
      Future<void> Function( String )? speak,
      Future<bool> Function( String )? shouldSpeak,
      Future<void> Function( String, String )? markPlayed,
    } ) => FcmWakeChain(
      readCredentials: () async => const FcmWakeCredentials(
          refreshToken: 'r', userEmail: 'e@x.com' ),
      exchangeForAccessToken : ( _ ) async => 'a',
      fetchNextNotification  : ( _, __ ) async => wireItem(),
      showNotification       : ( _, __, ___ ) async {},
      shouldSpeak            : shouldSpeak ?? ( _ ) async => true,
      ttsFraction            : () async => 1.0,
      speak                  : speak ?? ( _ ) async {},
      markPlayed             : markPlayed ?? ( id, __ ) async => played.add( id ),
      wakeNotificationsEnabled : () async => true,
      log                    : logs.add,
      speakBudget            : const Duration( milliseconds: 40 ),
      markPlayedBudget       : const Duration( milliseconds: 40 ),
    );

    test( 'a WEDGED TTS engine is abandoned, and the item is STILL marked played',
        () async {
      final outcome = await chainWith( speak: ( _ ) => never() )
          .handleWake( wakePayload() )
          .timeout( const Duration( seconds: 2 ),
              onTimeout: () => fail( 'handleWake hung on a wedged TTS engine' ) );

      expect( played, [ 'n-77' ],
          reason: 'the ledger write is what keeps the queue moving — a hang must not skip it' );
      expect( outcome.shown, isTrue );
      expect( outcome.spoke, isFalse, reason: 'it never finished speaking' );
      expect( logs.any( ( l ) => l.contains( 'exceeded its' ) && l.contains( 'budget' ) ), isTrue,
          reason: 'a hang used to raise nothing, so nothing was logged' );
    } );

    test( 'a WEDGED prefs read is abandoned too, and the item is still marked played',
        () async {
      // It would park the handler BEFORE anything was spoken, so the budget has
      // to cover the reads and not just the utterance.
      final outcome = await chainWith( shouldSpeak: ( _ ) => never() )
          .handleWake( wakePayload() )
          .timeout( const Duration( seconds: 2 ),
              onTimeout: () => fail( 'handleWake hung on a wedged prefs read' ) );

      expect( played, [ 'n-77' ] );
      expect( outcome.spoke, isFalse );
    } );

    test( 'a WEDGED mark-played does not hang the handler either', () async {
      // Last step, and the one whose whole point is being best-effort: it may
      // fail, it may not hold the isolate open.
      final outcome = await chainWith( markPlayed: ( _, __ ) => never() )
          .handleWake( wakePayload() )
          .timeout( const Duration( seconds: 2 ),
              onTimeout: () => fail( 'handleWake hung on a wedged mark-played' ) );

      expect( outcome.shown, isTrue );
      expect( outcome.fetched, 1 );
      expect( logs.any( ( l ) => l.contains( 'mark-played failed (best-effort)' ) ), isTrue );
    } );

    test( 'the speak budget does NOT cut a normal utterance short', () async {
      // A budget that fires on healthy speech would silently truncate every
      // notification, which is worse than the bug it prevents.
      final spoken = <String>[];
      final chain = chainWith(
        speak: ( t ) async {
          await Future<void>.delayed( const Duration( milliseconds: 5 ) );
          spoken.add( t );
        },
      );
      final outcome = await chain.handleWake( wakePayload() );
      expect( spoken, [ 'Build finished green.' ] );
      expect( outcome.spoke, isTrue );
      expect( played, [ 'n-77' ] );
    } );
  } );

  group( 'C2 — an unreadable wake switch must not kill the handler (Chloé)', () {
    // The gate sat ABOVE the try, so a SharedPreferences failure in a fresh
    // isolate escaped handleWake — whose contract says it never throws, and whose
    // only caller (fcmBackgroundHandler) awaits it with no try of its own.
    late List<String> logs;
    late List<String> shownBodies;

    Map<String, dynamic> wakePayload() => { 'type': 'ws_wake', 'reason': 'undelivered' };

    setUp( () { logs = []; shownBodies = []; } );

    FcmWakeChain chainWithGate( Future<bool> Function() gate ) => FcmWakeChain(
      readCredentials: () async => const FcmWakeCredentials(
          refreshToken: 'r', userEmail: 'e@x.com' ),
      exchangeForAccessToken : ( _ ) async => 'a',
      fetchNextNotification  : ( _, __ ) async => null,
      showNotification       : ( _, body, __ ) async => shownBodies.add( body ),
      shouldSpeak            : ( _ ) async => false,
      ttsFraction            : () async => 1.0,
      speak                  : ( _ ) async {},
      markPlayed             : ( _, __ ) async {},
      wakeNotificationsEnabled : gate,
      log                    : logs.add,
      showBudget             : const Duration( milliseconds: 40 ),
      fallbackBudget         : const Duration( milliseconds: 40 ),
    );

    test( 'a THROWING switch read does not escape handleWake', () async {
      final chain = chainWithGate( () async => throw Exception( 'prefs unavailable' ) );

      // The assertion is that this completes at all. Before the fix it threw, and
      // the throw went straight out through the background handler.
      final outcome = await chain.handleWake( wakePayload() );

      expect( outcome.handled, isTrue );
      expect( outcome.detail, contains( 'error:' ) );
      expect( logs.any( ( l ) => l.contains( 'chain failed' ) ), isTrue );
    } );

    test( 'an unreadable switch still ends in a VISIBLE notification', () async {
      // "Cannot tell" must not silently mean "off" — that would be a wake
      // swallowed by a storage hiccup, which is the whole failure slice 2 exists
      // to prevent.
      final chain = chainWithGate( () async => throw Exception( 'prefs unavailable' ) );
      final outcome = await chain.handleWake( wakePayload() );

      expect( outcome.shown, isTrue );
      expect( shownBodies, [ kFcmWakeFallbackBody ] );
    } );

    test( 'a HUNG switch read does not park the handler either', () async {
      final chain = chainWithGate( () => Completer<bool>().future );
      final outcome = await chain.handleWake( wakePayload() )
          .timeout( const Duration( seconds: 2 ),
              onTimeout: () => fail( 'handleWake hung on the switch read' ) );

      expect( outcome.shown, isTrue, reason: 'a hang still reaches the shade' );
      expect( outcome.detail, contains( 'timeout' ) );
    } );

    test( 'and OFF still means off: the switch working is not regressed', () async {
      final chain = chainWithGate( () async => false );
      final outcome = await chain.handleWake( wakePayload() );

      expect( outcome.detail, 'wake notifications off' );
      expect( shownBodies, isEmpty, reason: 'off shows nothing at all' );
    } );
  } );
}
