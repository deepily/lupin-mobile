/// What a posted Android notification carries so a TAP can be routed back to
/// the message it was about (row d9bc6f6c).
///
/// 🔴 THIS CROSSES A PROCESS BOUNDARY, SO IT IS UNTRUSTED INPUT ON THE WAY BACK.
/// The string is written by the background isolate (or by a build of the app
/// that is no longer installed), stored by the Android system inside the
/// notification's intent, and read by a FRESH main isolate — possibly days
/// later, possibly after an app upgrade. Nothing guarantees the shape survives
/// that trip, and [decode] is therefore total: every malformed, empty, legacy
/// or truncated payload returns null rather than throwing. A tap that cannot be
/// decoded degrades to a plain app launch, which is exactly the behaviour this
/// row is replacing — so the failure mode of the fix is the status quo, never a
/// crash on the launch path.
library;

import 'dart:convert';

/// The two identifiers a tap needs: WHICH message, and WHOSE conversation.
///
/// `senderId` is nullable because the wake path posts notifications that
/// genuinely belong to nobody — the `ws_wake` fallbacks ("New activity. Open
/// Lupin to see it.") are posted when the fetch returned nothing or failed, so
/// there is no sender to select. Those tap through to Focus mode unchanged.
class NotificationTapPayload {
  /// The backend `NotificationItem.id` of the message that was SHOWN.
  ///
  /// ⚠️ Not the id of whatever triggered the wake. `GET /api/notifications/
  /// {user_id}/next` returns the OLDEST unplayed item, which need not be the
  /// one that caused the push (Tiffany, 2026-09-28). The payload is built from
  /// the item the notification actually displays, so the tap lands on the
  /// message the user read on their lock screen.
  final String  notificationId;

  /// The `sender_id` of that item — the rail's key (`email#hash`), and the
  /// argument [FocusSenderSelected] takes. Null ⇒ nothing to select.
  final String? senderId;

  const NotificationTapPayload( {
    required this.notificationId,
    this.senderId,
  } );

  /// Build from the raw `notification` map the wake chain fetched, or null when
  /// that map carries no usable id.
  ///
  /// Requires:
  ///   - item is the server's `notification` object, or null
  ///
  /// Ensures:
  ///   - returns null when item is null or its `id` is absent/blank — a payload
  ///     with no notification id can route nothing, and an empty-string id
  ///     would defeat the handle-once dedupe in [NotificationTapRouter]
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

  /// The string handed to `FlutterLocalNotificationsPlugin.show( payload: … )`.
  String encode() => jsonEncode( <String, dynamic>{
    'notification_id' : notificationId,
    if ( senderId != null ) 'sender_id' : senderId,
  } );

  /// Read a payload back off a tap. TOTAL — see the library note.
  ///
  /// Ensures:
  ///   - null for null, empty, non-JSON, non-object, or id-less input
  ///   - never throws, for any input whatsoever
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
      // A payload written by an older build, or a truncated one. The tap still
      // opens the app; it just cannot say where to go.
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
