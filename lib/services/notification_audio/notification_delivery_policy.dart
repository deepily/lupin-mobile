import 'notification_preferences.dart';

/// Where a notification would be raised. The two surfaces are genuinely
/// different code paths, not two moods of one path: BACKGROUND is the FCM wake
/// chain running in a fresh isolate with the app closed, FOREGROUND is the
/// WebSocket path inside a live app.
enum NotificationSurface {
  background( 'background' ),
  foreground( 'foreground' );

  final String key;
  const NotificationSurface( this.key );
}

/// The one place that answers "should this notification be raised at all?"
/// (Rick 2026-09-28, row 7cac3a17 — "I'm getting bombarded").
///
/// Pure by design: no Flutter import, no service locator, nothing but a
/// [NotificationPreferences]. That is not tidiness — the background isolate
/// has no locator and no main-isolate state, so anything the wake chain
/// consults has to be constructible from SharedPreferences alone.
///
/// WHAT THIS DOES NOT DO. It never hides an item from a list and never marks
/// anything played. A suppressed notification is one the phone stays quiet
/// about; the item is still on the server, still unplayed, and still there when
/// the app is opened. Suppression is silence, never deletion.
///
/// It also does not decide how a raised notification SOUNDS. The ding and
/// speak toggles in [NotificationPreferences] keep that job; this gate sits in
/// front of them.
class NotificationDeliveryPolicy {
  final NotificationPreferences _prefs;
  const NotificationDeliveryPolicy( this._prefs );

  /// May a notification of [priority] be raised on [surface]?
  ///
  /// Requires:
  ///     - priority is a server priority string; anything unrecognised is
  ///       treated as denied rather than guessed at
  ///
  /// Ensures:
  ///     - returns true only when the master switch, the surface switch AND
  ///       that priority's own checkbox are all on
  ///     - never throws, never writes
  ///
  /// MUTE AND QUIET HOURS (row f1e80e67, plan §7.4). Two more denials, applied
  /// only after the three switches above have said yes — so an urgent the user
  /// switched off is never resurrected by a bypass:
  ///   - [senderKey] is muted            ⇒ denied, unless urgent and the mute bypass is on
  ///   - [now] falls inside quiet hours  ⇒ denied, unless urgent and the quiet bypass is on
  ///
  /// Requires:
  ///     - senderKey is `notificationSenderKey( item )`, or null when the
  ///       caller has no item (a null sender is never muted)
  ///     - now is local wall-clock time; it is a parameter so this stays pure,
  ///       and it defaults to DateTime.now() for callers that have no clock seam
  bool allows( {
    required NotificationSurface surface,
    required String              priority,
    String?                      senderKey,
    DateTime?                    now,
  } ) {
    if ( !_prefs.enabled ) return false;
    if ( !_surfaceEnabled( surface ) ) return false;
    // An unknown priority is DENIED, not defaulted to medium. A new server
    // tier arriving in a payload is a thing the user has never been offered a
    // checkbox for, so consent for it does not exist yet.
    if ( !NotificationPreferences.priorities.contains( priority ) ) return false;
    if ( !_prefs.priorityEnabled( surface.key, priority ) ) return false;

    final urgent = priority == 'urgent';
    if ( _prefs.isSenderMuted( senderKey ) && !( urgent && _prefs.muteUrgentBypass ) ) return false;
    if ( _prefs.inQuietHours( now ?? DateTime.now() ) && !( urgent && _prefs.quietUrgentBypass ) ) return false;
    return true;
  }

  /// Could ANY priority be raised on [surface]?
  ///
  /// This is the cheap pre-flight the background path needs: the wake chain
  /// has to decide whether to spend radio and battery BEFORE it knows what
  /// priority is waiting for it, because the priority only arrives with the
  /// fetch.
  ///
  /// Ensures:
  ///     - returns false iff [allows] would return false for every priority
  bool anyAllowedOn( NotificationSurface surface ) =>
      NotificationPreferences.priorities.any(
          ( p ) => allows( surface: surface, priority: p ) );

  bool _surfaceEnabled( NotificationSurface surface ) =>
      switch ( surface ) {
        NotificationSurface.background => _prefs.backgroundEnabled,
        NotificationSurface.foreground => _prefs.foregroundEnabled,
      };
}
