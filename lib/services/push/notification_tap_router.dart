/// Holds a notification tap until the app can route it.
///
/// A tap arrives at one of two moments, and in neither can the app act on it:
///   - Cold start: the app was swiped away. `getNotificationAppLaunchDetails()` answers during `main()`,
///     before `runApp`, so there is no FocusChatBloc, no authenticated user and no fingerprint unlock yet.
///   - Warm tap: the app is alive but behind the lock screen or login form. The callback fires at once,
///     and dispatching a sender selection into an unauthenticated app selects nothing.
///
/// Both [offer] the tap here. The authenticated app [takePending]s it once, after `AuthAuthenticated`.
/// Only then is the email needed to backfill the conversation in hand.
///
/// Each notification is handled once. The plugin documents the callback and the launch details as mutually exclusive.
/// That is intent, not a guarantee this app can verify on every OEM Android build.
/// A duplicate would re-select a sender under the user's thumb a second later.
/// Deduping by notification id makes the question moot: offering the same tap twice is a no-op.
library;

import 'dart:async';

import 'notification_tap_payload.dart';

/// Holder that dedupes and delivers notification taps; see the library note.
class NotificationTapRouter {
  /// The tap waiting to be consumed, or null.
  ///
  /// There is a single slot. If two taps arrive before the app can route either, the most recent one is the
  /// user's intent. A queue would walk them through a conversation they no longer care about.
  NotificationTapPayload? _pending;

  /// Notification ids already routed in this process.
  ///
  /// Bounded by [_maxHandled], so a long-lived app cannot grow it without limit.
  final List<String> _handled = <String>[];
  static const int   _maxHandled = 64;

  final StreamController<NotificationTapPayload> _taps =
      StreamController<NotificationTapPayload>.broadcast();

  /// Taps arriving while the app is already authenticated and listening.
  ///
  /// The pending slot covers the other case. A listener here must still call [takePending] on becoming authenticated,
  /// and the dedupe keeps the two from double-routing the same tap.
  Stream<NotificationTapPayload> get taps => _taps.stream;

  /// True when a tap is waiting; reading it does not consume the tap.
  bool get hasPending => _pending != null;

  /// Records a tap.
  ///
  /// Requires:
  ///   - payload may be null (an undecodable tap, or a fallback notification with nothing to route); such a tap is dropped
  ///
  /// Ensures:
  ///   - a payload whose notificationId was already handled is ignored: the pending slot is untouched and nothing is emitted
  ///   - otherwise the payload becomes [_pending] and is emitted on [taps]
  ///   - a non-routable payload (no senderId) is dropped rather than stored: a consumer can do nothing with it,
  ///     and storing it would let it displace a routable tap offered moments later
  void offer( NotificationTapPayload? payload ) {
    if ( payload == null ) return;
    if ( !payload.isRoutable ) return;
    if ( _handled.contains( payload.notificationId ) ) return;
    _pending = payload;
    if ( !_taps.isClosed ) _taps.add( payload );
  }

  /// Consumes the pending tap and marks it handled.
  ///
  /// A later [offer] of the same notification is then ignored.
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

  /// Marks a payload routed.
  ///
  /// Called by [takePending], and separately by a stream consumer that routed a tap without going through the slot.
  void markHandled( NotificationTapPayload payload ) {
    if ( _handled.contains( payload.notificationId ) ) return;
    _handled.add( payload.notificationId );
    if ( _handled.length > _maxHandled ) _handled.removeAt( 0 );
    // A tap routed off the stream leaves the slot holding the same payload. Clearing it here stops the next takePending() repeating the tap.
    if ( _pending?.notificationId == payload.notificationId ) _pending = null;
  }

  /// Closes the [taps] stream.
  Future<void> dispose() => _taps.close();
}
