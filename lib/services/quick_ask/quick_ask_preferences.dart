import 'package:shared_preferences/shared_preferences.dart';

/// How a spoken Quick Ask leaves the phone.
///
/// Backed by [SharedPreferences], shaped after `NotificationPreferences`.
///
///   review first (default) : stop → transcribe → HOLD the draft → the user
///                            taps send. Today's path, unchanged.
///   send immediately       : stop → one request to `/api/v2/ask-audio`,
///                            whose two-line reply carries the transcript and
///                            then the job id.
///
/// The default is review first by Rick's ruling (2026-09-11, decision 9df9f1c2).
class QuickAskPreferences {
  /// 🔴 A ONE-WAY DOOR (plan SC3 / C-J4). Once this spelling reaches a device
  /// it lives in that device's `SharedPreferences`, and renaming it later
  /// silently resets every user's choice — no error, no failing test, no log.
  /// The dotted form matches the house convention (`notif_audio.*`). Do not
  /// "tidy" it.
  static const keySendImmediately = 'quick_ask.send_immediately';

  static const bool defaultSendImmediately = false;

  final SharedPreferences _prefs;
  const QuickAskPreferences( this._prefs );

  bool get sendImmediately => _prefs.getBool( keySendImmediately ) ?? defaultSendImmediately;

  Future<void> setSendImmediately( bool v ) => _prefs.setBool( keySendImmediately, v );
}
