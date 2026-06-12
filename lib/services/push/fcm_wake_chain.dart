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
  final Future<void> Function( String title, String body ) showNotification;

  /// Prefs seam: may this priority speak? (Persisted speak-toggles read
  /// from local storage — mirrors the legacy policy: low/medium never,
  /// high iff speakOnHigh, urgent iff speakOnUrgent, masterMute silences.)
  final Future<bool> Function( String priority ) shouldSpeak;

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

    try {
      final creds = await readCredentials();
      if ( creds == null ) {
        log( '[FcmWake] no stored credentials — never logged in; done' );
        return FcmWakeOutcome(
          handled : true, reason: reason, fetched: 0,
          shown   : false, spoke: false, detail: 'no credentials',
        );
      }

      // The exchange is structurally unavoidable: the access token is
      // memory-only and this isolate is fresh (Arnold spot-check
      // amendment) — the Phase-0 probe asserts this log line.
      final accessToken = await exchangeForAccessToken( creds.refreshToken );
      log( '[FcmWake] refresh→access exchange ok' );

      final item = await fetchNextNotification( creds.userEmail, accessToken );
      if ( item == null ) {
        log( '[FcmWake] fetched 0 — nothing undelivered; done' );
        return FcmWakeOutcome(
          handled : true, reason: reason, fetched: 0,
          shown   : false, spoke: false, detail: 'nothing undelivered',
        );
      }

      final id       = item[ 'id' ]?.toString() ?? '';
      final message  = item[ 'message' ]?.toString() ?? '';
      final title    = item[ 'title' ]?.toString() ?? 'Lupin';
      final priority = item[ 'priority' ]?.toString() ?? 'medium';
      log( '[FcmWake] fetched 1 (id=$id priority=$priority)' );

      await showNotification( title, message );
      log( '[FcmWake] shown' );

      // Message-field-ONLY, prefs-gated, exactly one utterance. Audio is
      // best-effort: if the OS reclaims the isolate mid-utterance it
      // truncates and NOTHING is lost (server-side durable store +
      // foreground re-hydration; NO auto re-speak — badges carry it).
      final maySpeak = await shouldSpeak( priority );
      if ( maySpeak ) {
        await speak( message );
        log( '[FcmWake] spoke (message field only)' );
      } else {
        log( '[FcmWake] muted by speak-toggle prefs' );
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
        shown   : true, spoke: maySpeak, detail: 'id=$id',
      );
    } catch ( e ) {
      log( '[FcmWake] chain failed: $e' );
      return FcmWakeOutcome(
        handled : true, reason: reason, fetched: 0,
        shown   : false, spoke: false, detail: 'error: $e',
      );
    }
  }
}
