import 'notification_preferences.dart';

/// Where a notification would be raised: with the app closed or open.
///
/// The two surfaces are different code paths, not two moods of one path. Background is the FCM wake chain
/// running in a fresh isolate with the app closed. Foreground is the WebSocket path inside a live app.
enum NotificationSurface {
  /// Notifications raised by the FCM wake chain while the app is closed.
  background( 'background' ),
  /// Notifications raised by the WebSocket path while the app is open.
  foreground( 'foreground' );

  /// Key used in the per-surface preference names.
  final String key;
  /// Creates a surface with its preference [key].
  const NotificationSurface( this.key );
}

/// The one place that answers whether a notification should be raised at all.
///
/// Pure: no Flutter import, no service locator, nothing but a [NotificationPreferences]. The background isolate
/// has no locator and no main-isolate state, so anything the wake chain consults must be buildable from
/// SharedPreferences alone.
/// Design: src/docs/decisions/README.md (R-NA-raise-gate)
///
/// It never hides an item from a list and never marks anything played. A suppressed notification is one the
/// phone stays quiet about; the item stays on the server, unplayed, until the app is opened. Suppression is
/// silence, never deletion. It does not decide how a raised notification sounds.
/// The ding and speak toggles in [NotificationPreferences] keep that job, and this gate sits in front of them.
class NotificationDeliveryPolicy {
  final NotificationPreferences _prefs;
  /// Creates a policy on [_prefs].
  const NotificationDeliveryPolicy( this._prefs );

  /// Whether a notification of [priority] may be raised on [surface].
  ///
  /// Mute and quiet hours are two more denials, applied only after the three switches below have said yes.
  /// An urgent the user switched off is therefore never resurrected by a bypass.
  /// Design: src/docs/decisions/README.md (R-NA-mute-quiet)
  ///
  /// Requires:
  ///   - priority is a server priority string; anything unrecognised is treated as denied
  ///   - senderKey is `notificationSenderKey( item )`, or null when the caller has no item (a null sender is never muted)
  ///   - now is local wall-clock time; it defaults to DateTime.now() for callers with no clock seam
  ///
  /// Ensures:
  ///   - returns true only when the master switch, the surface switch and that priority's own checkbox are all on
  ///   - denied when [senderKey] is muted, unless the priority is urgent and the mute bypass is on
  ///   - denied when [now] falls inside quiet hours, unless the priority is urgent and the quiet bypass is on
  ///   - never throws, never writes
  bool allows( {
    required NotificationSurface surface,
    required String              priority,
    String?                      senderKey,
    DateTime?                    now,
  } ) {
    if ( !_prefs.enabled ) return false;
    if ( !_surfaceEnabled( surface ) ) return false;
    // An unknown priority is denied, not defaulted to medium. A new server tier arriving in a payload has
    // no checkbox the user was ever offered, so consent for it does not exist yet.
    if ( !NotificationPreferences.priorities.contains( priority ) ) return false;
    if ( !_prefs.priorityEnabled( surface.key, priority ) ) return false;

    final urgent = priority == 'urgent';
    if ( _prefs.isSenderMuted( senderKey ) && !( urgent && _prefs.muteUrgentBypass ) ) return false;
    if ( _prefs.inQuietHours( now ?? DateTime.now() ) && !( urgent && _prefs.quietUrgentBypass ) ) return false;
    return true;
  }

  /// Whether any priority could be raised on [surface].
  ///
  /// The background path needs this cheap pre-flight. The wake chain must decide whether to spend
  /// radio and battery first. It does not yet know the priority, which only arrives with the fetch.
  ///
  /// Ensures:
  ///   - returns false iff [allows] would return false for every priority
  bool anyAllowedOn( NotificationSurface surface ) =>
      NotificationPreferences.priorities.any(
          ( p ) => allows( surface: surface, priority: p ) );

  bool _surfaceEnabled( NotificationSurface surface ) =>
      switch ( surface ) {
        NotificationSurface.background => _prefs.backgroundEnabled,
        NotificationSurface.foreground => _prefs.foregroundEnabled,
      };
}
