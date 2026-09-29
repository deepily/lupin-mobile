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
  /// Speak SYSTEM senders (no voice persona: test runners, hooks, scripts)?
  /// Rick 2026-08-21: "how do I silence the system messages?" — OFF mutes
  /// every persona-less sender in one switch; personas keep speaking.
  /// Default ON (today's behaviour).
  static const keySpeakSystemSenders = 'notif_audio.speak_system_senders';
  /// Debug (row 9b1f7701): keep a WAV copy of every voice recording before
  /// it is deleted, for the Opus/AAC accuracy check. Lives here because this
  /// screen's Debug section is its only home. Default OFF.
  static const keyKeepVoiceRecordings = 'debug.keep_voice_recordings';
  /// Documents on a wide screen (an open Fold): beside the conversation, or
  /// below it so tables get the full width (Rick 2026-09-18). Flipped from
  /// the viewer's own title bar and remembered. Default OFF (beside).
  static const keyDocsBelowWhenWide = 'docs.below_when_wide';
  /// Wake notifications from the BACKGROUND FCM path (Rick 2026-09-28, row
  /// 1af7b3de): one switch to stop the phone lighting up while the app is
  /// closed. OFF makes the wake handler a no-op — it does not fetch, show,
  /// speak or mark anything played, so nothing is consumed: every notification
  /// is still there, unplayed, the next time the app opens. Default ON, which
  /// is today's behaviour.
  static const keyWakeNotifications = 'notif_audio.wake_notifications';

  // ── Notification management view (Rick 2026-09-28, row 7cac3a17) ─────────
  // "I'm getting bombarded." A master switch, then one switch per SURFACE
  // (is the app closed or open?), then one checkbox per PRIORITY under each.
  //
  // These govern whether a notification is RAISED AT ALL. The ding/speak
  // toggles above stay what they were — how a raised notification sounds.
  // Nothing here ever hides an item from a list or consumes it server-side.
  //
  // 🔴 EVERY DEFAULT REPRODUCES TODAY'S BEHAVIOUR, which is why they are not
  // symmetric. An install that never opens this view must behave exactly as it
  // did before the view existed.

  /// The master switch. OFF silences both surfaces at every priority.
  static const keyEnabled = 'notif.enabled';

  /// Raise notifications while the app is CLOSED (the FCM wake path).
  /// Supersedes [keyWakeNotifications], which seeds it once — see
  /// [backgroundEnabled].
  static const keyBackgroundEnabled = 'notif.background.enabled';

  /// Raise notifications while the app is OPEN (the WebSocket path: the
  /// in-app ding and the spoken summary).
  static const keyForegroundEnabled = 'notif.foreground.enabled';

  /// The four server-side priorities, in ascending order of insistence.
  /// Confirmed against the parent repo: `notifications.py:954`,
  /// `valid_priorities = ["low", "medium", "high", "urgent"]`.
  static const List<String> priorities = [ 'low', 'medium', 'high', 'urgent' ];

  /// `notif.background.priority.<p>` / `notif.foreground.priority.<p>`.
  static String priorityKey( String surface, String priority ) =>
      'notif.$surface.priority.$priority';

  /// Background defaults to ON at every priority: the wake path shows every
  /// item it fetches today — `showNotification` is unconditional — so ON is
  /// what "unchanged" means here.
  static const bool defaultBackgroundPriority = true;

  /// Foreground defaults to ON except `low`, which is already silent today:
  /// `NotificationAudioService.handleIncoming` returns early for it and the
  /// TTS orchestrator's `_isSpeakable` excludes it. Defaulting low to ON would
  /// start raising notifications that have never been raised before — the
  /// opposite of what row 7cac3a17 asks for.
  static bool defaultForegroundPriority( String priority ) => priority != 'low';

  final SharedPreferences _prefs;
  const NotificationPreferences( this._prefs );

  bool get dingOnMedium  => _prefs.getBool( _keyDingOnMedium  ) ?? true;
  bool get dingOnHigh    => _prefs.getBool( _keyDingOnHigh    ) ?? true;
  bool get dingOnUrgent  => _prefs.getBool( _keyDingOnUrgent  ) ?? true;
  bool get speakOnHigh   => _prefs.getBool( _keySpeakOnHigh   ) ?? true;
  bool get speakOnUrgent => _prefs.getBool( _keySpeakOnUrgent ) ?? true;
  bool get masterMute    => _prefs.getBool( _keyMasterMute    ) ?? false;
  bool get speakSystemSenders => _prefs.getBool( keySpeakSystemSenders ) ?? true;
  bool get keepVoiceRecordings => _prefs.getBool( keyKeepVoiceRecordings ) ?? false;
  bool get docsBelowWhenWide   => _prefs.getBool( keyDocsBelowWhenWide ) ?? false;
  bool get wakeNotifications   => _prefs.getBool( keyWakeNotifications ) ?? true;

  bool get enabled           => _prefs.getBool( keyEnabled ) ?? true;
  bool get foregroundEnabled => _prefs.getBool( keyForegroundEnabled ) ?? true;

  /// Whether the background wake path may raise notifications.
  ///
  /// MIGRATION (row 7cac3a17 supersedes row 1af7b3de): when this view's own key
  /// has never been written, Pocholo's single wake switch answers instead, so a
  /// user who already turned wake notifications off does not find them back on
  /// after updating. The old key is READ, never deleted — a rollback to his
  /// branch has to still find the user's choice where it left it.
  bool get backgroundEnabled =>
      _prefs.getBool( keyBackgroundEnabled ) ??
      _prefs.getBool( keyWakeNotifications ) ??
      true;

  bool priorityEnabled( String surface, String priority ) =>
      _prefs.getBool( priorityKey( surface, priority ) ) ??
      ( surface == 'background'
          ? defaultBackgroundPriority
          : defaultForegroundPriority( priority ) );

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
  Future<void> setSpeakSystemSenders( bool v ) => _prefs.setBool( keySpeakSystemSenders, v );
  Future<void> setKeepVoiceRecordings( bool v ) => _prefs.setBool( keyKeepVoiceRecordings, v );
  Future<void> setDocsBelowWhenWide( bool v ) => _prefs.setBool( keyDocsBelowWhenWide, v );
  Future<void> setWakeNotifications( bool v ) => _prefs.setBool( keyWakeNotifications, v );
  Future<void> setEnabled( bool v ) => _prefs.setBool( keyEnabled, v );
  Future<void> setForegroundEnabled( bool v ) => _prefs.setBool( keyForegroundEnabled, v );
  Future<void> setBackgroundEnabled( bool v ) => _prefs.setBool( keyBackgroundEnabled, v );
  Future<void> setPriorityEnabled( String surface, String priority, bool v ) =>
      _prefs.setBool( priorityKey( surface, priority ), v );
  Future<void> setTtsFraction( double v ) => _prefs.setDouble( keyTtsFraction, snapTtsFraction( v ) );
}
