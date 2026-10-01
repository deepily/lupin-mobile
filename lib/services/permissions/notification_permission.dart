/// The single place the notification permission is requested.
///
/// The manifest declares `POST_NOTIFICATIONS`, but declaring a runtime permission does not grant it.
/// On Android 13 and later a fresh install starts denied. Every
/// `FlutterLocalNotificationsPlugin.show()` then does nothing, although the push wake chain logs "shown".
library;

import 'package:permission_handler/permission_handler.dart';

/// Test seam for [requestNotificationPermission]; production code uses the default.
typedef NotificationPermissionRequester = Future<bool> Function();

/// Log line that says notifications are denied; nothing else on the device reports it.
///
/// Search for it when pushes do not arrive.
const String kNotificationPermissionDeniedMarker =
    '[Notifications] PERMISSION DENIED';

/// Requests the notification permission and returns true when notifications may be posted.
///
/// Callers must not discard the result. A denial otherwise looks like a server problem or an
/// APK built without `--fcm`: the wake chain still logs "[FcmWake] shown".
/// `onWsAuthenticated` logs [kNotificationPermissionDeniedMarker] on false, so a test can check it.
///
/// Ensures:
///   - returns true iff notifications may be posted afterwards
///   - below Android 13 the permission is implicit and this returns true without a prompt
///   - once permanently denied, `request()` returns the existing status without prompting
///   - a single earlier denial on Android 13 is not permanent, so a later login may prompt again
Future<bool> requestNotificationPermission() async {
  final status = await Permission.notification.request();
  return status.isGranted;
}
