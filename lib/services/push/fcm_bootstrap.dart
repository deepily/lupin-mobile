/// Firebase bootstrap, gated behind the compile-time flag `ENABLE_FCM`.
///
/// Build with `flutter build apk --dart-define=ENABLE_FCM=true`. The default is off, so builds without it carry no
/// hard dependency on `google-services.json`. `streaming_tts_player.dart` sets the precedent.
///
/// Provisioning the Firebase project is a human, laptop-side step (`src/rnd/2026.06.11-focus-mode-voice-chat/91-osq7-firebase-console-runbook.md`).
/// The same pass completes the wiring this file expects but does not require:
///   1. Drop `google-services.json` into `android/app/`.
///   2. Apply the google-services gradle plugin (`com.google.gms.google-services`) in `android/app/build.gradle.kts`,
///      with its classpath in `android/settings.gradle.kts`.
/// Neither is committed. Applying the plugin without the json breaks every build, so the gradle wiring rides that pass
/// (see `src/rnd/2026.06.11-focus-mode-voice-chat/92-s5-phase0-fcm-probe-runbook.md`).
library;

import 'dart:convert';
import 'dart:ui' show DartPluginRegistrant;

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/di/service_locator.dart';
import '../auth/auth_repository.dart';
import '../auth/secure_credential_store.dart';
import '../auth/server_context_service.dart';
import '../notification_audio/notification_delivery_policy.dart';
import '../notification_audio/notification_preferences.dart';
import '../websocket/websocket_service.dart';
import 'fcm_wake_chain.dart';
import 'fcm_wakeup_service.dart';
import 'notification_sender_label.dart';
import 'notification_tap_payload.dart';

/// Compile-time flag that turns FCM on: `--dart-define=ENABLE_FCM=true`; the default is off.
const bool kEnableFcm = bool.fromEnvironment( 'ENABLE_FCM', defaultValue: false );

/// Connect timeout for the background wake isolate's Dio.
///
/// The Android background-message handler gets roughly 30 s, shared by three calls (refresh, the unplayed list, mark-played)
/// and then an utterance. Each call is capped well inside that. The three timeouts are tighter than the foreground's
/// (`http_service.dart`), because out here a slow answer is worth less than a prompt fallback notification.
/// The fallback is what keeps FCM treating our wakes as high priority.
const Duration kFcmBackgroundConnectTimeout = Duration( seconds: 6 );
/// Send timeout for the background wake isolate's Dio; see [kFcmBackgroundConnectTimeout].
const Duration kFcmBackgroundSendTimeout    = Duration( seconds: 6 );
/// Receive timeout for the background wake isolate's Dio; see [kFcmBackgroundConnectTimeout].
const Duration kFcmBackgroundReceiveTimeout = Duration( seconds: 8 );

/// Real [FcmTokenSource] over FirebaseMessaging; main isolate only.
class FirebaseTokenSource implements FcmTokenSource {
  final FirebaseMessaging _messaging;
  /// Wraps [_messaging].
  FirebaseTokenSource( this._messaging );

  @override
  Future<String?> getToken() => _messaging.getToken();

  @override
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;
}

FcmWakeupService? _service;

/// Main-isolate init, called from `main()` after the service locator is up.
///
/// It is a no-op when the flag is off, which is the default.
Future<FcmWakeupService?> initFcmIfEnabled() async {
  if ( !kEnableFcm ) return null;

  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage( fcmBackgroundHandler );

  final service = FcmWakeupService(
    tokenSource : FirebaseTokenSource( FirebaseMessaging.instance ),
    dio         : ServiceLocator.get<Dio>(),   // shared auth-wired instance
  );
  _service = service;

  // Foreground data message: a no-op beyond a debug log. The WebSocket is already live,
  // and speech ownership stays with FocusChatBloc.
  FirebaseMessaging.onMessage.listen( ( m ) {
    debugPrint( '[FcmWakeup] foreground data message ignored '
        '(type=${m.data[ 'type' ]}, WS is live)' );
  } );

  // Token-lifecycle writer 3: every authenticated WebSocket (re)connect re-registers the token, as an idempotent upsert.
  // `auth_success` frames mark both the initial connect and every reconnect.
  final ws = ServiceLocator.get<WebSocketService>();
  ws.stream.listen( ( frame ) {
    if ( frame is Map && frame[ 'type' ] == 'auth_success' ) {
      _service?.onWsReconnected();
    }
  } );

  return service;
}

/// Auth-state hooks, called by the app layer on the auth-state stream's transitions.
///
/// It is the same signal AuthGate renders on. They are safe no-ops when FCM is disabled.
Future<void> fcmOnAuthenticated( String userEmail ) async =>
    _service?.onAuthenticated( userEmail );

/// Tells the wake service the user logged out; a no-op when FCM is disabled.
Future<void> fcmOnLoggedOut() async => _service?.onLoggedOut();

/// Background data-message handler: the handler does the work.
///
/// It runs in a fresh isolate with an empty service locator, and the main isolate may be dead.
/// It bootstraps its own minimal dependencies and runs the locator-free [FcmWakeChain]:
/// token exchange, fetch, show, one speak, mark played.
@pragma( 'vm:entry-point' )
Future<void> fcmBackgroundHandler( RemoteMessage message ) async {
  // Fresh-engine plugin access: secure storage, prefs and the asset bundle.
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();

  final chain = await buildBackgroundWakeChain();
  final outcome = await chain.handleWake( message.data );
  // The debug hook's terminal line: one summary per wake.
  debugPrint( '[FcmWake] outcome: $outcome' );
}

/// Refreshes the token in the background isolate and saves the rotated refresh token.
///
/// The server revokes the refresh token it is given and returns a new one, so the new one must be stored.
/// The write is the fragile half: it is retried, and if it still fails the wake continues and the log says so.
///
/// Requires:
///   - refreshToken is the token currently stored for contextId
///
/// Ensures:
///   - returns the new access token
///   - the rotated refresh token is written to the store before returning, or [kFcmRefreshWriteLostMarker] is logged
///     and the wake still completes
///
/// Raises:
///   - AuthException on a failed or malformed exchange; the chain turns it into the fallback notification,
///     and nothing is written in that case
@visibleForTesting
Future<String> exchangeRefreshAndPersist( {
  required Dio                   dio,
  required SecureCredentialStore store,
  required String                contextId,
  required String                refreshToken,
  void Function( String )?       logSink,
} ) async {
  // Notes on the rotation. The server rotates refresh tokens: every exchange revokes the token it was given.
  // Measured on a phone: the first wake refreshed with a 200 and discarded the new token, so the second wake
  // presented a revoked one and got a 401. The foreground interceptor reads the same stored token, so its next refresh
  // would fail too, which is a silent log-out. The foreground already persists rotations (`service_locator.dart`,
  // `onTokensRotated`). This is the background half of the same rule.
  //
  // The write is the fragile half, not the exchange. Between the exchange returning and the store accepting,
  // the only copy of a usable refresh token is a local variable, because the old one is already revoked.
  // A failed write loses the account. The likeliest cause is a Doze wake on a device booted but never unlocked,
  // where the Android keystore is not available yet. So the write is retried.
  // If it still fails, the wake continues and the log says so unmistakably, because the next foreground refresh will fail.
  //
  // Use the same parser as the foreground. The server answers `{message, user?, tokens: {access_token, refresh_token}}`.
  // A second, hand-rolled reader of that envelope read the tokens at the top level, got null, and threw after the exchange
  // had already revoked the old token. Nothing was ever fetched.
  final repo = AuthRepository( dio );

  AuthTokens tokens;
  try {
    tokens = await repo.refresh( refreshToken );
  } on AuthException catch ( e ) {
    // A 401 here usually means this attempt lost a race, not that the user is signed out.
    // This isolate and the foreground's AuthInterceptor share one stored refresh token, and the server revokes on every exchange.
    // When a wake lands while the app is backgrounded but alive, both can present the same token, and the loser's copy is revoked.
    // Treating that as a dead session turned an ordinary collision into a forced re-login.
    //
    // So re-read the store. If the winner already wrote a new token, that token is valid and this attempt simply arrived second.
    // Retry exactly once, and only when the stored value changed: a 401 on the same token just read is a dead session,
    // and retrying it in a loop would be a log-out with extra steps.
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

/// The one log line that says this account is about to need a re-login, and why.
///
/// It is the only warning anyone gets, so it is meant to be found with grep.
const String kFcmRefreshWriteLostMarker = '[FcmWake] ROTATED REFRESH TOKEN LOST';

/// How many times the rotated-token write is attempted before giving up.
const int kFcmRefreshWriteAttempts = 3;

/// Writes the rotated refresh token, retrying a transient storage failure.
///
/// The failure this guards against is overwhelmingly transient: a wake on a booted-but-never-unlocked device
/// finds the keystore unavailable for a moment, not forever.
///
/// Ensures:
///   - the token is stored, or [kFcmRefreshWriteLostMarker] is logged
///   - never throws: the old token is already revoked, so failing the wake as well would cost the notification and save nothing
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

/// Gap between write attempts.
///
/// Long enough for a keystore that is coming up, short enough to stay inside the handler budget three times over.
const Duration kFcmRefreshWriteRetryDelay = Duration( milliseconds: 250 );

/// The system user id (the JWT `sub` claim) carried by a Lupin access token.
///
/// Requires:
///   - jwt is a three-part JWT whose payload has a non-empty string `sub`
///
/// Ensures:
///   - returns that `sub`; nothing is verified, since the server does that
///
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

/// How many unplayed items one wake will consider.
///
/// The chain shows at most [kFcmWakeDrainMax] of them. The rest only have to be enough to find a priority
/// the user still wants behind a run of ones they do not.
///
/// The value is 500, not 50. The server applies the limit by slicing the head of the queue, `notifications[:limit]`.
/// A limit therefore means the oldest N items and nothing after them.
/// Sixty denied items at the head hide every allowed item behind them, as `/next`'s single item did.
/// The run never shrinks, because denied items are never consumed.
/// That is head-of-line blocking one layer down, invisible to any test that used a short list.
/// 500 is larger than any plausible unplayed backlog. A high limit costs one bigger JSON body on a wake.
/// A low one costs silence that looks like the feature working.
const int kFcmWakeUnplayedLimit = 500;

/// The background-enabled priorities, in [NotificationPreferences.priorities] order.
///
/// They are the ones the user has left switched on for the background surface.
/// They feed the wake fetch's server-side `priorities` filter.
@visibleForTesting
List<String> backgroundAllowedPriorities( NotificationPreferences audio ) => [
  for ( final p in NotificationPreferences.priorities )
    if ( audio.priorityEnabled( 'background', p ) ) p,
];

/// Fetches the user's unplayed notifications by user id, as a list, filtered by the server.
///
/// The path takes the account's UUID from the access token, not the email (the endpoint compares it with each item's `user_id`).
/// It is the list, not `/next`: `include_played=false` is a pure read, so skipped items stay unplayed.
/// Design: src/docs/decisions/README.md (R-PUSH-list-not-next)
///
/// Requires:
///   - [priorities] is drawn from [NotificationPreferences.priorities], since an unknown value is a 400
///   - an empty set fetches nothing, because "no priority allowed" must never be sent as "no filter"
///
/// Ensures:
///   - returns the unplayed items as raw wire maps, possibly empty, never null
///   - order is not trusted: `oldestFirst` sorts them, because the endpoint's docstring claims newest-first and its handler sorts nothing
@visibleForTesting
Future<List<Map<String, dynamic>>> fetchUnplayedForAccessToken( {
  required Dio          dio,
  required String       accessToken,
  required List<String> priorities,
} ) async {
  if ( priorities.isEmpty ) return const [];
  // The server filters and sorts, not the phone. `priorities` is the set the background policy allows
  // and `sort=oldest` puts the queue head first. The filter runs before the limit, so a run of switched-off
  // items cannot push an allowed urgent past [kFcmWakeUnplayedLimit]. Mute and quiet hours stay client-side,
  // because the server does not know them, and `oldestFirst` still runs as a check.
  // Sending the email here fetched nothing on every wake, so each one fell back to "New activity".
  // The id comes from the access token just issued, so the background isolate needs nothing else stored.
  final userId = userIdFromAccessToken( accessToken );
  final res    = await dio.get<Map<String, dynamic>>(
    '/api/notifications/${Uri.encodeComponent( userId )}',
    queryParameters: {
      'include_played' : false,
      'limit'          : kFcmWakeUnplayedLimit,
      'priorities'     : priorities.join( ',' ),
      'sort'           : 'oldest',
    },
    options: Options( headers: { 'Authorization': 'Bearer $accessToken' } ),
  );
  final list = res.data?[ 'notifications' ];
  if ( list is! List ) return const [];
  return [ for ( final e in list ) if ( e is Map<String, dynamic> ) e ];
}

/// The notification channel wake notifications are posted on.
///
/// The `_v2` suffix is required. Android fixes a channel's importance when the channel is created and ignores later changes.
/// Lowering `importance` in code would reach nobody who already had the app, and a heads-up banner at 3am would go on.
/// A new id is the only way the new importance applies to an existing install.
/// Design: src/docs/decisions/README.md (R-PUSH-wake-channel)
///
/// A new id leaves an orphan. The old channel stays in the system notification settings
/// as a second "Lupin background notifications" row that the user can toggle to no effect.
/// Hence [kFcmWakeChannelIdLegacy] and the delete below.
const String kFcmWakeChannelId       = 'lupin_fcm_wake_v2';

/// The pre-v2 channel, deleted so the id bump leaves no dead row in the user's settings.
///
/// Keep this list growing if the id is ever bumped again. Deleting a channel that no longer exists is harmless,
/// so the call is idempotent and safe on every wake.
const String kFcmWakeChannelIdLegacy = 'lupin_fcm_wake';

/// The details every wake notification is posted with.
///
/// It is extracted so a test can assert the channel id and the importance.
/// Inline in the `showNotification` closure they were unreachable, because that closure only runs with a live platform channel behind it.
@visibleForTesting
NotificationDetails wakeNotificationDetails() => const NotificationDetails(
  android: AndroidNotificationDetails(
    kFcmWakeChannelId,
    'Lupin background notifications',
    channelDescription: 'Notifications fetched on FCM silent-relay wake-up',
    // Default importance, not high: a wake that arrives overnight should land in the shade, not take over the screen with a heads-up banner.
    // This does not weaken the contract that every wake ends visible. FCM watches whether a high-priority message
    // produces a notification at all, not what importance that notification carries, so wakes stay high-priority end to end.
    // Design: src/docs/decisions/README.md (R-PUSH-wake-channel)
    importance : Importance.defaultImportance,
    priority   : Priority.defaultPriority,
  ),
);

/// Removes the pre-v2 channel, so the id bump leaves no duplicate row in the settings.
///
/// One of two identically-named rows would do nothing.
///
/// Requires:
///   - deleteChannel deletes an Android notification channel by id
///
/// Ensures:
///   - [kFcmWakeChannelIdLegacy] is deleted, and the current id never is
///   - never throws: an orphan row is cosmetic, and losing the wake over it would not be
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

/// Android notification id for one wake notification, derived per item and not per second.
///
/// Five posts in one second would share a per-second id, and Android replaces a live notification with the same id.
/// The id is a 31-bit FNV-1a hash of the item id in [payload], so a re-shown item replaces its own earlier notification.
/// A fallback has no item id, so it keeps the per-second id.
///
/// Ensures:
///   - the same item id gives the same result, and different item ids give different results, barring a 1-in-2^31 collision
///   - the result is in [0, 2^31)
@visibleForTesting
int wakeNotificationId( String? payload, { DateTime? now } ) {
  final itemId = NotificationTapPayload.decode( payload )?.notificationId ?? '';
  if ( itemId.isEmpty ) {
    return ( ( now ?? DateTime.now() ).millisecondsSinceEpoch ~/ 1000 ) & 0x7fffffff;
  }
  var h = 0x811c9dc5;
  for ( final unit in itemId.codeUnits ) {
    h = ( ( h ^ unit ) * 0x01000193 ) & 0xffffffff;
  }
  return h & 0x7fffffff;
}

/// Posts one wake notification, carrying its tap payload.
///
/// It is extracted from the chain's lambda so a test can reach it. Deleting `payload:` here once left the whole push suite green,
/// because `fcm_wake_chain_test` supplies its own lambda for the seam. A seam nothing covers will be silently deleted.
///
/// Requires:
///   - plugin is an initialized FlutterLocalNotificationsPlugin
///
/// Ensures:
///   - the notification is posted on [kFcmWakeChannelId] (the v2 channel) at default importance and priority, via [wakeNotificationDetails]
///   - `payload` reaches the plugin verbatim, including null
@visibleForTesting
Future<void> showWakeNotification(
  FlutterLocalNotificationsPlugin plugin,
  String  title,
  String  body,
  String? payload,
) async {
  await plugin.show(
    wakeNotificationId( payload ),
    title,
    body,
    wakeNotificationDetails(),
    // Android persists this in the notification's intent, the only carrier that survives this isolate being killed.
    // The main isolate reads it back from the launch intent when the tap is what started the app.
    payload: payload,
  );
}

/// Reads what the background isolate can know about who is logged in.
///
/// The refresh token is the only credential this path needs. The email is no longer used by the fetch, which is addressed by the JWT `sub` claim.
/// Demanding it would only produce a false "Open Lupin and sign in" for a signed-in user.
/// It is pulled out of the chain builder so it can be tested, because the coupling was undocumented and its failure would be invisible.
///
/// Requires:
///   - contextId is the active server context
///
/// Ensures:
///   - null iff there is no stored refresh token, meaning never logged in here
///   - otherwise credentials, with an empty email when none is stored
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

/// Builds the chain from real background-isolate dependencies.
///
/// It is split out of the handler so the Phase-0 probe can reuse it verbatim.
/// Nothing below touches the ServiceLocator: everything is constructed fresh because of the isolate boundary.
Future<FcmWakeChain> buildBackgroundWakeChain() async {
  final prefs   = await SharedPreferences.getInstance();
  final context = await ServerContextService.load( prefs );
  final store   = SecureCredentialStore();
  final audio   = NotificationPreferences( prefs );
  final policy  = NotificationDeliveryPolicy( audio );
  final dio     = Dio( BaseOptions(
    baseUrl        : context.baseUrl,
    // A wake that hangs posts nothing, the one outcome this whole path exists to prevent.
    // This Dio carries all three calls of the wake (refresh, unplayed list, mark-played) and once set no timeouts, which for Dio means none.
    // A half-open socket, such as captive-portal Wi-Fi or a dying LTE cell, parks `handleWake` forever.
    // The fallback notification lives in the chain's catch arm, so a call that never returns and never throws never reaches it,
    // and Android eventually kills the isolate in silence.
    // FCM downgrades high-priority messages that produce no notification (see `kFcmWakeFallbackBody`), so one bad network event degrades every later wake.
    // The budgets leave room under the ~30 s handler window for all three calls plus the utterance;
    // `http_service.dart` is the foreground precedent.
    connectTimeout : kFcmBackgroundConnectTimeout,
    sendTimeout    : kFcmBackgroundSendTimeout,
    receiveTimeout : kFcmBackgroundReceiveTimeout,
  ) );

  final localNotifications = FlutterLocalNotificationsPlugin();
  await localNotifications.initialize( const InitializationSettings(
    android: AndroidInitializationSettings( '@mipmap/ic_launcher' ),
  ) );

  // The other half of the v2 channel bump: drop the pre-v2 channel, so the user is not left with two identically-named rows, one of them dead.
  // It is idempotent, since deleting a channel that is already gone is a no-op, so running it on every wake needs no "have I done this" flag.
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
      // Same sink as the chain's own, so a lost rotation shows up in the one adb stream anyone debugging a wake already watches.
      logSink      : debugPrint,
    ),
    fetchUnplayed: ( _, accessToken ) => fetchUnplayedForAccessToken(
        dio         : dio,
        accessToken : accessToken,
        priorities  : backgroundAllowedPriorities( audio ) ),
    showNotification: ( title, body, payload ) =>
        showWakeNotification( localNotifications, title, body, payload ),
    shouldSpeak: ( priority ) async {
      // Persisted speak toggles are the background path's only gate; the foreground pause is bloc state and does not persist.
      // This mirrors the legacy priority policy (`notifications.js`).
      if ( audio.masterMute ) return false;
      switch ( priority ) {
        case 'high':   return audio.speakOnHigh;
        case 'urgent': return audio.speakOnUrgent;
        default:       return false;   // low / medium never spoken
      }
    },
    ttsFraction: () async => audio.ttsFraction,
    speak: ( text ) async {
      // Fresh instance, strict one utterance (`flutter_tts` issue 260).
      // `awaitSpeakCompletion` keeps the handler alive through the utterance.
      // The Phase-0 probe measures whether playback also survives handler completion, which informs the 30 s budget posture.
      final tts = FlutterTts();
      await tts.awaitSpeakCompletion( true );
      await tts.speak( text );
    },
    // The two gates, both answered from SharedPreferences, the only store this isolate can read.
    backgroundAllowsAnyPriority: () async =>
        policy.anyAllowedOn( NotificationSurface.background ),
    // The item goes in too, so a muted sender and quiet hours are answered here from the same SharedPreferences as the priority is.
    itemAllowed: ( priority, item ) async => policy.allows(
        surface   : NotificationSurface.background,
        priority  : priority,
        senderKey : notificationSenderKey( item ) ),
    markPlayed: ( id, accessToken ) async {
      await dio.post<Map<String, dynamic>>(
        '/api/notifications/$id/played',
        options: Options( headers: { 'Authorization': 'Bearer $accessToken' } ),
      );
    },
    log: debugPrint,
  );
}
