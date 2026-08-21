import 'package:shared_preferences/shared_preferences.dart';

/// User-tunable audio preferences for incoming notifications.
///
/// Backed by [SharedPreferences]. All toggles default to values that match
/// the Lupin web client's behavior so first-run users hear the same thing as
/// on desktop. Master mute overrides every other toggle.
///
/// Priority → behavior table (defaults):
///   low    : silent
///   medium : ding
///   high   : ding + speak title/message
///   urgent : ding (distinct alert tone) + speak title/message
class NotificationPreferences {
  static const _keyDingOnMedium = 'notif_audio.ding_on_medium';
  static const _keyDingOnHigh   = 'notif_audio.ding_on_high';
  static const _keyDingOnUrgent = 'notif_audio.ding_on_urgent';
  static const _keySpeakOnHigh  = 'notif_audio.speak_on_high';
  static const _keySpeakOnUrgent = 'notif_audio.speak_on_urgent';
  static const _keyMasterMute   = 'notif_audio.master_mute';
  /// TTS preview fraction (Rick 2026-08-21 -- mirrors the web client's
  /// `#cc-tts-fraction-slider`): how much of each message is spoken
  /// automatically, in 10% steps. 1.0 = whole message.
  static const keyTtsFraction   = 'notif_audio.tts_fraction';
  static const double defaultTtsFraction = 0.2;

  final SharedPreferences _prefs;
  const NotificationPreferences( this._prefs );

  bool get dingOnMedium  => _prefs.getBool( _keyDingOnMedium  ) ?? true;
  bool get dingOnHigh    => _prefs.getBool( _keyDingOnHigh    ) ?? true;
  bool get dingOnUrgent  => _prefs.getBool( _keyDingOnUrgent  ) ?? true;
  bool get speakOnHigh   => _prefs.getBool( _keySpeakOnHigh   ) ?? true;
  bool get speakOnUrgent => _prefs.getBool( _keySpeakOnUrgent ) ?? true;
  bool get masterMute    => _prefs.getBool( _keyMasterMute    ) ?? false;

  /// Spoken fraction of each message, snapped to 10% steps in [0.0, 1.0].
  double get ttsFraction {
    final v = _prefs.getDouble( keyTtsFraction ) ?? defaultTtsFraction;
    return snapTtsFraction( v );
  }

  static double snapTtsFraction( double v ) =>
      ( ( v.clamp( 0.0, 1.0 ) * 10 ).round() ) / 10.0;

  Future<void> setDingOnMedium(  bool v ) => _prefs.setBool( _keyDingOnMedium,  v );
  Future<void> setDingOnHigh(    bool v ) => _prefs.setBool( _keyDingOnHigh,    v );
  Future<void> setDingOnUrgent(  bool v ) => _prefs.setBool( _keyDingOnUrgent,  v );
  Future<void> setSpeakOnHigh(   bool v ) => _prefs.setBool( _keySpeakOnHigh,   v );
  Future<void> setSpeakOnUrgent( bool v ) => _prefs.setBool( _keySpeakOnUrgent, v );
  Future<void> setMasterMute(    bool v ) => _prefs.setBool( _keyMasterMute,    v );
  Future<void> setTtsFraction( double v ) => _prefs.setDouble( keyTtsFraction, snapTtsFraction( v ) );
}
