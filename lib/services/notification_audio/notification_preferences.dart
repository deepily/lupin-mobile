import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// User-tunable audio preferences for incoming notifications, backed by [SharedPreferences].
///
/// Every toggle defaults to the Lupin web client's behavior, so a first-run user hears what they hear on desktop.
/// The master mute overrides every other toggle.
///
/// Behavior by priority, by default:
///   - low is silent.
///   - medium dings.
///   - high dings and speaks the title and message.
///   - urgent dings with a distinct alert tone and speaks the title and message.
class NotificationPreferences {
  static const _keyDingOnMedium = 'notif_audio.ding_on_medium';
  static const _keyDingOnHigh   = 'notif_audio.ding_on_high';
  static const _keyDingOnUrgent = 'notif_audio.ding_on_urgent';
  static const _keySpeakOnHigh  = 'notif_audio.speak_on_high';
  static const _keySpeakOnUrgent = 'notif_audio.speak_on_urgent';
  static const _keyMasterMute   = 'notif_audio.master_mute';
  /// Preference key for the fraction of each message spoken automatically.
  ///
  /// The fraction moves in 10% steps and 1.0 is the whole message. It mirrors the web client's `#cc-tts-fraction-slider`.
  /// Design: src/docs/decisions/README.md (R-NA-tts-fraction)
  static const keyTtsFraction   = 'notif_audio.tts_fraction';
  /// Default of [keyTtsFraction]: 0.2.
  static const double defaultTtsFraction = 0.2;
  /// Preference key for speaking system senders.
  ///
  /// They are senders with no voice persona, such as test runners, hooks and scripts.
  /// Off mutes every persona-less sender in one switch, and personas keep speaking. The default is on.
  /// Design: src/docs/decisions/README.md (R-NA-system-senders)
  static const keySpeakSystemSenders = 'notif_audio.speak_system_senders';
  /// Debug preference key to keep a copy of every voice recording.
  ///
  /// The copy is made before the recording is deleted, for the Opus/AAC accuracy check. It lives here because this screen's Debug section is its only home. The default is off.
  static const keyKeepVoiceRecordings = 'debug.keep_voice_recordings';
  /// Preference key for placing documents below the conversation on a wide screen.
  ///
  /// A wide screen is, for example, an open Fold. Off places them beside it. On gives tables the full width. The viewer's own title bar flips it and the
  /// choice is remembered. The default is off.
  /// Design: src/docs/decisions/README.md (R-NA-docs-below-wide)
  static const keyDocsBelowWhenWide = 'docs.below_when_wide';
  /// Preference key for wake notifications from the background FCM path.
  ///
  /// One switch stops the phone lighting up while the app is closed. Off makes the wake handler a no-op:
  /// it does not fetch, show, speak or mark anything played. Every notification is still there, unplayed,
  /// when the app next opens. The default is on, which is the earlier behavior.
  /// Design: src/docs/decisions/README.md (R-NA-wake-switch)
  static const keyWakeNotifications = 'notif_audio.wake_notifications';

  // Notification management view: a master switch, then one switch per surface (app closed or open),
  // then one checkbox per priority under each.
  //
  // These govern whether a notification is raised at all. The ding and speak toggles above stay what they were:
  // how a raised notification sounds. Nothing here hides an item from a list or consumes it server-side.
  // Every default reproduces the earlier behavior, which is why they are not symmetric: an install that never
  // opens this view must behave exactly as it did before the view existed.
  // Design: src/docs/decisions/README.md (R-NA-raise-gate)

  /// Preference key for the master switch; off silences both surfaces at every priority.
  static const keyEnabled = 'notif.enabled';

  /// Preference key to raise notifications while the app is closed, on the FCM wake path.
  ///
  /// It supersedes [keyWakeNotifications], which seeds it once; see [backgroundEnabled].
  static const keyBackgroundEnabled = 'notif.background.enabled';

  /// Preference key to raise notifications while the app is open, on the WebSocket path.
  ///
  /// That covers the in-app ding and the spoken summary.
  static const keyForegroundEnabled = 'notif.foreground.enabled';

  /// The four server-side priorities, in ascending order of insistence.
  ///
  /// They match the parent repo's `valid_priorities` in `notifications.py`: `low`, `medium`, `high`, `urgent`.
  static const List<String> priorities = [ 'low', 'medium', 'high', 'urgent' ];

  /// `notif.background.priority.<p>` / `notif.foreground.priority.<p>`.
  static String priorityKey( String surface, String priority ) =>
      'notif.$surface.priority.$priority';

  /// Default of each background priority checkbox: on.
  ///
  /// The wake path shows every item it fetches, because `showNotification` is unconditional, so on is what
  /// unchanged means here.
  static const bool defaultBackgroundPriority = true;

  /// Default of a foreground priority checkbox: on except for `low`.
  ///
  /// `low` is already silent: `NotificationAudioService.handleIncoming` returns early for it and the TTS
  /// orchestrator's `_isSpeakable` excludes it. Defaulting it to on would start raising notifications that
  /// were never raised before.
  static bool defaultForegroundPriority( String priority ) => priority != 'low';

  // Mute by sender and quiet hours: they decide whether a notification is raised, never whether it exists.
  //
  // Every default leaves behavior as it was.
  // Design: src/docs/decisions/README.md (R-NA-mute-quiet)

  /// Preference key for muted senders: a JSON object of sender key to display label.
  ///
  /// The label is kept beside the key because a person should not have to read the key (`persona:maya`).
  /// An example label is "Maya" with the persona icon.
  static const keyMutedSenders = 'notif.muted.senders';

  /// Preference key: an urgent notification from a muted sender still gets through.
  ///
  /// The default is on, because a mute means stop the chatter, not never tell me about an emergency.
  static const keyMuteUrgentBypass = 'notif.muted.urgent_bypass';

  /// Preference key to turn quiet hours on.
  static const keyQuietEnabled      = 'notif.quiet.enabled';
  /// Preference key for the start of quiet hours, in minutes after local midnight.
  ///
  /// The window may cross midnight.
  static const keyQuietStart        = 'notif.quiet.start_minutes';
  /// Preference key for the end of quiet hours, in minutes after local midnight.
  static const keyQuietEnd          = 'notif.quiet.end_minutes';
  /// Preference key: an urgent notification still gets through during quiet hours.
  static const keyQuietUrgentBypass = 'notif.quiet.urgent_bypass';

  /// Default start of quiet hours: 22:00, in minutes after midnight.
  static const int defaultQuietStart = 22 * 60;  // 22:00
  /// Default end of quiet hours: 07:00, in minutes after midnight.
  static const int defaultQuietEnd   = 7 * 60;   // 07:00

  final SharedPreferences _prefs;
  /// Creates preferences over [_prefs].
  const NotificationPreferences( this._prefs );

  /// Muted sender key to label.
  ///
  /// Empty when nothing is muted and also when the stored value is unreadable: a corrupt blob must not mute anyone.
  Map<String, String> get mutedSenders {
    final raw = _prefs.getString( keyMutedSenders );
    if ( raw == null || raw.isEmpty ) return const {};
    try {
      final decoded = jsonDecode( raw );
      if ( decoded is! Map ) return const {};
      return {
        for ( final e in decoded.entries ) e.key.toString(): e.value.toString(),
      };
    } on FormatException {
      return const {};
    }
  }

  /// True when [key] is a muted sender; a null key is never muted.
  bool isSenderMuted( String? key ) => key != null && mutedSenders.containsKey( key );

  /// Mutes the sender [key] and stores [label] for display.
  Future<void> muteSender( String key, String label ) =>
      _writeMuted( { ...mutedSenders, key: label } );

  /// Unmutes the sender [key].
  Future<void> unmuteSender( String key ) =>
      _writeMuted( Map.of( mutedSenders )..remove( key ) );

  Future<void> _writeMuted( Map<String, String> m ) =>
      _prefs.setString( keyMutedSenders, jsonEncode( m ) );

  /// Whether urgent notifications bypass a sender mute; true when unset.
  bool get muteUrgentBypass  => _prefs.getBool( keyMuteUrgentBypass ) ?? true;
  /// Whether quiet hours are on; false when unset.
  bool get quietEnabled      => _prefs.getBool( keyQuietEnabled ) ?? false;
  /// Start of quiet hours in minutes after midnight.
  int  get quietStartMinutes => _prefs.getInt( keyQuietStart ) ?? defaultQuietStart;
  /// End of quiet hours in minutes after midnight.
  int  get quietEndMinutes   => _prefs.getInt( keyQuietEnd ) ?? defaultQuietEnd;
  /// Whether urgent notifications bypass quiet hours; true when unset.
  bool get quietUrgentBypass => _prefs.getBool( keyQuietUrgentBypass ) ?? true;

  /// Stores the sender-mute urgent bypass.
  Future<void> setMuteUrgentBypass( bool v ) => _prefs.setBool( keyMuteUrgentBypass, v );
  /// Turns quiet hours on or off.
  Future<void> setQuietEnabled( bool v )     => _prefs.setBool( keyQuietEnabled, v );
  /// Stores the quiet-hours start, wrapped into one day.
  Future<void> setQuietStartMinutes( int m ) => _prefs.setInt( keyQuietStart, m % ( 24 * 60 ) );
  /// Stores the quiet-hours end, wrapped into one day.
  Future<void> setQuietEndMinutes( int m )   => _prefs.setInt( keyQuietEnd, m % ( 24 * 60 ) );
  /// Stores the quiet-hours urgent bypass.
  Future<void> setQuietUrgentBypass( bool v ) => _prefs.setBool( keyQuietUrgentBypass, v );

  /// Whether [now], in local time, is inside the quiet window.
  ///
  /// Ensures:
  ///   - false whenever quiet hours are off
  ///   - start inclusive, end exclusive: 22:00-07:00 is quiet at 22:00, not at 07:00
  ///   - a window whose start is later than its end crosses midnight
  ///   - start equal to end is an empty window, never a 24-hour one: "22:00 to 22:00" is far more likely
  ///     a half-finished edit than a request for permanent silence
  bool inQuietHours( DateTime now ) {
    if ( !quietEnabled ) return false;
    final s = quietStartMinutes;
    final e = quietEndMinutes;
    final m = now.hour * 60 + now.minute;
    if ( s == e ) return false;
    return s < e ? ( m >= s && m < e ) : ( m >= s || m < e );
  }

  /// Whether a medium notification dings; true when unset.
  bool get dingOnMedium  => _prefs.getBool( _keyDingOnMedium  ) ?? true;
  /// Whether a high notification dings; true when unset.
  bool get dingOnHigh    => _prefs.getBool( _keyDingOnHigh    ) ?? true;
  /// Whether an urgent notification dings; true when unset.
  bool get dingOnUrgent  => _prefs.getBool( _keyDingOnUrgent  ) ?? true;
  /// Whether a high notification is spoken; true when unset.
  bool get speakOnHigh   => _prefs.getBool( _keySpeakOnHigh   ) ?? true;
  /// Whether an urgent notification is spoken; true when unset.
  bool get speakOnUrgent => _prefs.getBool( _keySpeakOnUrgent ) ?? true;
  /// Whether all notification audio is muted; false when unset.
  bool get masterMute    => _prefs.getBool( _keyMasterMute    ) ?? false;
  /// Whether system senders (no voice persona) are spoken; true when unset.
  bool get speakSystemSenders => _prefs.getBool( keySpeakSystemSenders ) ?? true;
  /// Whether voice recordings are kept for debugging; false when unset.
  bool get keepVoiceRecordings => _prefs.getBool( keyKeepVoiceRecordings ) ?? false;
  /// Whether documents sit below the conversation on a wide screen; false when unset.
  bool get docsBelowWhenWide   => _prefs.getBool( keyDocsBelowWhenWide ) ?? false;
  /// Whether the background wake path shows notifications; true when unset.
  bool get wakeNotifications   => _prefs.getBool( keyWakeNotifications ) ?? true;

  /// Whether notifications are raised at all; true when unset.
  bool get enabled           => _prefs.getBool( keyEnabled ) ?? true;
  /// Whether notifications are raised while the app is open; true when unset.
  bool get foregroundEnabled => _prefs.getBool( keyForegroundEnabled ) ?? true;

  /// Whether the background wake path may raise notifications.
  ///
  /// When this view's own key has never been written, the single wake switch [keyWakeNotifications] answers instead.
  /// A user who already turned wake notifications off therefore does not find them back on after updating.
  /// The old key is read, never deleted, so a rollback to the earlier build still finds the user's choice.
  bool get backgroundEnabled =>
      _prefs.getBool( keyBackgroundEnabled ) ??
      _prefs.getBool( keyWakeNotifications ) ??
      true;

  /// Whether [priority] may be raised on [surface], falling back to the surface default.
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

  /// Clamps [v] to [0.0, 1.0] and rounds it to the nearest 10%.
  static double snapTtsFraction( double v ) =>
      ( ( v.clamp( 0.0, 1.0 ) * 10 ).round() ) / 10.0;

  /// Stores whether a medium notification dings.
  Future<void> setDingOnMedium(  bool v ) => _prefs.setBool( _keyDingOnMedium,  v );
  /// Stores whether a high notification dings.
  Future<void> setDingOnHigh(    bool v ) => _prefs.setBool( _keyDingOnHigh,    v );
  /// Stores whether an urgent notification dings.
  Future<void> setDingOnUrgent(  bool v ) => _prefs.setBool( _keyDingOnUrgent,  v );
  /// Stores whether a high notification is spoken.
  Future<void> setSpeakOnHigh(   bool v ) => _prefs.setBool( _keySpeakOnHigh,   v );
  /// Stores whether an urgent notification is spoken.
  Future<void> setSpeakOnUrgent( bool v ) => _prefs.setBool( _keySpeakOnUrgent, v );
  /// Stores the master mute.
  Future<void> setMasterMute(    bool v ) => _prefs.setBool( _keyMasterMute,    v );
  /// Stores whether system senders are spoken.
  Future<void> setSpeakSystemSenders( bool v ) => _prefs.setBool( keySpeakSystemSenders, v );
  /// Stores whether voice recordings are kept.
  Future<void> setKeepVoiceRecordings( bool v ) => _prefs.setBool( keyKeepVoiceRecordings, v );
  /// Stores whether documents sit below the conversation on a wide screen.
  Future<void> setDocsBelowWhenWide( bool v ) => _prefs.setBool( keyDocsBelowWhenWide, v );
  /// Stores the wake-notifications switch.
  Future<void> setWakeNotifications( bool v ) => _prefs.setBool( keyWakeNotifications, v );
  /// Stores the master notification switch.
  Future<void> setEnabled( bool v ) => _prefs.setBool( keyEnabled, v );
  /// Stores whether notifications are raised while the app is open.
  Future<void> setForegroundEnabled( bool v ) => _prefs.setBool( keyForegroundEnabled, v );
  /// Stores whether notifications are raised while the app is closed.
  Future<void> setBackgroundEnabled( bool v ) => _prefs.setBool( keyBackgroundEnabled, v );
  /// Stores whether [priority] may be raised on [surface].
  Future<void> setPriorityEnabled( String surface, String priority, bool v ) =>
      _prefs.setBool( priorityKey( surface, priority ), v );
  /// Stores the spoken fraction, snapped to 10% steps.
  Future<void> setTtsFraction( double v ) => _prefs.setDouble( keyTtsFraction, snapTtsFraction( v ) );
}
