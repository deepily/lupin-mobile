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
import '../auth/secure_credential_store.dart';
import '../auth/server_context_service.dart';
import '../notification_audio/notification_preferences.dart';
import '../websocket/websocket_service.dart';
import 'fcm_wake_chain.dart';
import 'fcm_wakeup_service.dart';

/// Grep-able flag pin (AC-S5.4): `--dart-define=ENABLE_FCM`.
const bool kEnableFcm = bool.fromEnvironment( 'ENABLE_FCM', defaultValue: false );

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
  final dio     = Dio( BaseOptions( baseUrl: context.baseUrl ) );

  final localNotifications = FlutterLocalNotificationsPlugin();
  await localNotifications.initialize( const InitializationSettings(
    android: AndroidInitializationSettings( '@mipmap/ic_launcher' ),
  ) );

  return FcmWakeChain(
    readCredentials: () async {
      final refresh = await store.readRefreshToken( context.activeConfig.id );
      final email   = await store.readLastEmail( context.activeConfig.id );
      if ( refresh == null || email == null ) return null;
      return FcmWakeCredentials( refreshToken: refresh, userEmail: email );
    },
    exchangeForAccessToken: ( refreshToken ) async {
      // POST /auth/refresh — same exchange the foreground repository uses
      // (`auth_repository.dart:67`); the access token is memory-only and
      // never exists in this isolate (Arnold spot-check amendment).
      final res = await dio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: { 'refresh_token': refreshToken },
      );
      return res.data![ 'access_token' ] as String;
    },
    fetchNextNotification: ( email, accessToken ) async {
      // GET /api/notifications/{user}/next (parent notifications.py:1628)
      // — the §3.2.4 content fetch; the FCM payload stays content-free.
      final res = await dio.get<Map<String, dynamic>>(
        '/api/notifications/${Uri.encodeComponent( email )}/next',
        options: Options( headers: { 'Authorization': 'Bearer $accessToken' } ),
      );
      final notif = res.data?[ 'notification' ];
      return notif is Map<String, dynamic> ? notif : null;
    },
    showNotification: ( title, body ) async {
      await localNotifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'lupin_fcm_wake',
            'Lupin background notifications',
            channelDescription:
                'Notifications fetched on FCM silent-relay wake-up',
            importance : Importance.high,
            priority   : Priority.high,
          ),
        ),
      );
    },
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
    speak: ( text ) async {
      // Fresh instance; strict fetch-one-speak-one (flutter_tts#260).
      // awaitSpeakCompletion keeps the handler alive through the
      // utterance — the Phase-0 probe measures whether playback ALSO
      // survives handler completion (informs the 30s-budget posture).
      final tts = FlutterTts();
      await tts.awaitSpeakCompletion( true );
      await tts.speak( text );
    },
    markPlayed: ( id, accessToken ) async {
      await dio.post<Map<String, dynamic>>(
        '/api/notifications/$id/played',
        options: Options( headers: { 'Authorization': 'Bearer $accessToken' } ),
      );
    },
    log: debugPrint,
  );
}
