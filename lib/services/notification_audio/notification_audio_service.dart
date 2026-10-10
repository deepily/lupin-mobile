import 'dart:async';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../core/logging/logger.dart';
import '../push/notification_tap_payload.dart';
import 'notification_preferences.dart';

/// Android notification channel ids.
///
/// Each must match the `RawResourceAndroidNotificationSound` filename, without its extension, in
/// `android/app/src/main/res/raw/`. The three MP3 assets are copied from the Lupin web client for audio parity.
class _Channels {
  /// Channel id for medium priority.
  static const medium = 'lupin_medium';
  /// Channel id for high priority.
  static const high   = 'lupin_high';
  /// Channel id for urgent priority.
  static const urgent = 'lupin_urgent';
}

/// Plays a ding for each incoming notification, one sound per priority tier.
///
/// High and urgent notifications are also spoken, by `TtsOrchestrator`.
/// Mirrors the Lupin web client (`src/fastapi_app/static/js/notifications.js`). `NotificationBloc._onExternalUpdate`
/// calls it when a WS `notification_queue_update` event carries a parsed `NotificationItem`.
class NotificationAudioService {
  final FlutterLocalNotificationsPlugin _fln;
  final FlutterTts                      _tts;
  final NotificationPreferences         _prefs;
  bool _initialized = false;
  bool _handlersSet = false;
  Completer<void>? _utteranceDone;

  /// How long the engine may take to accept a text; see [flutterTtsSpeak].
  final Duration speakAcceptBudget;
  final Duration? _completionBound;

  /// The notification-tap callback this service must preserve when it initializes the plugin.
  ///
  /// It is not optional. `FlutterLocalNotificationsPlugin()` is a singleton and `initialize()` installs the tap handler
  /// by plain assignment, so calling it without a callback sets the handler to null. This service initializes lazily,
  /// on the first ding, so taps would work from launch until the first notification arrives and then stop.
  /// That failure is intermittent, ordering-dependent and invisible to any test that only exercises a cold start.
  final DidReceiveNotificationResponseCallback? _onNotificationTap;

  /// Wiring probe, like `FocusChatBloc.hasQuickAskProbe`.
  ///
  /// It lets a DI-level test assert that production injected the callback.
  ///
  /// Without it a test can only check that this class forwards whatever it was given, and a service constructed
  /// with nothing forwards nothing without complaint. That uninjected-seam failure has happened before.
  @visibleForTesting
  bool get hasTapCallback => _onNotificationTap != null;

  /// Creates the service; [plugin] and [tts] default to the platform singletons.
  NotificationAudioService( {
    required NotificationPreferences prefs,
    FlutterLocalNotificationsPlugin? plugin,
    FlutterTts?                      tts,
    DidReceiveNotificationResponseCallback? onNotificationTap,
    this.speakAcceptBudget = const Duration( seconds: 10 ),
    Duration? completionBound,
  } ) : _completionBound = completionBound,
       _prefs = prefs,
       _onNotificationTap = onNotificationTap,
       _fln   = plugin ?? FlutterLocalNotificationsPlugin(),
       _tts   = tts    ?? FlutterTts();

  /// Initializes the notification plugin and creates the Android channels, once.
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

  /// Plays the ding for an incoming notification, subject to the preferences.
  ///
  /// [priority] is one of `low`, `medium`, `high` or `urgent`. A `low` priority and a master mute do nothing.
  /// [suppressDing] is the backend `suppress_ding` flag. It silences the ding only, not speech, as in the web client.
  /// Speech is not dispatched from here: `TtsOrchestrator` owns it, with `flutter_tts` as the fallback through
  /// [flutterTtsSpeak].
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

    // Speech is not dispatched from here. `TtsOrchestrator` owns all speech, ElevenLabs first and `flutter_tts`
    // as the fallback through [flutterTtsSpeak]. `NotificationBloc._onExternalUpdate` wires it beside this ding call.
  }

  /// Speaks [text] with `flutter_tts` and returns when the engine has finished it, for `TtsOrchestrator` when
  /// ElevenLabs is unavailable.
  ///
  /// Unavailable means quota exceeded, a network error or a disconnected WebSocket. It lives here because this
  /// service owns the `FlutterTts` singleton. A missing TTS engine is non-fatal.
  ///
  /// Two bounds, so a wedged engine can never hold the caller for good:
  ///   - acceptance: [speakAcceptBudget] for the engine to take the text
  ///   - completion: [completionBoundFor] the text, for the engine's completion, cancel or error callback
  ///
  /// The orchestrator keeps its in-flight utterance until this returns, which is what lets skip, stop-all,
  /// pause, the microphone hold and an urgent arrival reach the speech. Returning on acceptance let a burst
  /// pile up inside the engine where none of them could.
  Future<void> flutterTtsSpeak( String text ) async {
    final done = Completer<void>();
    _utteranceDone = done;
    try {
      _ensureHandlers();
      await _tts.stop();
      await _tts.speak( text ).timeout( speakAcceptBudget );
    } on TimeoutException {
      Logger.warning( "on-device speak was not accepted within ${speakAcceptBudget.inMilliseconds} ms", tag: "TtsFallback" );
      _release( done );
      await stopFallbackSpeech();
      return;
    } catch ( e ) {
      // TTS engine may be unavailable on some devices; non-fatal.
      Logger.warning( "on-device speak failed", tag: "TtsFallback", error: e );
      _release( done );
      return;
    }
    try {
      await done.future.timeout( completionBoundFor( text ) );
    } on TimeoutException {
      Logger.warning( "on-device speech did not report finishing within ${completionBoundFor( text ).inSeconds} s", tag: "TtsFallback" );
      _release( done );
      await stopFallbackSpeech();
    }
  }

  /// How long the engine may take to finish [text] before it is presumed wedged.
  ///
  /// It is 30 s plus the text at a deliberately slow 8 characters a second, unless a bound was injected.
  Duration completionBoundFor( String text ) =>
      _completionBound ?? Duration( seconds: 30 + text.length ~/ 8 );

  void _ensureHandlers() {
    if ( _handlersSet ) return;
    _handlersSet = true;
    try {
      _tts.setCompletionHandler( _releaseCurrent );
      _tts.setCancelHandler( _releaseCurrent );
      _tts.setErrorHandler( ( dynamic _ ) => _releaseCurrent() );
    } catch ( e ) {
      // Without callbacks the completion bound still releases the caller.
      Logger.warning( "could not register the speech completion handlers", tag: "TtsFallback", error: e );
    }
  }

  void _releaseCurrent() => _release( _utteranceDone );

  void _release( Completer<void>? c ) {
    if ( c != null && !c.isCompleted ) c.complete();
  }

  /// Stops any in-flight `flutter_tts` utterance.
  ///
  /// `TtsOrchestrator` calls it on urgent-preempt and user-cancel.
  Future<void> stopFallbackSpeech() async {
    // Release a waiting speak first: some engines fire no cancel callback on stop.
    _releaseCurrent();
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
    // The Android id is a stable 32-bit hash, because the backend `NotificationItem.id` is a string.
    // Prefer the item's own id: hashing the title collapses every notification that shares one into a single
    // Android id, so each new arrival replaced the last.
    final id = ( notificationId ?? title ?? body ).hashCode & 0x7fffffff;
    await _fln.show(
      id, title ?? 'Lupin', body, details,
      // The foreground ding is a second post site, and a tap on it must route exactly like a tap on a
      // background wake notification. The payload is null when the caller had no id, which reads as "not routable".
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
