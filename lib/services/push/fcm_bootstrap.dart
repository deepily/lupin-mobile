/// S5 Firebase bootstrap — EVERYTHING here is gated behind the
/// compile-time flag (F-S5-2.i, repo precedent `performance_monitor.dart` /
/// `streaming_tts_player.dart`):
///
///   flutter build apk --dart-define=ENABLE_FCM=true
///
/// Default OFF (AC-S5.4): Stage-1 builds carry NO hard dependency on
/// `google-services.json`. OSQ-7 (EXECUTOR: HUMAN, laptop-side — see
/// `src/rnd/2026.06.11-focus-mode-voice-chat/91-osq7-firebase-console-runbook.md`)
/// provisions the Firebase project; the SAME laptop pass completes the
/// wiring this file expects but does not require:
///   1. drop `google-services.json` into `android/app/`
///   2. apply the google-services gradle plugin
///      (`com.google.gms.google-services`) in `android/app/build.gradle.kts`
///      + its classpath in `android/settings.gradle.kts`
/// Neither is committed yet — applying the plugin WITHOUT the json breaks
/// every build, so the gradle wiring rides the OSQ-7 pass (documented in
/// the S5 Phase-0 probe runbook, 92-s5-phase0-fcm-probe-runbook.md).
library;

import 'dart:convert';
import 'dart:ui' show DartPluginRegistrant;

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/di/service_locator.dart';
import '../auth/auth_repository.dart';
import '../auth/secure_credential_store.dart';
import '../auth/server_context_service.dart';
import '../notification_audio/notification_preferences.dart';
import '../websocket/websocket_service.dart';
import 'fcm_wake_chain.dart';
import 'fcm_wakeup_service.dart';

/// Grep-able flag pin (AC-S5.4): `--dart-define=ENABLE_FCM`.
const bool kEnableFcm = bool.fromEnvironment( 'ENABLE_FCM', defaultValue: false );

/// Network budgets for the BACKGROUND wake isolate (review F2, row 8ff78c69).
///
/// The Android background-message handler gets roughly 30 s. Three calls share
/// it — refresh, `/next`, mark-played — and an utterance follows, so each one
/// is capped well inside that. They are deliberately TIGHTER than the
/// foreground's (`http_service.dart:46-48`): out here a slow answer is worth
/// less than a prompt fallback notification, because the fallback is what keeps
/// FCM treating our wakes as high priority.
const Duration kFcmBackgroundConnectTimeout = Duration( seconds: 6 );
const Duration kFcmBackgroundSendTimeout    = Duration( seconds: 6 );
const Duration kFcmBackgroundReceiveTimeout = Duration( seconds: 8 );

/// Real [FcmTokenSource] over FirebaseMessaging (main isolate only).
class FirebaseTokenSource implements FcmTokenSource {
  final FirebaseMessaging _messaging;
  FirebaseTokenSource( this._messaging );

  @override
  Future<String?> getToken() => _messaging.getToken();

  @override
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;
}

FcmWakeupService? _service;

/// Main-isolate init, called from `main()` AFTER the service locator is
/// up. No-op when the flag is OFF (the default — Stage-1 regression
/// safety, AC-S5.4).
Future<FcmWakeupService?> initFcmIfEnabled() async {
  if ( !kEnableFcm ) return null;

  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage( fcmBackgroundHandler );

  final service = FcmWakeupService(
    tokenSource : FirebaseTokenSource( FirebaseMessaging.instance ),
    dio         : ServiceLocator.get<Dio>(),   // shared auth-wired instance
  );
  _service = service;

  // Foreground data message: no-op beyond a debug log (§3.2.3 — the WS
  // is already live; speech ownership stays with FocusChatBloc).
  FirebaseMessaging.onMessage.listen( ( m ) {
    debugPrint( '[FcmWakeup] foreground data message ignored '
        '(type=${m.data[ 'type' ]}, WS is live)' );
  } );

  // Token-lifecycle writer 3 (F-S6-S2-1(b)): every authenticated WS
  // (re)connect re-registers — idempotent upsert. auth_success frames
  // mark both the initial connect AND every reconnect.
  final ws = ServiceLocator.get<WebSocketService>();
  ws.stream.listen( ( frame ) {
    if ( frame is Map && frame[ 'type' ] == 'auth_success' ) {
      _service?.onWsReconnected();
    }
  } );

  return service;
}

/// Auth-state hooks — called by the app layer on the existing auth-state
/// stream's transitions (the same signal AuthGate renders on; Arnold
/// residual #1). Safe no-ops when FCM is disabled.
Future<void> fcmOnAuthenticated( String userEmail ) async =>
    _service?.onAuthenticated( userEmail );

Future<void> fcmOnLoggedOut() async => _service?.onLoggedOut();

/// Background data-message handler (§3.2.4, USER-RULED shape (2)
/// "handler-does-the-work"). Runs in a FRESH isolate: empty service
/// locator, main isolate possibly dead. It bootstraps its OWN minimal
/// dependencies and runs the locator-free [FcmWakeChain] —
/// token-exchange → fetch → show → ONE speak → mark played.
@pragma( 'vm:entry-point' )
Future<void> fcmBackgroundHandler( RemoteMessage message ) async {
  // Fresh-engine plugin access (secure storage / prefs / asset bundle).
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  final chain = await buildBackgroundWakeChain();
  final outcome = await chain.handleWake( message.data );
  // The §4 debug hook's terminal line — one summary per wake.
  debugPrint( '[FcmWake] outcome: $outcome' );
}

/// POST /auth/refresh from the background isolate, and SAVE the rotated
/// refresh token before returning the access token.
///
/// 🔴 THE SERVER ROTATES REFRESH TOKENS: every exchange revokes the token it
/// was given and returns a new one. Measured on Rick's phone 2026-09-28 (row
/// 8ff78c69): the first wake refreshed with 200 and discarded the new token,
/// so the second wake presented a revoked one and got 401. The foreground
/// interceptor reads the SAME stored token, so the next foreground refresh
/// would have failed as well, which means a silent log-out. The foreground
/// already persists rotations (`service_locator.dart`, `onTokensRotated`);
/// this is the background half of the same rule.
///
/// 🔴 AND THE WRITE IS THE FRAGILE HALF, NOT THE EXCHANGE (review F5). Between
/// the exchange returning and the store accepting, the only copy of a usable
/// refresh token is a local variable: the old one is already revoked. A write
/// that fails there loses the account outright — and the likeliest cause is
/// exactly the state a Doze wake runs in, a device booted but never unlocked,
/// where the Android keystore is not yet available. So the write is RETRIED, and
/// if it still will not land we keep the wake (the user sees their notification)
/// and say so unmistakably in the log, because the next foreground refresh is
/// going to fail and somebody will need to know why.
///
/// Requires:
///   - refreshToken is the token currently stored for contextId
/// Ensures:
///   - returns the new access token
///   - the rotated refresh token is written to the store before returning, or
///     [kFcmRefreshWriteLostMarker] is logged and the wake still completes
/// Raises:
///   - AuthException on a failed or malformed exchange (the chain turns it
///     into the fallback notification); nothing is written in that case
@visibleForTesting
Future<String> exchangeRefreshAndPersist( {
  required Dio                   dio,
  required SecureCredentialStore store,
  required String                contextId,
  required String                refreshToken,
  void Function( String )?       logSink,
} ) async {
  // The SAME parser the foreground uses. The server answers
  // `{message, user?, tokens: {access_token, refresh_token}}`, and a second,
  // hand-rolled reader of that envelope is how this path read the tokens at the
  // TOP level, got null, threw after the exchange had already revoked the old
  // token, and never fetched anything (emulator logcat, 2026-09-28 16:47).
  final repo = AuthRepository( dio );

  AuthTokens tokens;
  try {
    tokens = await repo.refresh( refreshToken );
  } on AuthException catch ( e ) {
    // 🔴 A 401 HERE USUALLY MEANS WE LOST A RACE, NOT THAT THE USER IS SIGNED
    // OUT. This isolate and the foreground's AuthInterceptor share ONE stored
    // refresh token and the server revokes on every exchange, so when a wake
    // lands while the app is backgrounded-but-alive, both can present the same
    // token; the loser's copy is already revoked. Treating that as a dead
    // session is what turned an ordinary collision into a forced re-login.
    //
    // So: re-read the store. If the winner has already written a NEW token,
    // that token is valid and this attempt simply arrived second — use it.
    // Exactly one retry, and only when the stored value actually CHANGED: a
    // 401 on the same token we just read is a genuinely dead session, and
    // retrying it in a loop would be a log-out with extra steps.
    if ( e.statusCode != 401 ) rethrow;
    final current = await store.readRefreshToken( contextId );
    if ( current == null || current == refreshToken ) rethrow;
    tokens = await repo.refresh( current );
  }

  await _persistRotatedRefreshToken(
    store     : store,
    contextId : contextId,
    token     : tokens.refreshToken,
    log       : logSink ?? debugPrint,
  );
  return tokens.accessToken;
}

/// The one log line that says "this account is about to need a re-login, and
/// here is why". Grep-able on purpose: it is the only warning anyone gets.
const String kFcmRefreshWriteLostMarker = '[FcmWake] ROTATED REFRESH TOKEN LOST';

/// How many times the rotated-token write is attempted before giving up.
const int kFcmRefreshWriteAttempts = 3;

/// Write the rotated refresh token, retrying a transient storage failure.
///
/// The retry is worth having because the failure this guards against is
/// overwhelmingly transient: a wake that fires on a booted-but-never-unlocked
/// device finds the keystore unavailable for a moment, not forever.
///
/// Ensures:
///   - the token is stored, or [kFcmRefreshWriteLostMarker] is logged
///   - never throws: by this point the old token is already revoked, so failing
///     the wake as well would cost the notification and save nothing
Future<void> _persistRotatedRefreshToken( {
  required SecureCredentialStore store,
  required String                contextId,
  required String                token,
  required void Function( String ) log,
} ) async {
  for ( var attempt = 1; attempt <= kFcmRefreshWriteAttempts; attempt++ ) {
    try {
      await store.writeRefreshToken( contextId, token );
      if ( attempt > 1 ) log( '[FcmWake] rotated refresh token saved on attempt $attempt' );
      return;
    } catch ( e ) {
      if ( attempt == kFcmRefreshWriteAttempts ) {
        log( '$kFcmRefreshWriteLostMarker after $attempt attempts: $e — the old '
             'token is revoked and the new one could not be stored, so the next '
             'refresh will 401 and force a password re-login' );
        return;
      }
      log( '[FcmWake] refresh-token write failed (attempt $attempt), retrying: $e' );
      await Future<void>.delayed( kFcmRefreshWriteRetryDelay );
    }
  }
}

/// Gap between write attempts — long enough for a keystore that is coming up,
/// short enough to stay inside the handler budget three times over.
const Duration kFcmRefreshWriteRetryDelay = Duration( milliseconds: 250 );

/// The system user id (the JWT `sub` claim) carried by a Lupin access token.
///
/// Requires:
///   - jwt is a three-part JWT whose payload has a non-empty string `sub`
/// Ensures:
///   - returns that `sub`; nothing is verified, since the server does that
/// Raises:
///   - FormatException when the token is malformed or has no `sub`
@visibleForTesting
String userIdFromAccessToken( String jwt ) {
  final parts = jwt.split( '.' );
  if ( parts.length != 3 ) throw const FormatException( 'access token is not a JWT' );
  final payload = jsonDecode(
      utf8.decode( base64Url.decode( base64Url.normalize( parts[ 1 ] ) ) ) );
  final sub = payload is Map ? payload[ 'sub' ] : null;
  if ( sub is! String || sub.isEmpty ) {
    throw const FormatException( 'access token carries no sub claim' );
  }
  return sub;
}

/// GET the user's next unplayed notification, addressed by SYSTEM USER ID.
///
/// 🔴 NOT BY EMAIL. `GET /api/notifications/{user_id}/next` compares the path
/// segment against each queued item's `user_id`, which is the account's UUID
/// (lupin `notifications.py`: "The system user ID (not email)"). This path used
/// to send the email, so every wake fetched nothing and fell back to "New
/// activity" (emulator logcat, 2026-09-28 17:02: `fetched 0` three times while
/// notifications were queued). The id comes from the access token just issued,
/// so the background isolate needs nothing else stored.
///
/// Ensures:
///   - returns the `notification` map, or null when there is none
@visibleForTesting
Future<Map<String, dynamic>?> fetchNextForAccessToken( {
  required Dio    dio,
  required String accessToken,
} ) async {
  final userId = userIdFromAccessToken( accessToken );
  final res    = await dio.get<Map<String, dynamic>>(
    '/api/notifications/${Uri.encodeComponent( userId )}/next',
    options: Options( headers: { 'Authorization': 'Bearer $accessToken' } ),
  );
  final notif = res.data?[ 'notification' ];
  return notif is Map<String, dynamic> ? notif : null;
}

/// The notification channel wake notifications are posted on.
///
/// 🔴 THE `_v2` IS LOAD-BEARING, AND THAT IS THE WHOLE POINT OF IT. Android fixes
/// a channel's importance when the channel is CREATED and ignores every later
/// change, so lowering `importance` in the code below reached nobody who already
/// had the app: the original `lupin_fcm_wake` kept the high importance it was
/// first registered with, and a heads-up banner at 3am kept happening. A new id
/// is the only way the new importance actually applies to an existing install
/// (Tiffany's ruling, 2026-09-28, row 1af7b3de).
///
/// The cost of a new id is an orphan: the old channel stays in the system
/// notification settings forever, as a second "Lupin background notifications"
/// row the user can see and toggle to no effect. Hence
/// [kFcmWakeChannelIdLegacy] and the delete below.
const String kFcmWakeChannelId       = 'lupin_fcm_wake_v2';

/// The pre-v2 channel. Deleted on init so the bump does not leave a dead row in
/// the user's notification settings. Keep this list growing if the id is ever
/// bumped again — a deleted channel that no longer exists deletes harmlessly, so
/// the call is idempotent and safe to repeat on every wake.
const String kFcmWakeChannelIdLegacy = 'lupin_fcm_wake';

/// The details every wake notification is posted with.
///
/// Extracted so a test can assert the channel id and the importance. Inline in
/// the `showNotification` closure they were unreachable: that closure only runs
/// with a live platform channel behind it.
@visibleForTesting
NotificationDetails wakeNotificationDetails() => const NotificationDetails(
  android: AndroidNotificationDetails(
    kFcmWakeChannelId,
    'Lupin background notifications',
    channelDescription: 'Notifications fetched on FCM silent-relay wake-up',
    // Rick 2026-09-28 (row 1af7b3de): default, not high — a wake that arrives
    // overnight should land in the shade, not take over the screen with a
    // heads-up banner. This does NOT weaken the slice-2 contract: FCM watches
    // whether a high-priority MESSAGE produces a notification at all, not what
    // importance that notification carries, so wakes stay high-priority end to
    // end.
    importance : Importance.defaultImportance,
    priority   : Priority.defaultPriority,
  ),
);

/// Remove the pre-v2 channel, so bumping the id does not leave the user staring
/// at two identically-named rows in their notification settings, one of which
/// does nothing.
///
/// Requires:
///   - deleteChannel deletes an Android notification channel by id
/// Ensures:
///   - [kFcmWakeChannelIdLegacy] is deleted, and the CURRENT id never is
///   - never throws: an orphan row is cosmetic, and losing the wake over it
///     would not be
@visibleForTesting
Future<void> deleteLegacyWakeChannel(
  Future<void> Function( String channelId ) deleteChannel,
) async {
  try {
    await deleteChannel( kFcmWakeChannelIdLegacy );
  } catch ( e ) {
    debugPrint( '[FcmWake] could not delete the legacy notification channel '
        '"$kFcmWakeChannelIdLegacy" (cosmetic, ignored): $e' );
  }
}

/// Post one wake notification, CARRYING ITS TAP PAYLOAD (row d9bc6f6c).
///
/// 🔴 EXTRACTED FROM THE CHAIN'S LAMBDA SO IT CAN BE TESTED, and that is not
/// tidiness. `fcm_wake_chain_test` exercises the `showNotification` SEAM by
/// supplying its own lambda — so deleting `payload:` from the production call
/// below left the entire suite green. Measured exactly that way: the mutation
/// was made deliberately, the whole push suite passed, and `flutter analyze`
/// reported nothing. That is the uninjected-seam shape this repo has been bitten
/// by before (bug 9adff476), and a seam nothing covers is a seam that will be
/// silently deleted.
///
/// Requires:
///   - plugin is an initialized FlutterLocalNotificationsPlugin
///
/// Ensures:
///   - the notification is posted on [kFcmWakeChannelId] (the v2 channel) at
///     DEFAULT importance and priority, via [wakeNotificationDetails]
///     (row 1af7b3de)
///   - `payload` reaches the plugin VERBATIM, including null
@visibleForTesting
Future<void> showWakeNotification(
  FlutterLocalNotificationsPlugin plugin,
  String  title,
  String  body,
  String? payload,
) async {
  await plugin.show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000,
    title,
    body,
    wakeNotificationDetails(),
    // Android persists this in the notification's intent — the ONLY carrier
    // that survives this isolate being killed. The main isolate reads it back
    // from the launch intent whenever the tap is what started the app, which is
    // the case Rick reported.
    payload: payload,
  );
}

/// What the background isolate can know about who is logged in.
///
/// 🔴 THE REFRESH TOKEN IS THE ONLY CREDENTIAL THIS PATH NEEDS (review F9). The
/// stored email used to be required here as well, from when the fetch was
/// addressed by email. Since the fetch moved to the JWT `sub` claim the seam
/// discards it outright (`fetchNextNotification: ( _, accessToken )`), so
/// demanding it could only ever produce a FALSE "Open Lupin and sign in" for a
/// user who is signed in perfectly well — silently, and with no fetch attempted.
///
/// Unreachable on today's code, because every path that stores a refresh token
/// has an email by then (`auth_bloc.dart` writes both at login). Changed anyway,
/// and pulled out of the chain builder so it can be tested: the coupling was
/// undocumented, and the day anything stores a token without an email — an
/// import, a context migration, a token-only sign-in — the failure is invisible.
///
/// Requires:
///   - contextId is the active server context
/// Ensures:
///   - null iff there is no stored refresh token (never logged in here)
///   - otherwise credentials, with an EMPTY email when none is stored
@visibleForTesting
Future<FcmWakeCredentials?> readWakeCredentials( {
  required SecureCredentialStore store,
  required String                contextId,
} ) async {
  final refresh = await store.readRefreshToken( contextId );
  if ( refresh == null ) return null;
  final email = await store.readLastEmail( contextId );
  return FcmWakeCredentials( refreshToken: refresh, userEmail: email ?? '' );
}

/// Build the chain from REAL background-isolate dependencies. Split out
/// of the handler so the Phase-0 probe can reuse it verbatim. NOTE: no
/// ServiceLocator access anywhere below — everything is constructed
/// fresh (isolate boundary; AC-S5.3's zero-locator rule holds for the
/// production wiring too).
Future<FcmWakeChain> buildBackgroundWakeChain() async {
  final prefs   = await SharedPreferences.getInstance();
  final context = await ServerContextService.load( prefs );
  final store   = SecureCredentialStore();
  final audio   = NotificationPreferences( prefs );
  final dio     = Dio( BaseOptions(
    baseUrl        : context.baseUrl,
    // 🔴 A WAKE THAT HANGS POSTS NOTHING, AND THAT IS THE ONE OUTCOME THIS
    // WHOLE PATH EXISTS TO PREVENT. This Dio carries all three calls of the
    // wake (refresh, /next, mark-played) and used to set no timeouts at all,
    // which for Dio means none. A half-open socket — captive-portal Wi-Fi, a
    // dying LTE cell — parks `handleWake` forever: the fallback notification
    // lives in the chain's CATCH arm, so a call that never returns and never
    // throws never reaches it, and Android eventually kills the isolate in
    // silence. FCM watches whether high-priority messages produce a
    // notification and downgrades them to normal when they don't (see
    // kFcmWakeFallbackBody), so one bad network event degrades every LATER
    // wake too. Budgets chosen to leave room under the ~30 s handler window
    // for all three calls plus the utterance; `http_service.dart:46-48` is the
    // foreground precedent (Pocholo's review F2, row 8ff78c69).
    connectTimeout : kFcmBackgroundConnectTimeout,
    sendTimeout    : kFcmBackgroundSendTimeout,
    receiveTimeout : kFcmBackgroundReceiveTimeout,
  ) );

  final localNotifications = FlutterLocalNotificationsPlugin();
  await localNotifications.initialize( const InitializationSettings(
    android: AndroidInitializationSettings( '@mipmap/ic_launcher' ),
  ) );

  // The v2 channel bump's other half: drop the pre-v2 channel so the user is not
  // left with two identically-named rows in their notification settings, one of
  // them dead. Idempotent — deleting a channel that is already gone is a no-op —
  // so running it on every wake is fine and needs no "have I done this" flag.
  final android = localNotifications.resolvePlatformSpecificImplementation
      <AndroidFlutterLocalNotificationsPlugin>();
  if ( android != null ) {
    await deleteLegacyWakeChannel( android.deleteNotificationChannel );
  }

  return FcmWakeChain(
    readCredentials: () => readWakeCredentials(
      store     : store,
      contextId : context.activeConfig.id,
    ),
    exchangeForAccessToken: ( refreshToken ) => exchangeRefreshAndPersist(
      dio          : dio,
      store        : store,
      contextId    : context.activeConfig.id,
      refreshToken : refreshToken,
      // Same sink as the chain's own, so a lost rotation shows up in the one
      // adb stream anyone debugging a wake is already watching.
      logSink      : debugPrint,
    ),
    fetchNextNotification: ( _, accessToken ) =>
        fetchNextForAccessToken( dio: dio, accessToken: accessToken ),
    showNotification: ( title, body, payload ) =>
        showWakeNotification( localNotifications, title, body, payload ),
    shouldSpeak: ( priority ) async {
      // Persisted speak-toggles are the background path's ONLY gate
      // (foreground pause is bloc state and does not persist). Mirrors
      // the legacy priority policy (notifications.js:5421 alignment).
      if ( audio.masterMute ) return false;
      switch ( priority ) {
        case 'high':   return audio.speakOnHigh;
        case 'urgent': return audio.speakOnUrgent;
        default:       return false;   // low / medium never spoken
      }
    },
    ttsFraction: () async => audio.ttsFraction,
    speak: ( text ) async {
      // Fresh instance; strict fetch-one-speak-one (flutter_tts#260).
      // awaitSpeakCompletion keeps the handler alive through the
      // utterance — the Phase-0 probe measures whether playback ALSO
      // survives handler completion (informs the 30s-budget posture).
      final tts = FlutterTts();
      await tts.awaitSpeakCompletion( true );
      await tts.speak( text );
    },
    wakeNotificationsEnabled: () async => audio.wakeNotifications,
    markPlayed: ( id, accessToken ) async {
      await dio.post<Map<String, dynamic>>(
        '/api/notifications/$id/played',
        options: Options( headers: { 'Authorization': 'Bearer $accessToken' } ),
      );
    },
    log: debugPrint,
  );
}
