/// The S5 §3.2.4 HANDLER-DOES-THE-WORK chain (F-S5-S2-1, USER-RULED shape
/// (2) — the 2026.04.21 §Option A′ single-utterance chain), shaped for the
/// background-isolate reality:
///
///   token-exchange → fetch → show → ONE speak (prefs-gated) → mark played
///
/// This class is LOCATOR-FREE BY CONSTRUCTION (AC-S5.3): every dependency
/// is a constructor-injected callback seam, so it runs identically in the
/// fresh background isolate (where the main isolate's service locator and
/// memory-only access token simply do not exist —
/// `auth_token_provider.dart:14`) and under unit test with an EMPTY GetIt.
///
/// Hard rules carried from the section file:
///   - The FCM payload is CONTENT-FREE; content arrives ONLY via the
///     authenticated fetch (`GET /api/notifications/{user}/next`,
///     parent `notifications.py:1628`).
///   - The spoken text is the TTS-brevity `message` field ONLY — never
///     abstract/payload bodies.
///   - Strict fetch-one-speak-one (`flutter_tts#260` rapid-repeat crash).
///   - The chain NEVER touches the WebSocket (Rick directive 1).
///   - Speak-toggle prefs are the path's ONLY gate; the foreground pause
///     is bloc state and does not persist.
///   - A wake is a summons, never proof of disconnection (§3.1
///     environment note) — no connection-state inference here.
library;

import 'notification_sender_label.dart';
import 'notification_tap_payload.dart';
import '../tts/tts_preview_truncator.dart';

/// Outcome record for the §4 debug hook — every wake logs
/// `reason + fetched n / shown / spoke|muted` so the chain is
/// field-debuggable from `adb logcat`.
class FcmWakeOutcome {
  final bool   handled;   // false ⇒ unknown type, logged + ignored
  final String reason;    // wake payload reason (or 'n/a')
  final int    fetched;   // 0 or 1 (fetch-one shape)
  final bool   shown;
  final bool   spoke;     // false + shown=true ⇒ muted by prefs
  final String detail;

  const FcmWakeOutcome( {
    required this.handled,
    required this.reason,
    required this.fetched,
    required this.shown,
    required this.spoke,
    required this.detail,
  } );

  @override
  String toString() =>
      'FcmWakeOutcome(handled=$handled reason=$reason fetched=$fetched '
      'shown=$shown ${spoke ? "spoke" : "muted"} $detail)';
}

/// Credentials the bootstrap reads from secure storage (the REFRESH token —
/// the access token is memory-only and never exists in a fresh isolate —
/// plus the last authenticated email for the fetch path).
class FcmWakeCredentials {
  final String refreshToken;
  final String userEmail;
  const FcmWakeCredentials( {
    required this.refreshToken,
    required this.userEmail,
  } );
}

/// What a wake shows when it has nothing better (row 8ff78c69, slice 2).
///
/// 🔴 A `ws_wake` MUST END IN A VISIBLE NOTIFICATION, EVERY TIME. FCM watches
/// whether high-priority messages produce one; when they don't, it quietly
/// downgrades them to normal priority, and normal-priority messages wait out
/// Doze (expert response C4,
/// src/rnd/2026.09.28-background-wake-socket-problem-statement-response.md).
/// So every path that used to end silently — no stored login, nothing
/// undelivered, a failed fetch — now posts one of these instead. Tapping it
/// opens the app, whose normal start reconnects the socket.
const String kFcmWakeFallbackTitle   = 'Lupin';
const String kFcmWakeFallbackBody    = 'New activity. Open Lupin to see it.';
const String kFcmWakeSignedOutBody   = 'New activity. Open Lupin and sign in to see it.';

class FcmWakeChain {
  /// Secure-storage seam: refresh token + last email, or null when the
  /// user has never logged in on this device/context.
  final Future<FcmWakeCredentials?> Function() readCredentials;

  /// Auth seam: exchange the refresh token for a fresh access token
  /// (`POST /auth/refresh` — `auth_repository.dart:67`).
  final Future<String> Function( String refreshToken ) exchangeForAccessToken;

  /// Fetch seam: next unplayed notification for the user, or null.
  /// Returns the raw wire map (`notification` object of the /next
  /// response); the chain reads only `id` / `message` / `title` /
  /// `priority` from it.
  final Future<Map<String, dynamic>?> Function(
      String userEmail, String accessToken ) fetchNextNotification;

  /// Local-notification seam (plugin re-initialized inside the handler).
  ///
  /// The third argument is the TAP PAYLOAD (row d9bc6f6c) — the encoded
  /// `{notification_id, sender_id}` of the item being shown, or null when there
  /// is no item behind the notification (every fallback path). Android stores
  /// it in the notification's intent, which is the ONLY channel that survives
  /// this isolate dying, the phone locking, and the user tapping an hour later.
  final Future<void> Function( String title, String body, String? payload )
      showNotification;

  /// Prefs seam: may this priority speak? (Persisted speak-toggles read
  /// from local storage — mirrors the legacy policy: low/medium never,
  /// high iff speakOnHigh, urgent iff speakOnUrgent, masterMute silences.)
  final Future<bool> Function( String priority ) shouldSpeak;

  /// Prefs seam: the TTS slider's fraction (`NotificationPreferences.
  /// ttsFraction`). The background path honours it exactly as the foreground
  /// orchestrator does: 0% speaks nothing, anything else is cut the same way
  /// (Rick 2026-09-18 — he heard whole messages here with the slider at 0%).
  final Future<double> Function() ttsFraction;

  /// TTS seam: ONE utterance, fresh flutter_tts instance behind it.
  final Future<void> Function( String message ) speak;

  /// Dedupe seam (best-effort, AFTER the speak): mark the item played so a
  /// repeat wake fetches nothing — the server-side durable store is the
  /// dedupe ledger (§3.1 environment note). Failures are swallowed.
  final Future<void> Function( String notificationId, String accessToken )
      markPlayed;

  /// Debug-hook seam (§4): one line per chain step, adb-visible.
  final void Function( String line ) log;

  const FcmWakeChain( {
    required this.readCredentials,
    required this.exchangeForAccessToken,
    required this.fetchNextNotification,
    required this.showNotification,
    required this.shouldSpeak,
    required this.ttsFraction,
    required this.speak,
    required this.markPlayed,
    required this.log,
  } );

  /// Handle one wake payload. Never throws — the FCM handler budget
  /// (~30 s) is best-effort and a crashed handler helps nobody; every
  /// failure path logs and returns an outcome.
  Future<FcmWakeOutcome> handleWake( Map<String, dynamic> data ) async {
    final type   = data[ 'type' ]?.toString() ?? '';
    final reason = data[ 'reason' ]?.toString() ?? 'n/a';

    if ( type != 'ws_wake' ) {
      // Defensive: unknown types logged and ignored (AC-S5.3).
      log( '[FcmWake] ignoring unknown data-message type "$type"' );
      return FcmWakeOutcome(
        handled : false,
        reason  : reason,
        fetched : 0,
        shown   : false,
        spoke   : false,
        detail  : 'unknown type "$type"',
      );
    }
    log( '[FcmWake] wake received, reason=$reason' );

    // Set once the REAL notification is posted, so a failure after that point
    // (speak, mark-played) never adds a fallback on top of it.
    var shown = false;

    try {
      final creds = await readCredentials();
      if ( creds == null ) {
        log( '[FcmWake] no stored credentials — never logged in' );
        return FcmWakeOutcome(
          handled : true, reason: reason, fetched: 0,
          shown   : await _showFallback( kFcmWakeSignedOutBody ),
          spoke   : false, detail: 'no credentials',
        );
      }

      // The exchange is structurally unavoidable: the access token is
      // memory-only and this isolate is fresh (Arnold spot-check
      // amendment) — the Phase-0 probe asserts this log line.
      final accessToken = await exchangeForAccessToken( creds.refreshToken );
      log( '[FcmWake] refresh→access exchange ok' );

      final item = await fetchNextNotification( creds.userEmail, accessToken );
      if ( item == null ) {
        log( '[FcmWake] fetched 0 — nothing undelivered' );
        return FcmWakeOutcome(
          handled : true, reason: reason, fetched: 0,
          shown   : await _showFallback( kFcmWakeFallbackBody ),
          spoke   : false, detail: 'nothing undelivered',
        );
      }

      final id       = item[ 'id' ]?.toString() ?? '';
      final message  = item[ 'message' ]?.toString() ?? '';
      final priority = item[ 'priority' ]?.toString() ?? 'medium';

      // 🔴 THE TITLE IS WHO SENT IT, NOT THE ITEM'S OWN `title` (Tiffany's ruling,
      // 2026-09-28). A notification arriving with the phone face down said WHAT
      // happened and not WHO said it, so the only way to find out was to open the
      // app and tab through personas — the same complaint the tap routing fixes,
      // one step earlier. `notificationSenderLabel` is total and always returns
      // something, so the title cannot come out blank.
      final title = notificationSenderLabel( item );
      log( '[FcmWake] fetched 1 (id=$id priority=$priority from="$title")' );

      // 🔴 THE PAYLOAD IS BUILT FROM `item`, THE THING BEING SHOWN — never from
      // the wake `data`. The push is content-free, and `/next` hands back the
      // OLDEST unplayed item rather than whatever triggered this wake, so the
      // notification on the lock screen and the conversation a tap opens agree
      // only if both come from the same map.
      await showNotification(
        title, message,
        NotificationTapPayload.fromNotification( item )?.encode(),
      );
      shown = true;
      log( '[FcmWake] shown' );

      // Message-field-ONLY, prefs-gated, exactly one utterance. Audio is
      // best-effort: if the OS reclaims the isolate mid-utterance it
      // truncates and NOTHING is lost (server-side durable store +
      // foreground re-hydration; NO auto re-speak — badges carry it).
      //
      // 🔴 BEST-EFFORT MEANS THE MARK-PLAYED BELOW STILL RUNS. This block used
      // to sit bare in the outer try, so a throwing TTS engine jumped straight
      // to the catch and skipped the dedupe — and /next keeps returning the
      // oldest UNPLAYED item, so the next wake re-fetched and re-showed this
      // same notification, failed to speak it again, and the queue head never
      // moved. One dead TTS engine made every later notification invisible,
      // permanently (Pocholo's review F1, row 8ff78c69). Speech is allowed to
      // fail; the ledger write is what keeps the queue moving.
      var spoke = false;
      try {
        final maySpeak = await shouldSpeak( priority );
        final fraction = maySpeak ? await ttsFraction() : 0.0;
        if ( !maySpeak ) {
          log( '[FcmWake] muted by speak-toggle prefs' );
        } else if ( TtsPreviewTruncator.silences( fraction ) ) {
          log( '[FcmWake] muted by the TTS slider at 0%' );
        } else {
          await speak( TtsPreviewTruncator.previewFor( message, fraction ) );
          spoke = true;
          log( '[FcmWake] spoke (message field only)' );
        }
      } catch ( e ) {
        // Covers the prefs reads too: a failed SharedPreferences lookup is no
        // more entitled to strand the queue than a failed utterance is.
        log( '[FcmWake] speak failed (best-effort): $e' );
      }

      if ( id.isNotEmpty ) {
        try {
          await markPlayed( id, accessToken );
          log( '[FcmWake] marked played (dedupe)' );
        } catch ( e ) {
          log( '[FcmWake] mark-played failed (best-effort): $e' );
        }
      }

      return FcmWakeOutcome(
        handled : true, reason: reason, fetched: 1,
        shown   : true, spoke: spoke, detail: 'id=$id',
      );
    } catch ( e ) {
      log( '[FcmWake] chain failed: $e' );
      return FcmWakeOutcome(
        handled : true, reason: reason, fetched: shown ? 1 : 0,
        shown   : shown || await _showFallback( kFcmWakeFallbackBody ),
        spoke   : false, detail: 'error: $e',
      );
    }
  }

  /// Post the fallback notification. Never throws: returns whether it posted,
  /// so a plugin failure here is reported as `shown=false` rather than lost.
  Future<bool> _showFallback( String body ) async {
    try {
      // No payload: a fallback stands for "something happened" with no item
      // behind it, so a tap has no conversation to open and lands on Focus mode
      // as it does today. Passing an id-less payload would be worse than none —
      // it would occupy the tap router's single slot for nothing.
      await showNotification( kFcmWakeFallbackTitle, body, null );
      log( '[FcmWake] shown (fallback)' );
      return true;
    } catch ( e ) {
      log( '[FcmWake] fallback notification failed: $e' );
      return false;
    }
  }
}
