/// The wake handler's chain: token exchange, fetch, show, one spoken item, mark played.
///
/// It is shaped for the background isolate, where the main isolate's service locator and its memory-only
/// access token do not exist (`auth_token_provider.dart`).
/// Every dependency is a constructor-injected callback, so the chain is locator-free.
/// It runs the same in a fresh isolate and in a unit test with an empty GetIt.
///
/// Rules:
///   - The FCM payload is content-free. Content arrives only through the authenticated fetch.
///   - The spoken text is the TTS-brevity `message` field only, never abstract or payload bodies.
///   - Speech is strictly one utterance, because of a rapid-repeat crash (`flutter_tts` issue 260).
///   - The chain never touches the WebSocket.
///   - The speak toggles are the only gate on speech. The foreground pause is bloc state and does not persist.
///   - A wake is a summons, not proof of disconnection, so the chain infers nothing about the connection state.
library;

import 'dart:async' show TimeoutException;

import 'notification_sender_label.dart';
import 'notification_tap_payload.dart';
import 'unplayed_queue_order.dart';
import '../tts/tts_preview_truncator.dart';

/// Result of one wake, logged so the chain can be debugged from `adb logcat`.
///
/// Every wake logs the reason, the number fetched, whether a notification was shown, and whether it spoke or was muted.
class FcmWakeOutcome {
  /// False for an unknown wake type, which is logged and ignored.
  final bool   handled;   // false ⇒ unknown type, logged + ignored
  /// Wake payload reason, or `n/a`.
  final String reason;    // wake payload reason (or 'n/a')
  /// Number of unplayed items the fetch returned.
  final int    fetched;   // how many UNPLAYED items the fetch returned
  /// Whether a notification was posted.
  final bool   shown;
  /// Whether an item was spoken; false with `shown` true means prefs muted it.
  final bool   spoke;     // false + shown=true ⇒ muted by prefs
  /// Free-text detail for the log line.
  final String detail;

  /// Creates an outcome; every field is required.
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

/// Credentials the bootstrap reads from secure storage: refresh token and last email.
///
/// The access token is memory-only and never exists in a fresh isolate. The email is for the fetch path.
class FcmWakeCredentials {
  /// Refresh token from secure storage.
  final String refreshToken;
  /// Last authenticated email.
  final String userEmail;
  /// Creates credentials.
  const FcmWakeCredentials( {
    required this.refreshToken,
    required this.userEmail,
  } );
}

/// Title of the fallback notification a wake shows when it has nothing better.
///
/// A `ws_wake` must end in a visible notification every time. FCM watches whether high-priority messages produce one.
/// When they do not, it quietly downgrades them to normal priority, and normal-priority messages wait out Doze.
/// So every path that would end silently posts a fallback: no stored login, nothing undelivered, a failed fetch.
/// Tapping it opens the app, whose normal start reconnects the socket.
/// Design: src/rnd/2026.09.28-background-wake-socket-problem-statement-response.md
const String kFcmWakeFallbackTitle   = 'Lupin';
/// Body of the fallback notification when nothing is undelivered or a step failed.
const String kFcmWakeFallbackBody    = 'New activity. Open Lupin to see it.';
/// Body of the fallback notification when no login is stored.
const String kFcmWakeSignedOutBody   = 'New activity. Open Lupin and sign in to see it.';

/// How long the chain may spend reaching a visible notification before it posts the fallback.
///
/// A hang is worse than an error, because the fallback lives in the catch arm. An exception reaches it.
/// A call that never returns and never throws does not, so the wake ends with an empty shade.
/// Android then reclaims the isolate, and FCM starts downgrading high-priority messages (see [kFcmWakeFallbackTitle]).
/// Transport timeouts alone cannot close this: secure storage, SharedPreferences and the notification plugin
/// are all on the path and none of them is Dio.
///
/// The budget covers only the pre-notification phase: credentials, exchange, fetch and show.
/// Past that the contract is met, speech has its own catch, and mark-played must not be skipped.
/// It is about 20 s of the Android handler's roughly 30 s, leaving room for speech and the ledger.
const Duration kFcmWakeShowBudget = Duration( seconds: 20 );

/// How long the fallback notification itself may take.
///
/// It needs its own budget. The fallback goes out through the same `showNotification` seam.
/// If that seam hung, the catch arm would hang on it too and the main timeout would have bought nothing.
/// It is short, because the main budget is already spent when this runs.
const Duration kFcmWakeFallbackBudget = Duration( seconds: 5 );

/// How long the utterance may take.
///
/// A try/catch around speak() catches a throw and does nothing about a hang, and they are different failures.
/// The show budget stops at the shade, which meets the contract for the shade but not for what follows.
/// `speak` awaits `awaitSpeakCompletion`, so a wedged TTS engine parks the handler until Android reclaims the isolate.
/// Mark-played then never runs, the queue head stays unplayed, and every later notification is invisible.
/// So speech gets a budget of its own, and the ledger write gets one too ([kFcmWakeMarkPlayedBudget]).
/// Both are generous enough for real work and short enough that the handler ends instead of being killed.
const Duration kFcmWakeSpeakBudget      = Duration( seconds: 12 );
/// Budget for the mark-played ledger write.
const Duration kFcmWakeMarkPlayedBudget = Duration( seconds: 5 );

/// The whole handler's window, from the first statement to the return.
///
/// The Android handler gets roughly 30 s, and this leaves a margin under it.
///
/// The show budget stops at the shade. Past it, speak and mark-played each had a per-call budget, and the wake drains up to
/// [kFcmWakeDrainMax] items, so those budgets stacked once per item. Speech and the ledger write now draw down from this one
/// deadline. The drain does not start an item it could not finish marking played, because a shown-but-unmarked item is
/// re-shown by the next wake.
const Duration kFcmWakeHandlerBudget = Duration( seconds: 27 );

/// The most unplayed items one wake shows.
///
/// The server wakes only for a new notification, so a backlog would otherwise sit unseen behind the first item
/// until the app opened. The cap stops a long backlog flooding the shade or outrunning the handler window.
/// Whatever is past the cap stays unplayed.
/// Design: src/docs/decisions/README.md (R-PUSH-drain-each)
const int kFcmWakeDrainMax = 5;

/// The wake chain with every dependency injected; see the library note.
class FcmWakeChain {
  /// Secure-storage seam: refresh token and last email, or null when never logged in here.
  ///
  /// "Here" means this device and server context.
  final Future<FcmWakeCredentials?> Function() readCredentials;

  /// Auth seam: exchanges the refresh token for a fresh access token with `POST /auth/refresh`.
  ///
  /// See `auth_repository.dart`.
  final Future<String> Function( String refreshToken ) exchangeForAccessToken;

  /// Fetch seam: the user's unplayed notifications, as raw wire maps.
  ///
  /// The chain reads only `id`, `message`, `priority` and `timestamp`, plus what `notificationSenderLabel` and
  /// `NotificationTapPayload` need.
  /// It fetches a list, not `/next`, which returns only the oldest unplayed item. With per-priority filtering that is
  /// a trap. A `low` the user switched off sits at the head and must not be consumed (see [itemAllowed]).
  /// So every later wake re-fetches it, and an `urgent` behind it never reaches the phone.
  /// Design: src/docs/decisions/README.md (R-PUSH-list-not-next)
  final Future<List<Map<String, dynamic>>> Function(
      String userEmail, String accessToken ) fetchUnplayed;

  /// Local-notification seam; the plugin is re-initialized inside the handler.
  ///
  /// The third argument is the tap payload, the encoded `{notification_id, sender_id}` of the item shown.
  /// It is null when no item is behind the notification, which is every fallback path.
  /// Android stores it in the notification's intent, the only channel that survives this isolate dying,
  /// the phone locking and the user tapping an hour later.
  final Future<void> Function( String title, String body, String? payload )
      showNotification;

  /// Prefs seam: may this priority speak?
  ///
  /// It reads the persisted speak toggles and mirrors the legacy policy. Low and medium never speak,
  /// high speaks if speakOnHigh, urgent speaks if speakOnUrgent, and the master mute silences everything.
  final Future<bool> Function( String priority ) shouldSpeak;

  /// Prefs seam: the TTS slider fraction (`NotificationPreferences.ttsFraction`).
  ///
  /// The background path honors it as the foreground orchestrator does: 0% speaks nothing and anything else is cut the same way.
  /// Design: src/docs/decisions/README.md (R-NA-tts-fraction)
  final Future<double> Function() ttsFraction;

  /// TTS seam: one utterance, on a fresh flutter_tts instance.
  final Future<void> Function( String message ) speak;

  /// Dedupe seam: marks the item played after the speak, so a repeat wake fetches nothing.
  ///
  /// The server-side durable store is the dedupe ledger. Failures are swallowed.
  final Future<void> Function( String notificationId, String accessToken )
      markPlayed;

  /// Prefs seam, gate A: could a background notification be raised at any priority?
  ///
  /// It is checked first, before credentials, and not merely before `showNotification`.
  /// A wake that fetched an item and marked it played without showing anything would consume it.
  /// The server's unplayed queue is what the foreground rehydrates from, so the user would never see the item.
  /// That is deletion rather than silence. Off must also cost no radio and no battery,
  /// which holds only if nothing before the notification runs either.
  /// Design: src/docs/decisions/README.md (R-NA-wake-switch)
  final Future<bool> Function() backgroundAllowsAnyPriority;

  /// Prefs seam, gate B: may this item be raised in the background?
  ///
  /// It gets the priority, defaulted to `medium` when absent, and the whole item.
  /// Mute-by-sender and quiet hours need to know who sent it, not just how loudly.
  /// A denied item is skipped, never consumed. It is not shown, spoken or marked played.
  /// It is still unplayed on the server when the app opens and the list rehydrates.
  /// That is silence, not deletion, the same rule gate A enforces one step later.
  final Future<bool> Function( String priority, Map<String, dynamic> item ) itemAllowed;

  /// Debug-hook seam: one line per chain step, visible in adb.
  final void Function( String line ) log;

  /// Deadline for reaching a visible notification ([kFcmWakeShowBudget]).
  ///
  /// Injectable so tests can prove the hang path in milliseconds.
  final Duration showBudget;

  /// Deadline for the fallback notification itself ([kFcmWakeFallbackBudget]).
  final Duration fallbackBudget;

  /// Deadline for the utterance ([kFcmWakeSpeakBudget]).
  ///
  /// Injectable so a test can prove a hung speak in milliseconds. [markPlayedBudget] bounds the ledger write after it.
  final Duration speakBudget;
  /// Deadline for the mark-played write ([kFcmWakeMarkPlayedBudget]).
  final Duration markPlayedBudget;

  /// Deadline for the whole handler ([kFcmWakeHandlerBudget]).
  ///
  /// Speech and mark-played are cut to whatever it has left.
  final Duration handlerBudget;

  /// Creates a chain from its seams; the budgets default to the `kFcmWake*` constants.
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
    this.handlerBudget    = kFcmWakeHandlerBudget,
  } );

  /// Handles one wake payload and never throws.
  ///
  /// The FCM handler budget is about 30 s and a crashed handler helps nobody, so every failure path logs and returns an outcome.
  Future<FcmWakeOutcome> handleWake( Map<String, dynamic> data ) async {
    final type   = data[ 'type' ]?.toString() ?? '';
    final reason = data[ 'reason' ]?.toString() ?? 'n/a';

    if ( type != 'ws_wake' ) {
      // Defensive: an unknown type is logged and ignored.
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

    // Set once the real notification is posted, so a failure after that point (speak, mark-played) never adds a fallback on top of it.
    var shown = false;

    // One deadline is shared by every step on the way to the notification, not a per-call timeout.
    // Four calls each allowed the full budget would let the handler run four times over its window and be reclaimed anyway.
    final deadline = DateTime.now().add( showBudget );
    Duration remaining() {
      final left = deadline.difference( DateTime.now() );
      return left.isNegative ? Duration.zero : left;
    }

    // The overall deadline, across the pre-notification phase and the drain loop.
    final overallDeadline = DateTime.now().add( handlerBudget );
    Duration overallRemaining() {
      final left = overallDeadline.difference( DateTime.now() );
      return left.isNegative ? Duration.zero : left;
    }
    Duration lesser( Duration a, Duration b ) => a < b ? a : b;
    // Speech may not eat the time mark-played needs, so it is cut short of it.
    Duration speechLeft() {
      final left = overallRemaining() - markPlayedBudget;
      return lesser( speakBudget, left.isNegative ? Duration.zero : left );
    }

    try {
      // Gate A: could a background notification be raised at any priority?
      // Nothing is fetched, shown, spoken or marked played, so the queue is left as it was and opening the app still surfaces everything.
      //
      // It is inside the try on purpose. Outside it, a SharedPreferences failure in a fresh isolate would escape `handleWake`.
      // That breaks the never-throws contract, because `fcmBackgroundHandler` awaits it with no try of its own,
      // and the wake would die with nothing shown and nothing logged. Inside, a failure takes the ordinary path:
      // a fallback notification and an error outcome. For an unreadable switch that is right, because "cannot tell" must not mean "off".
      //
      // It is the first statement in the try, ahead of credentials, so off costs no radio and no battery.
      // Off posts no fallback. That is a deliberate exception to the every-wake-ends-visible rule above:
      // the rule stops FCM downgrading our messages, but it cannot outrank the user asking for quiet, or the setting is decorative.
      // The asymmetry is intended: an unreadable switch does get the fallback.
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

      // The exchange is unavoidable: the access token is memory-only and this isolate is fresh.
      // The Phase-0 probe asserts this log line.
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

      // Gate B and drain: oldest first, up to [kFcmWakeDrainMax] items this user still wants, each its own notification.
      // The server wakes only for a new notification, so an item behind the first would stay invisible until the app opened.
      // Everything skipped, or left over past the cap or the budget, is left as found: unshown, unspoken and unplayed.
      // Design: src/docs/decisions/README.md (R-PUSH-drain-each)
      final ordered    = oldestFirst( unplayed );
      final shownIds   = <String>[];
      var   skipped    = 0;
      var   spoke      = false;
      // The read is budgeted too, for the same reason as gate A.
      // It is a prefs read in a fresh isolate before the notification, and here it runs once per skipped item.
      // A storage layer gone slow rather than broken is multiplied by the length of the denied run.
      // Sharing the one `remaining()` deadline keeps that bounded. A wedged read throws into the catch and posts the fallback.
      for ( final candidate in ordered ) {
        if ( shownIds.length >= kFcmWakeDrainMax ) break;
        try {
          // Out of time: stop draining. Nothing is consumed that was not shown.
          // Never before the first item: that one takes the ordinary path, where a spent budget throws into the catch arm and posts the fallback.
          if ( shownIds.isNotEmpty &&
               ( remaining() == Duration.zero || overallRemaining() <= markPlayedBudget ) ) {
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

          // The title is who sent it, not the item's own `title`.
          // `notificationSenderLabel` is total and always returns something, so the title cannot come out blank.
          // Design: src/docs/decisions/README.md (R-PUSH-sender-label)
          final title = notificationSenderLabel( candidate );
          log( '[FcmWake] fetched ${ordered.length}, showing id=$id '
               'priority=$priority from="$title"' );

          // The payload is built from `candidate`, the item being shown, never from the wake `data`.
          // The push is content-free and the queue head is not necessarily what triggered this wake.
          // The notification on the lock screen and the conversation a tap opens agree only if both come from the same map.
          // The deadline covers the post itself: a wedged plugin here is the last thing between a wake and an empty shade.
          await showNotification(
            title, message,
            NotificationTapPayload.fromNotification( candidate )?.encode(),
          ).timeout( remaining() );
          shown = true;
          shownIds.add( id );
          log( '[FcmWake] shown' );

          // Only the first shown item is spoken. Speech is strictly one utterance (`flutter_tts` issue 260),
          // and five messages read aloud back to back is a pile-up, not a summary. The rest are visible and marked below.
          //
          // Only the `message` field is spoken, gated by prefs. Audio is best-effort: if the OS reclaims the isolate mid-utterance,
          // it truncates and nothing is lost, because the server-side store and the foreground rehydration keep the item.
          // There is no automatic re-speak; badges carry it.
          //
          // Best-effort means the mark-played below still runs. If a throwing TTS engine skipped the dedupe,
          // the queue head would keep coming back, the next wake would re-show the same notification and fail to speak it again,
          // and the head would never move. One dead TTS engine would make every later notification invisible.
          // Speech may fail; the ledger write is what keeps the queue moving.
          if ( shownIds.length == 1 ) {
            try {
              // The prefs reads are budgeted too. In a fresh isolate a wedged SharedPreferences can park the handler
              // as well as a wedged engine can, and it would do so before anything was spoken.
              final maySpeak = await shouldSpeak( priority ).timeout( speechLeft() );
              final fraction = maySpeak
                  ? await ttsFraction().timeout( speechLeft() )
                  : 0.0;
              if ( !maySpeak ) {
                log( '[FcmWake] muted by speak-toggle prefs' );
              } else if ( TtsPreviewTruncator.silences( fraction ) ) {
                log( '[FcmWake] muted by the TTS slider at 0%' );
              } else {
                await speak( TtsPreviewTruncator.previewFor( message, fraction ) )
                    .timeout( speechLeft() );
                spoke = true;
                log( '[FcmWake] spoke (message field only)' );
              }
            } on TimeoutException catch ( _ ) {
              // Named apart from a throw because a timeout has no floor: nothing is raised, so nothing is caught,
              // and the handler would simply stop here with the ledger unwritten.
              log( '[FcmWake] speech exceeded its ${speakBudget.inSeconds}s budget — '
                   'abandoned, and the wake continues to mark-played' );
            } catch ( e ) {
              // Covers the prefs reads too: a failed SharedPreferences lookup is no more entitled to strand the queue than a failed utterance.
              log( '[FcmWake] speak failed (best-effort): $e' );
            }
          }

          // Marked only now that this item is shown, so an item the budget or the cap cut off is never consumed.
          if ( id.isNotEmpty ) {
            try {
              await markPlayed( id, accessToken )
                  .timeout( lesser( markPlayedBudget, overallRemaining() ) );
              log( '[FcmWake] marked played (dedupe)' );
            } catch ( e ) {
              log( '[FcmWake] mark-played failed (best-effort): $e' );
            }
          }
        } catch ( e ) {
          // The first item keeps the ordinary failure path: fallback and an error outcome.
          // Once something is visible, a later item failing just ends the drain, and what is left stays unplayed for the next wake or the app.
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
        // Every waiting item is one the user asked not to hear about.
        // Silence is the point, so no notification and no fallback, and nothing is consumed: opening the app still shows the lot.
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
      // A timeout is named separately because it is otherwise invisible: nothing threw, so nothing was logged and nothing was shown.
      // The abandoned call keeps running, because Dart cannot cancel it. If it completes after the deadline it may post its own notification too.
      // Two notifications is the acceptable trade for never posting zero.
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

  /// Posts the fallback notification; never throws.
  ///
  /// It returns whether the post succeeded, so a plugin failure is reported as `shown=false` rather than lost.
  Future<bool> _showFallback( String body ) async {
    try {
      // No payload: a fallback stands for "something happened" with no item behind it, so a tap has no conversation to open
      // and lands on Focus mode. An id-less payload would be worse than none, because it would occupy the tap router's single slot for nothing.
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
