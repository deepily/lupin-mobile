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

/// The grep-able line for "notifications are denied, that is why nothing
/// arrives". Nothing else on the device will say it (review F8).
const String kNotificationPermissionDeniedMarker =
    '[Notifications] PERMISSION DENIED';

/// Request the notification permission, raising the system prompt when it
/// has not yet been decided.
///
/// 🔴 THE CALLER MUST NOT DISCARD THE RESULT, BECAUSE A DENIAL IS OTHERWISE
/// INVISIBLE. Denied, the wake chain still runs end to end and still logs
/// "[FcmWake] shown" while the shade stays empty — bit for bit the bug this file
/// was added to fix, only now with the fix installed and nothing to distinguish
/// it from a server problem or an APK built without --fcm. `onWsAuthenticated`
/// logs [kNotificationPermissionDeniedMarker] on a false; it does that rather
/// than this function doing it, so the behaviour sits behind the injectable seam
/// and a test can actually prove it (review F8).
///
/// Ensures:
///   - returns true iff notifications may be posted afterwards
///   - below Android 13 the permission is implicit and this returns true
///     without a prompt
///
/// Note on calling this every login: once PERMANENTLY denied, `request()`
/// returns the existing status without prompting. A single earlier denial is not
/// permanent on Android 13 (the platform allows a second ask), so the next login
/// may prompt again — which is the platform's intended behaviour, not a bug, but
/// it is not the "never prompts again" this comment used to claim.
Future<bool> requestNotificationPermission() async {
  final status = await Permission.notification.request();
  return status.isGranted;
}
