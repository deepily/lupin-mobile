/// What a posted Android notification carries so a tap can be routed back to its message.
///
/// The payload crosses a process boundary, so it is untrusted input on the way back.
/// The background isolate, or a build no longer installed, writes the string.
/// Android stores it in the notification's intent, and a fresh main isolate reads it, possibly days later.
/// Nothing guarantees the shape survives, so [decode] is total: every malformed, empty, legacy or
/// truncated payload returns null instead of throwing.
/// A tap that cannot be decoded degrades to a plain app launch, never a crash on the launch path.
library;

import 'dart:convert';

/// The two identifiers a tap needs: which message, and whose conversation.
///
/// `senderId` is nullable because the wake path posts notifications that belong to nobody. The `ws_wake`
/// fallbacks ("New activity. Open Lupin to see it.") go out when the fetch returned nothing or failed, so there
/// is no sender to select. Those tap through to Focus mode unchanged.
class NotificationTapPayload {
  /// The backend `NotificationItem.id` of the message that was shown.
  ///
  /// It is not the id of whatever triggered the wake.
  /// `GET /api/notifications/{user_id}/next` returns the oldest unplayed item, which need not have caused the push.
  /// The payload is built from the item the notification displays, so the tap lands on the message
  /// the user read on the lock screen.
  final String  notificationId;

  /// The `sender_id` of that item: the rail's key (`email#hash`).
  ///
  /// [FocusSenderSelected] takes it as its argument. Null means there is nothing to select.
  final String? senderId;

  /// Creates a payload.
  const NotificationTapPayload( {
    required this.notificationId,
    this.senderId,
  } );

  /// Builds a payload from the fetched `notification` map, or null when it has no usable id.
  ///
  /// Requires:
  ///   - item is the server's `notification` object, or null
  ///
  /// Ensures:
  ///   - returns null when item is null or its `id` is absent or blank: a payload with no notification id can
  ///     route nothing, and an empty-string id would defeat the handle-once dedupe in [NotificationTapRouter]
  ///   - a blank or absent `sender_id` becomes null, never the string ""
  static NotificationTapPayload? fromNotification( Map<String, dynamic>? item ) {
    if ( item == null ) return null;
    final id = item[ 'id' ]?.toString().trim() ?? '';
    if ( id.isEmpty ) return null;
    final sender = item[ 'sender_id' ]?.toString().trim() ?? '';
    return NotificationTapPayload(
      notificationId : id,
      senderId       : sender.isEmpty ? null : sender,
    );
  }

  /// The string handed to `FlutterLocalNotificationsPlugin.show( payload: ... )`.
  String encode() => jsonEncode( <String, dynamic>{
    'notification_id' : notificationId,
    if ( senderId != null ) 'sender_id' : senderId,
  } );

  /// Reads a payload back off a tap; total, see the library note.
  ///
  /// Ensures:
  ///   - null for null, empty, non-JSON, non-object or id-less input
  ///   - never throws, for any input
  static NotificationTapPayload? decode( String? raw ) {
    if ( raw == null || raw.trim().isEmpty ) return null;
    try {
      final decoded = jsonDecode( raw );
      if ( decoded is! Map ) return null;
      final id = decoded[ 'notification_id' ]?.toString().trim() ?? '';
      if ( id.isEmpty ) return null;
      final sender = decoded[ 'sender_id' ]?.toString().trim() ?? '';
      return NotificationTapPayload(
        notificationId : id,
        senderId       : sender.isEmpty ? null : sender,
      );
    } catch ( _ ) {
      // A payload written by an older build, or a truncated one. The tap still opens the app; it cannot say where to go.
      return null;
    }
  }

  /// True when this tap can actually select a conversation.
  bool get isRoutable => senderId != null;

  @override
  String toString() =>
      'NotificationTapPayload(id=$notificationId sender=${ senderId ?? "-" })';

  @override
  bool operator ==( Object other ) =>
      other is NotificationTapPayload &&
      other.notificationId == notificationId &&
      other.senderId       == senderId;

  @override
  int get hashCode => Object.hash( notificationId, senderId );
}
