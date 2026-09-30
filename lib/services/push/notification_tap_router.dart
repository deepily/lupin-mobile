/// Holds a notification tap until there is somewhere to send it (row d9bc6f6c).
///
/// WHY A HOLDER AND NOT A DIRECT CALL. A tap arrives at one of two moments, and
/// neither of them is a moment when the app can act on it:
///
///   COLD START — the app was swiped away. `getNotificationAppLaunchDetails()`
///   answers during `main()`, before `runApp`, so there is no FocusChatBloc, no
///   authenticated user and no fingerprint unlock yet.
///
///   WARM TAP — the app is alive but sitting behind the lock screen or the login
///   form. `onDidReceiveNotificationResponse` fires immediately, and dispatching
///   a sender selection into an unauthenticated app selects nothing.
///
/// Both therefore [offer] the tap here, and the authenticated app [takePending]s
/// it once — after `AuthAuthenticated`, when the email needed to backfill the
/// conversation is finally in hand.
///
/// 🔴 HANDLE-ONCE IS THE POINT, NOT A NICETY. The plugin's own documentation
/// says the callback covers "the application was running" and launch-details
/// cover "a notification launched an application", which reads as mutually
/// exclusive — but that is a documented intent, not a guarantee this app can
/// verify on every OEM Android build, and a duplicate would re-select a sender
/// under the user's thumb a second later. Deduping by notification id makes the
/// question moot instead of betting on the answer: offering the same tap twice
/// is a no-op, whichever path offered it first.
library;

import 'dart:async';

import 'notification_tap_payload.dart';

class NotificationTapRouter {
  /// The tap waiting to be consumed, or null. ONE slot, deliberately: if two
  /// taps arrive before the app can route either, the user's most recent
  /// intention is the one worth honouring, and a queue would walk them through
  /// a conversation they have already stopped caring about.
  NotificationTapPayload? _pending;

  /// Notification ids already routed in this process. Bounded by [_maxHandled]
  /// so a long-lived app cannot grow this without limit.
  final List<String> _handled = <String>[];
  static const int   _maxHandled = 64;

  final StreamController<NotificationTapPayload> _taps =
      StreamController<NotificationTapPayload>.broadcast();

  /// Taps arriving while the app is already authenticated and listening. The
  /// pending slot covers the other case; a listener here must still call
  /// [takePending] on becoming authenticated, and the dedupe keeps the two from
  /// double-routing the same tap.
  Stream<NotificationTapPayload> get taps => _taps.stream;

  /// Is a tap waiting? Read-only — does not consume.
  bool get hasPending => _pending != null;

  /// Record a tap.
  ///
  /// Requires:
  ///   - payload may be null (an undecodable tap, or a fallback notification
  ///     with nothing to route) — such a tap is simply dropped
  ///
  /// Ensures:
  ///   - a payload whose notificationId was already handled is IGNORED: the
  ///     pending slot is untouched and nothing is emitted
  ///   - otherwise the payload becomes [_pending] AND is emitted on [taps]
  ///   - a non-routable payload (no senderId) is still dropped rather than
  ///     stored: there is nothing for a consumer to do with it, and storing it
  ///     would let it displace a routable tap offered moments later
  void offer( NotificationTapPayload? payload ) {
    if ( payload == null ) return;
    if ( !payload.isRoutable ) return;
    if ( _handled.contains( payload.notificationId ) ) return;
    _pending = payload;
    if ( !_taps.isClosed ) _taps.add( payload );
  }

  /// Consume the pending tap, marking it handled so no later [offer] of the
  /// same notification repeats it.
  ///
  /// Ensures:
  ///   - returns the pending payload and clears the slot, or null when empty
  ///   - a second call with no intervening [offer] returns null
  NotificationTapPayload? takePending() {
    final payload = _pending;
    _pending = null;
    if ( payload != null ) markHandled( payload );
    return payload;
  }

  /// Mark a payload routed. Called by [takePending], and separately by a
  /// stream consumer that routed a tap without going through the slot.
  void markHandled( NotificationTapPayload payload ) {
    if ( _handled.contains( payload.notificationId ) ) return;
    _handled.add( payload.notificationId );
    if ( _handled.length > _maxHandled ) _handled.removeAt( 0 );
    // A tap routed off the stream leaves the slot holding the same payload;
    // clearing it here is what stops the next takePending() repeating it.
    if ( _pending?.notificationId == payload.notificationId ) _pending = null;
  }

  Future<void> dispose() => _taps.close();
}
