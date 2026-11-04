import 'package:shared_preferences/shared_preferences.dart';

/// Persisted choice of how a spoken Quick Ask leaves the phone.
///
/// Backed by [SharedPreferences], shaped after `NotificationPreferences`.
/// Review first (the default) stops, transcribes, holds the draft, and sends
/// when the user taps send. Send immediately makes one request to
/// `/api/v2/ask-audio`, whose two-line reply carries the transcript, then the job id.
/// Design: src/docs/decisions/README.md (R-QA-review-first)
class QuickAskPreferences {
  /// Storage key for [sendImmediately]; never rename it.
  ///
  /// A shipped key lives in each device's [SharedPreferences], so renaming it
  /// silently resets every user's choice with no error or log. The dotted form
  /// matches the `notif_audio.*` convention.
  static const keySendImmediately = 'quick_ask.send_immediately';

  /// Value of [sendImmediately] when nothing is stored: review first.
  static const bool defaultSendImmediately = false;

  final SharedPreferences _prefs;
  /// Wraps an already-loaded [SharedPreferences].
  const QuickAskPreferences( this._prefs );

  /// True when a recording is sent without a review step.
  bool get sendImmediately => _prefs.getBool( keySendImmediately ) ?? defaultSendImmediately;

  /// Persists [v] as the send-immediately choice.
  Future<void> setSendImmediately( bool v ) => _prefs.setBool( keySendImmediately, v );
}
