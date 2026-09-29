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
        log                    : logs.add,
      );
      final outcome = await broken.handleWake( wakePayload() );
      expect( outcome.shown, isTrue );
      expect( shownBodies, [ kFcmWakeFallbackBody ] );
    } );

    test( 'a failure AFTER the real notification does not add a fallback on top', () async {
      final shownTitles = <String>[];
      final loud = FcmWakeChain(
        readCredentials: () async => const FcmWakeCredentials(
            refreshToken: 'r', userEmail: 'e@x.com' ),
        exchangeForAccessToken : ( _ ) async => 'a',
        fetchNextNotification  : ( _, __ ) async => wireItem(),
        showNotification       : ( title, _, __ ) async => shownTitles.add( title ),
        shouldSpeak            : ( _ ) async => true,
        ttsFraction            : () async => 1.0,
        speak                  : ( _ ) async => throw Exception( 'tts engine gone' ),
        markPlayed             : ( _, __ ) async {},
        log                    : logs.add,
      );
      final outcome = await loud.handleWake( wakePayload() );
      expect( outcome.shown, isTrue );
      expect( outcome.fetched, 1 );
      expect( shownTitles, [ '📻 Mr. Radio' ], reason: 'exactly one notification, the real one' );
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
          log                    : logs.add,
        );

        await blind.handleWake( wakePayload() );

        expect( NotificationTapPayload.decode( dropping.single ), isNull,
            reason: 'and a tap on that notification can route nowhere, which is '
                    'exactly the reported symptom' );
      } );
    } );
  } );
}
