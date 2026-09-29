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

import 'dart:async' show TimeoutException;

import 'notification_sender_label.dart';
import 'notification_tap_payload.dart';
import 'unplayed_queue_order.dart';
import '../tts/tts_preview_truncator.dart';

/// Outcome record for the §4 debug hook — every wake logs
/// `reason + fetched n / shown / spoke|muted` so the chain is
/// field-debuggable from `adb logcat`.
class FcmWakeOutcome {
  final bool   handled;   // false ⇒ unknown type, logged + ignored
  final String reason;    // wake payload reason (or 'n/a')
  final int    fetched;   // how many UNPLAYED items the fetch returned
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

/// How long the chain may spend getting to a VISIBLE notification before it
/// gives up and posts the fallback instead (review F2, row 8ff78c69).
///
/// 🔴 A HANG IS WORSE THAN AN ERROR, BECAUSE THE FALLBACK LIVES IN THE CATCH
/// ARM. An exception reaches it; a call that never returns and never throws does
/// not, so the wake ends with an empty shade and Android eventually reclaims the
/// isolate — after which FCM starts downgrading our high-priority messages (see
/// the note on [kFcmWakeFallbackBody]). Transport timeouts alone cannot close
/// this: secure storage, SharedPreferences and the notification plugin are all
/// on the path to the notification and none of them is Dio.
///
/// The budget covers the PRE-NOTIFICATION phase only — credentials, exchange,
/// fetch, show. Past that the contract is already met, the utterance has its own
/// best-effort catch, and mark-played must not be skipped (that is F1).
/// ~20 s of the Android handler's ~30 s, leaving room for speech and the ledger.
const Duration kFcmWakeShowBudget = Duration( seconds: 20 );

/// How long the FALLBACK notification itself may take. It needs a budget of its
/// own: the fallback goes out through the SAME `showNotification` seam, so if
/// that seam is what hung, the catch arm would hang on it too and the timeout
/// above would have bought nothing. Short, because by the time this runs the
/// main budget is already spent.
const Duration kFcmWakeFallbackBudget = Duration( seconds: 5 );

/// How long the UTTERANCE may take, and how long the ledger write after it may
/// take (Chloé's C1).
///
/// 🔴 A try/catch AROUND speak() CATCHES A THROW AND DOES NOTHING ABOUT A HANG,
/// and those are different failures. The F2 budget was scoped to the
/// pre-notification phase on the argument that "past that the contract is met" —
/// true for the SHADE, false for everything after it. `speak` awaits
/// `awaitSpeakCompletion`, so a wedged TTS engine parks the handler until Android
/// reclaims the isolate, and mark-played never runs. That is F1's permanent
/// head-of-line block arriving through a different door: the queue head stays
/// unplayed and every later notification is invisible.
///
/// So speech gets a budget of its own, and the ledger write gets one too. Both
/// are generous enough for real work — a long utterance, a round trip — and short
/// enough that the handler ends rather than being killed.
const Duration kFcmWakeSpeakBudget      = Duration( seconds: 12 );
const Duration kFcmWakeMarkPlayedBudget = Duration( seconds: 5 );

/// The most unplayed items one wake shows (row 8e91d937). The server wakes only
/// for a NEW notification, so a backlog would otherwise sit unseen behind the
/// first item until the app opened. Capped so a long backlog cannot flood the
/// shade or outrun the handler window; whatever is past the cap stays unplayed.
const int kFcmWakeDrainMax = 5;

class FcmWakeChain {
  /// Secure-storage seam: refresh token + last email, or null when the
  /// user has never logged in on this device/context.
  final Future<FcmWakeCredentials?> Function() readCredentials;

  /// Auth seam: exchange the refresh token for a fresh access token
  /// (`POST /auth/refresh` — `auth_repository.dart:67`).
  final Future<String> Function( String refreshToken ) exchangeForAccessToken;

  /// Fetch seam: the user's UNPLAYED notifications, raw wire maps. The chain
  /// reads only `id` / `message` / `priority` / `timestamp` from each, plus
  /// whatever `notificationSenderLabel` and `NotificationTapPayload` need.
  ///
  /// 🔴 A LIST, NOT ONE ITEM (Tiffany's ruling, 2026-09-28, row 7cac3a17).
  /// This used to be `/next`, which hands back the single oldest unplayed
  /// item. With per-priority filtering that is a trap: a `low` the user has
  /// switched off sits at the head of the queue, and because we must not
  /// consume it — see [itemAllowed] — every later wake re-fetches that
  /// same item and an `urgent` behind it never reaches the phone at all.
  /// Fetching the list lets the chain skip what it may not show and still
  /// find what it may.
  final Future<List<Map<String, dynamic>>> Function(
      String userEmail, String accessToken ) fetchUnplayed;

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

  /// Prefs seam, GATE A: could a background notification be raised at ANY
  /// priority? (Row 7cac3a17; supersedes row 1af7b3de's single wake switch,
  /// whose gate position this keeps verbatim.)
  ///
  /// Checked FIRST, before credentials, and not merely before
  /// `showNotification`. Two reasons the earlier gate is the right one, both
  /// Pocholo's and both still true: a wake that fetches an item and marks it
  /// played WITHOUT showing anything would silently CONSUME it — the server's
  /// unplayed queue is what the foreground re-hydrates from, so Rick would
  /// never see it at all, which is deletion rather than silence. And "off"
  /// should cost no radio and no battery, which only holds if nothing before
  /// the notification runs either.
  final Future<bool> Function() backgroundAllowsAnyPriority;

  /// Prefs seam, GATE B: may THIS item be raised in the background?
  ///
  /// It gets the priority (already defaulted to `medium` when absent) AND the
  /// whole item, because mute-by-sender and quiet hours (row f1e80e67) need to
  /// know who sent it, not just how loudly.
  ///
  /// 🔴 A DENIED ITEM IS SKIPPED, NEVER CONSUMED. It is not shown, not spoken
  /// and not marked played, so it is still sitting unplayed on the server when
  /// the app is next opened and the list re-hydrates. Silence, not deletion —
  /// the same rule gate A enforces, one step later.
  final Future<bool> Function( String priority, Map<String, dynamic> item ) itemAllowed;

  /// Debug-hook seam (§4): one line per chain step, adb-visible.
  final void Function( String line ) log;

  /// Deadline for reaching a visible notification ([kFcmWakeShowBudget]).
  /// Injectable so tests can prove the hang path in milliseconds.
  final Duration showBudget;

  /// Deadline for the fallback notification itself ([kFcmWakeFallbackBudget]).
  final Duration fallbackBudget;

  /// Deadline for the utterance ([kFcmWakeSpeakBudget]) and for the mark-played
  /// write after it ([kFcmWakeMarkPlayedBudget]). Injectable so a test can prove a
  /// HUNG speak in milliseconds.
  final Duration speakBudget;
  final Duration markPlayedBudget;

  const FcmWakeChain( {
    required this.readCredentials,
    required this.exchangeForAccessToken,
    required this.fetchUnplayed,
    required this.showNotification,
    required this.shouldSpeak,
    required this.ttsFraction,
    required this.speak,
    required this.markPlayed,
    required this.backgroundAllowsAnyPriority,
    required this.itemAllowed,
    required this.log,
    this.showBudget       = kFcmWakeShowBudget,
    this.fallbackBudget   = kFcmWakeFallbackBudget,
    this.speakBudget      = kFcmWakeSpeakBudget,
    this.markPlayedBudget = kFcmWakeMarkPlayedBudget,
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

    // ONE deadline shared by every step on the way to the notification, rather
    // than a per-call timeout: four calls each allowed the full budget would let
    // the handler run four times over its window and be reclaimed anyway.
    final deadline = DateTime.now().add( showBudget );
    Duration remaining() {
      final left = deadline.difference( DateTime.now() );
      return left.isNegative ? Duration.zero : left;
    }

    try {
      // GATE A (rows 1af7b3de then 7cac3a17): could a background notification be
      // raised at ANY priority? Nothing is fetched, shown, spoken or marked
      // played — the queue is left exactly as it was, so opening the app still
      // surfaces everything.
      //
      // 🔴 INSIDE THE TRY, AND THAT IS THE WHOLE POINT (Chloé's C2). This read sat
      // ABOVE it, so a SharedPreferences failure in a fresh isolate escaped
      // handleWake entirely — and the contract above says it never throws, while
      // `fcmBackgroundHandler` awaits it with no try of its own. The wake would
      // have died with nothing shown and nothing logged. Worth naming plainly: F1
      // added a test proving a throwing prefs read is survivable for
      // `shouldSpeak`, and then this second prefs read was added where it was not.
      // In here a failure takes the ordinary path — fallback notification, error
      // outcome — which for an unreadable switch is the right answer, because
      // "cannot tell" must not silently mean "off".
      //
      // Row 7cac3a17 widened WHAT is read and changed nothing about WHERE: it is
      // now "is any priority still wanted", not "is the one switch on". It is
      // still the FIRST statement in the try, ahead of credentials, so OFF still
      // costs no radio and no battery.
      //
      // 🔴 AND OFF POSTS NO FALLBACK, a deliberate exception to the every-wake-
      // ends-visible rule above. That rule exists to stop FCM downgrading our
      // high-priority messages; it cannot outrank the user saying in plain words
      // to be quiet, or the setting is decorative. Note the asymmetry with the
      // paragraph above and that it is intended: an unreadable switch DOES get
      // the fallback, because "cannot tell" is not consent to silence.
      if ( !await backgroundAllowsAnyPriority().timeout( remaining() ) ) {
        log( '[FcmWake] background notifications are OFF in settings — nothing to do' );
        return FcmWakeOutcome(
          handled : true, reason: reason, fetched: 0,
          shown   : false, spoke: false, detail: 'background notifications off',
        );
      }

      final creds = await readCredentials().timeout( remaining() );
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
      final accessToken =
          await exchangeForAccessToken( creds.refreshToken ).timeout( remaining() );
      log( '[FcmWake] refresh→access exchange ok' );

      final unplayed = await fetchUnplayed( creds.userEmail, accessToken )
          .timeout( remaining() );
      if ( unplayed.isEmpty ) {
        log( '[FcmWake] fetched 0 — nothing undelivered' );
        return FcmWakeOutcome(
          handled : true, reason: reason, fetched: 0,
          shown   : await _showFallback( kFcmWakeFallbackBody ),
          spoke   : false, detail: 'nothing undelivered',
        );
      }

      // GATE B + DRAIN (row 8e91d937, Rick "Show each", 2026-09-29). Oldest
      // first, up to [kFcmWakeDrainMax] items this user still wants, each its own
      // notification. The server wakes only for a NEW notification, so an item
      // behind the first would otherwise stay invisible until the app opened.
      // Everything skipped, or left over past the cap or the budget, is left
      // exactly as it was found: unshown, unspoken and UNPLAYED.
      final ordered    = oldestFirst( unplayed );
      final shownIds   = <String>[];
      var   skipped    = 0;
      var   spoke      = false;
      //
      // 🔴 THE READ IS BUDGETED TOO, for Chloé's C2 reason one loop further in.
      // This is a prefs read in a fresh isolate exactly as gate A's is, it sits
      // before the notification, and here it runs once PER SKIPPED ITEM — so a
      // storage layer that has gone slow rather than broken is multiplied by the
      // length of the denied run. Sharing the one `remaining()` deadline is what
      // keeps that bounded; a wedged read now throws into the catch and posts
      // the fallback instead of parking the handler until Android reclaims it.
      for ( final candidate in ordered ) {
        if ( shownIds.length >= kFcmWakeDrainMax ) break;
        try {
          // Out of time: stop draining. Nothing is consumed that was not shown.
          // (Never before the FIRST item: that one takes the ordinary path, where
          // a spent budget throws into the catch arm and posts the fallback.)
          if ( shownIds.isNotEmpty && remaining() == Duration.zero ) {
            log( '[FcmWake] handler budget spent after ${shownIds.length} — '
                 'the rest stays unplayed' );
            break;
          }

          final priority = candidate[ 'priority' ]?.toString() ?? 'medium';
          if ( !await itemAllowed( priority, candidate ).timeout( remaining() ) ) {
            skipped++;
            continue;
          }

          final id      = candidate[ 'id' ]?.toString() ?? '';
          final message = candidate[ 'message' ]?.toString() ?? '';

          // 🔴 THE TITLE IS WHO SENT IT, NOT THE ITEM'S OWN `title` (Tiffany's
          // ruling, 2026-09-28). A notification arriving with the phone face down
          // said WHAT happened and not WHO said it, so the only way to find out
          // was to open the app and tab through personas — the same complaint the
          // tap routing fixes, one step earlier. `notificationSenderLabel` is
          // total and always returns something, so the title cannot come out blank.
          final title = notificationSenderLabel( candidate );
          log( '[FcmWake] fetched ${ordered.length}, showing id=$id '
               'priority=$priority from="$title"' );

          // 🔴 THE PAYLOAD IS BUILT FROM `candidate`, THE THING BEING SHOWN — never
          // from the wake `data`. The push is content-free, and the queue head is
          // not necessarily whatever triggered this wake, so the notification on
          // the lock screen and the conversation a tap opens agree only if both
          // come from the same map.
          //
          // The deadline covers the post itself: a wedged plugin here is the last
          // thing between a wake and an empty shade (F2).
          await showNotification(
            title, message,
            NotificationTapPayload.fromNotification( candidate )?.encode(),
          ).timeout( remaining() );
          shown = true;
          shownIds.add( id );
          log( '[FcmWake] shown' );

          // At most the FIRST shown item is spoken: strict one-utterance
          // (`flutter_tts#260`), and five messages read aloud back to back is a
          // pile-up, not a summary. The rest are visible and marked below.
          //
          // Message-field-ONLY, prefs-gated. Audio is best-effort: if the OS
          // reclaims the isolate mid-utterance it truncates and NOTHING is lost
          // (server-side durable store + foreground re-hydration; NO auto
          // re-speak — badges carry it).
          //
          // 🔴 BEST-EFFORT MEANS THE MARK-PLAYED BELOW STILL RUNS. This block used
          // to sit bare in the outer try, so a throwing TTS engine jumped straight
          // to the catch and skipped the dedupe — and the queue head kept coming
          // back, so the next wake re-fetched and re-showed this same notification,
          // failed to speak it again, and the head never moved. One dead TTS engine
          // made every later notification invisible, permanently (Pocholo's review
          // F1, row 8ff78c69). Speech is allowed to fail; the ledger write is what
          // keeps the queue moving.
          if ( shownIds.length == 1 ) {
            try {
              // The prefs reads are budgeted too: in a fresh isolate a wedged
              // SharedPreferences is as capable of parking the handler as a wedged
              // engine is, and it would park it BEFORE anything was spoken.
              final maySpeak = await shouldSpeak( priority ).timeout( speakBudget );
              final fraction = maySpeak
                  ? await ttsFraction().timeout( speakBudget )
                  : 0.0;
              if ( !maySpeak ) {
                log( '[FcmWake] muted by speak-toggle prefs' );
              } else if ( TtsPreviewTruncator.silences( fraction ) ) {
                log( '[FcmWake] muted by the TTS slider at 0%' );
              } else {
                await speak( TtsPreviewTruncator.previewFor( message, fraction ) )
                    .timeout( speakBudget );
                spoke = true;
                log( '[FcmWake] spoke (message field only)' );
              }
            } on TimeoutException catch ( _ ) {
              // Named apart from a throw because it is the failure that used to
              // have no floor at all: nothing raised, so nothing was caught, and
              // the handler simply stopped here with the ledger un-written.
              log( '[FcmWake] speech exceeded its ${speakBudget.inSeconds}s budget — '
                   'abandoned, and the wake continues to mark-played' );
            } catch ( e ) {
              // Covers the prefs reads too: a failed SharedPreferences lookup is no
              // more entitled to strand the queue than a failed utterance is.
              log( '[FcmWake] speak failed (best-effort): $e' );
            }
          }

          // Marked only now that THIS item is shown, so an item the budget or the
          // cap cut off is never consumed.
          if ( id.isNotEmpty ) {
            try {
              await markPlayed( id, accessToken ).timeout( markPlayedBudget );
              log( '[FcmWake] marked played (dedupe)' );
            } catch ( e ) {
              log( '[FcmWake] mark-played failed (best-effort): $e' );
            }
          }
        } catch ( e ) {
          // The first item keeps the ordinary failure path (fallback, error
          // outcome). Once something is visible, a later item failing just ends
          // the drain: what is left stays unplayed for the next wake or the app.
          if ( shownIds.isEmpty ) rethrow;
          log( '[FcmWake] drain stopped after ${shownIds.length} shown: $e' );
          break;
        }
      }
      if ( skipped > 0 ) {
        log( '[FcmWake] skipped $skipped item(s) the user has switched off '
             '(left unplayed — they are all still there on open)' );
      }
      if ( shownIds.isEmpty ) {
        // Every waiting item is one the user asked not to hear about. Silence
        // is the whole point, so no notification and no fallback — and nothing
        // consumed, so opening the app still shows the lot.
        log( '[FcmWake] all ${ordered.length} unplayed item(s) are switched off '
             '— staying quiet, nothing consumed' );
        return FcmWakeOutcome(
          handled : true, reason: reason, fetched: ordered.length,
          shown   : false, spoke: false,
          detail  : 'all ${ordered.length} suppressed by priority',
        );
      }

      final ids = shownIds.length == 1
          ? 'id=${shownIds.first}'
          : 'ids=${shownIds.join( "," )} (shown ${shownIds.length})';
      return FcmWakeOutcome(
        handled : true, reason: reason, fetched: ordered.length,
        shown   : true, spoke: spoke,
        detail  : skipped > 0 ? '$ids (skipped $skipped)' : ids,
      );
    } catch ( e ) {
      // A timeout is named separately because it is the failure that used to be
      // invisible: nothing threw, so nothing was logged and nothing was shown.
      // The abandoned call keeps running — Dart cannot cancel it — so in the
      // rare case it completes after the deadline it may post its own
      // notification too. Two notifications is the acceptable trade for never
      // posting zero.
      final timedOut = e is TimeoutException;
      log( timedOut
          ? '[FcmWake] gave up after ${showBudget.inSeconds}s '
              'without reaching a notification — posting the fallback'
          : '[FcmWake] chain failed: $e' );
      return FcmWakeOutcome(
        handled : true, reason: reason, fetched: shown ? 1 : 0,
        shown   : shown || await _showFallback( kFcmWakeFallbackBody ),
        spoke   : false,
        detail  : timedOut ? 'timeout after ${showBudget.inSeconds}s' : 'error: $e',
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
      await showNotification( kFcmWakeFallbackTitle, body, null )
          .timeout( fallbackBudget );
      log( '[FcmWake] shown (fallback)' );
      return true;
    } catch ( e ) {
      log( '[FcmWake] fallback notification failed: $e' );
      return false;
    }
  }
}
