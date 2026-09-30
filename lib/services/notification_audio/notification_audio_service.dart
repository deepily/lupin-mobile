import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../push/notification_tap_payload.dart';
import 'notification_preferences.dart';

/// Channel IDs must match the `RawResourceAndroidNotificationSound` filenames
/// (sans extension) in `android/app/src/main/res/raw/`. These are the three
/// MP3 assets copied from the Lupin web client to maintain audio parity.
class _Channels {
  static const medium = 'lupin_medium';
  static const high   = 'lupin_high';
  static const urgent = 'lupin_urgent';
}

/// Plays audio on incoming notifications: single ding per priority tier, plus
/// spoken title+message for high/urgent. Mirrors Lupin web client semantics
/// (see `src/fastapi_app/static/js/notifications.js`).
///
/// Triggered from `NotificationBloc._onExternalUpdate` when a WS
/// `notification_queue_update` event carries a parsed `NotificationItem`.
class NotificationAudioService {
  final FlutterLocalNotificationsPlugin _fln;
  final FlutterTts                      _tts;
  final NotificationPreferences         _prefs;
  bool _initialized = false;

  /// The notification-TAP callback this service must PRESERVE when it
  /// initializes the plugin (row d9bc6f6c).
  ///
  /// 🔴 NOT AN OPTIONAL EXTRA — WITHOUT IT THIS SERVICE SILENTLY UNBINDS TAPS.
  /// `FlutterLocalNotificationsPlugin()` is a singleton
  /// (`factory FlutterLocalNotificationsPlugin() => _instance`) and
  /// `initialize()` installs the tap handler by plain ASSIGNMENT, so calling it
  /// without one sets the handler to null. This service initializes LAZILY, on
  /// the first ding — so the old bare call would have let taps work from launch
  /// until the first notification arrived and then stop, which is about the
  /// worst shape a bug can have: intermittent, ordering-dependent, and invisible
  /// to any test that only exercises a cold start.
  final DidReceiveNotificationResponseCallback? _onNotificationTap;

  /// Wiring probe, same purpose as `FocusChatBloc.hasQuickAskProbe`: let a
  /// DI-level test assert that PRODUCTION actually injected the callback.
  ///
  /// Without it, a test can only check that this class forwards whatever it was
  /// given — and a service constructed with nothing forwards nothing perfectly
  /// happily, which is the uninjected-seam failure this repo has already been
  /// bitten by once (bug 9adff476).
  @visibleForTesting
  bool get hasTapCallback => _onNotificationTap != null;

  NotificationAudioService( {
    required NotificationPreferences prefs,
    FlutterLocalNotificationsPlugin? plugin,
    FlutterTts?                      tts,
    DidReceiveNotificationResponseCallback? onNotificationTap,
  } ) : _prefs = prefs,
       _onNotificationTap = onNotificationTap,
       _fln   = plugin ?? FlutterLocalNotificationsPlugin(),
       _tts   = tts    ?? FlutterTts();

  Future<void> initialize() async {
    if ( _initialized ) return;
    const androidInit = AndroidInitializationSettings( '@mipmap/ic_launcher' );
    await _fln.initialize(
      const InitializationSettings( android: androidInit ),
      onDidReceiveNotificationResponse: _onNotificationTap,
    );
    await _createAndroidChannels();
    _initialized = true;
  }

  Future<void> _createAndroidChannels() async {
    final android = _fln.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if ( android == null ) return;

    await android.createNotificationChannel( const AndroidNotificationChannel(
      _Channels.medium,
      'Lupin — Medium priority',
      description: 'Medium-priority notifications: gentle ding, no speech.',
      importance: Importance.defaultImportance,
      playSound : true,
      sound     : RawResourceAndroidNotificationSound( 'lupin_medium' ),
    ) );

    await android.createNotificationChannel( const AndroidNotificationChannel(
      _Channels.high,
      'Lupin — High priority',
      description: 'High-priority notifications: prominent ding + spoken summary.',
      importance: Importance.high,
      playSound : true,
      sound     : RawResourceAndroidNotificationSound( 'lupin_high' ),
    ) );

    await android.createNotificationChannel( const AndroidNotificationChannel(
      _Channels.urgent,
      'Lupin — Urgent',
      description: 'Urgent notifications: distinct alert tone + spoken summary.',
      importance: Importance.max,
      playSound : true,
      sound     : RawResourceAndroidNotificationSound( 'lupin_urgent' ),
    ) );
  }

  /// Called by `NotificationBloc` whenever a WS notification_queue_update
  /// event carries a fresh `NotificationItem`. [priority] is one of the
  /// four canonical tiers `low | medium | high | urgent`. [suppressDing]
  /// is the backend `suppress_ding` flag (silences ding only, not speech —
  /// matches web client semantics).
  Future<void> handleIncoming( {
    required String  priority,
    required String  message,
    String?          title,
    required bool    suppressDing,
    String?          notificationId,
    String?          senderId,
  } ) async {
    if ( _prefs.masterMute ) return;
    if ( priority == 'low' ) return;

    await initialize();

    final shouldDing = !suppressDing && _dingEnabledFor( priority );

    if ( shouldDing ) {
      await _showDing(
        priority       : priority,
        title          : title,
        body           : message,
        notificationId : notificationId,
        senderId       : senderId,
      );
    }

    // Speech is NOT dispatched from here anymore. `TtsOrchestrator` owns
    // all speech — ElevenLabs primary, `flutter_tts` fallback via
    // [flutterTtsSpeak] below. The orchestrator is wired in
    // `NotificationBloc._onExternalUpdate` alongside this ding call.
  }

  /// Fallback helper — called ONLY by `TtsOrchestrator` when ElevenLabs
  /// is unavailable (quota exceeded, network error, WS disconnected).
  /// Kept inside this service because it owns the `FlutterTts` singleton.
  Future<void> flutterTtsSpeak( String text ) async {
    try {
      await _tts.stop();
      await _tts.speak( text );
    } catch ( _ ) {
      // TTS engine may be unavailable on some devices; non-fatal.
    }
  }

  /// Stop any in-flight `flutter_tts` utterance. Called by
  /// `TtsOrchestrator` on urgent-preempt and user-cancel paths.
  Future<void> stopFallbackSpeech() async {
    try {
      await _tts.stop();
    } catch ( _ ) {
      // Already-stopped is fine.
    }
  }

  bool _dingEnabledFor( String priority ) {
    switch ( priority ) {
      case 'medium' : return _prefs.dingOnMedium;
      case 'high'   : return _prefs.dingOnHigh;
      case 'urgent' : return _prefs.dingOnUrgent;
      default       : return false;
    }
  }

  Future<void> _showDing( {
    required String  priority,
    required String  body,
    String?          title,
    String?          notificationId,
    String?          senderId,
  } ) async {
    final channelId   = _channelFor( priority );
    final channelName = _channelDisplayFor( priority );
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        channelId,
        channelName,
        importance: _importanceFor( priority ),
        priority  : _fdnPriorityFor( priority ),
        playSound : true,
        sound     : RawResourceAndroidNotificationSound( channelId ),
      ),
    );
    // Unique id per notification — backend NotificationItem.id is a string,
    // so we hash to a stable 32-bit int. Prefer the item's OWN id when we have
    // it: hashing the title collapses every notification that shares one into a
    // single Android id, so each new arrival replaced the last.
    final id = ( notificationId ?? title ?? body ).hashCode & 0x7fffffff;
    await _fln.show(
      id, title ?? 'Lupin', body, details,
      // Row d9bc6f6c: the foreground ding is a SECOND post site, and a tap on it
      // has to route exactly like a tap on a background wake notification. Null
      // when the caller had no id to give, which reads as "not routable".
      payload: notificationId == null ? null : NotificationTapPayload(
        notificationId : notificationId,
        senderId       : senderId,
      ).encode(),
    );
  }

  String _channelFor( String priority ) {
    switch ( priority ) {
      case 'urgent' : return _Channels.urgent;
      case 'high'   : return _Channels.high;
      default       : return _Channels.medium;
    }
  }

  String _channelDisplayFor( String priority ) {
    switch ( priority ) {
      case 'urgent' : return 'Lupin — Urgent';
      case 'high'   : return 'Lupin — High priority';
      default       : return 'Lupin — Medium priority';
    }
  }

  Importance _importanceFor( String priority ) {
    switch ( priority ) {
      case 'urgent' : return Importance.max;
      case 'high'   : return Importance.high;
      default       : return Importance.defaultImportance;
    }
  }

  Priority _fdnPriorityFor( String priority ) {
    switch ( priority ) {
      case 'urgent' : return Priority.max;
      case 'high'   : return Priority.high;
      default       : return Priority.defaultPriority;
    }
  }
}
