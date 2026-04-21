import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_tts/flutter_tts.dart';

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

  /// 300ms gap between ding and TTS — matches web client behavior so the
  /// ding sound finishes cleanly before speech starts.
  static const _dingToSpeechGap = Duration( milliseconds: 300 );

  NotificationAudioService( {
    required NotificationPreferences prefs,
    FlutterLocalNotificationsPlugin? plugin,
    FlutterTts?                      tts,
  } ) : _prefs = prefs,
       _fln   = plugin ?? FlutterLocalNotificationsPlugin(),
       _tts   = tts    ?? FlutterTts();

  Future<void> initialize() async {
    if ( _initialized ) return;
    const androidInit = AndroidInitializationSettings( '@mipmap/ic_launcher' );
    await _fln.initialize( const InitializationSettings( android: androidInit ) );
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
  } ) async {
    if ( _prefs.masterMute ) return;
    if ( priority == 'low' ) return;

    await initialize();

    final shouldDing  = !suppressDing && _dingEnabledFor( priority );
    final shouldSpeak = _speechEnabledFor( priority );

    if ( shouldDing ) await _showDing( priority: priority, title: title, body: message );

    if ( shouldSpeak ) {
      // 300ms delay lets the ding finish before speech starts. Fire-and-forget.
      Future.delayed( _dingToSpeechGap, () => _speak( title: title, body: message ) );
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

  bool _speechEnabledFor( String priority ) {
    switch ( priority ) {
      case 'high'   : return _prefs.speakOnHigh;
      case 'urgent' : return _prefs.speakOnUrgent;
      default       : return false;
    }
  }

  Future<void> _showDing( {
    required String  priority,
    required String  body,
    String?          title,
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
    // so we hash to a stable 32-bit int.
    final id = ( title ?? body ).hashCode & 0x7fffffff;
    await _fln.show( id, title ?? 'Lupin', body, details );
  }

  Future<void> _speak( { required String body, String? title } ) async {
    final text = ( title != null && title.isNotEmpty )
        ? '$title. $body'
        : body;
    try {
      await _tts.stop();  // cancel any in-flight speech; latest wins
      await _tts.speak( text );
    } catch ( _ ) {
      // TTS engine may be unavailable on some devices; failures are non-fatal.
    }
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
