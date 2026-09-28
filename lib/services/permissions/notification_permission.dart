/// The ONE place the notification permission is REQUESTED (row 8ff78c69).
///
/// 🔴 The manifest declares `POST_NOTIFICATIONS`, and until 2026-09-28 nothing
/// ever asked for it. On Android 13+ a fresh install starts DENIED, so every
/// `FlutterLocalNotificationsPlugin.show()` silently did nothing: the FCM wake
/// chain ran end to end on the emulator, logged "shown", and the shade stayed
/// empty. Declaring a runtime permission is not the same as holding it.
library;

import 'package:permission_handler/permission_handler.dart';

/// The seam. Tests substitute this; production leaves it alone.
typedef NotificationPermissionRequester = Future<bool> Function();

/// Request the notification permission, raising the system prompt when it
/// has not yet been decided.
///
/// Ensures:
///   - returns true iff notifications may be posted afterwards
///   - below Android 13 the permission is implicit and this returns true
///     without a prompt; once granted or permanently denied, `request()`
///     returns the existing status without a prompt, so calling it on every
///     login is safe
Future<bool> requestNotificationPermission() async {
  final status = await Permission.notification.request();
  return status.isGranted;
}
