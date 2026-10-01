/// Main-isolate wiring that turns an Android notification tap into a routable payload.
///
/// Both halves of the plugin's tap API are needed, and neither substitutes for the other:
///   - `onDidReceiveNotificationResponse` fires when the app was already running at the tap,
///     in the foreground or backgrounded but not killed.
///   - `getNotificationAppLaunchDetails()` covers a tap that launched the app, the case where the
///     app was swiped away when the notification arrived.
///
/// The plugin's own documentation says the same.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_tap_payload.dart';
import 'notification_tap_router.dart';

/// The Android init settings every main-isolate `initialize()` call must use.
///
/// Shared so the two call sites cannot drift into disagreeing about the icon.
const AndroidInitializationSettings kAndroidNotificationInit =
    AndroidInitializationSettings( '@mipmap/ic_launcher' );

/// Plugin init settings built from [kAndroidNotificationInit].
const InitializationSettings kNotificationInitSettings =
    InitializationSettings( android: kAndroidNotificationInit );

/// Builds the tap callback that feeds [router].
///
/// Ensures:
///   - an undecodable or sender-less payload is offered as null or non-routable, and the router drops
///     it; the tap still opened the app
DidReceiveNotificationResponseCallback notificationTapSink(
    NotificationTapRouter router ) {
  return ( NotificationResponse response ) {
    final payload = NotificationTapPayload.decode( response.payload );
    if ( payload == null ) {
      debugPrint( '[NotifTap] tap with no routable payload '
                  '(raw="${ response.payload }") — opening the app only' );
      return;
    }
    debugPrint( '[NotifTap] tap → $payload' );
    router.offer( payload );
  };
}

/// Initializes the plugin with the tap callback, then drains the launch intent.
///
/// Call it from `main()` before `runApp`, so a cold-start tap is in the router before the first authenticated frame.
/// `initialize()` installs the callback by assignment on a singleton plugin, so a later call without it silently unbinds taps.
/// `NotificationAudioService.initialize()` runs on the first ding and forwards it; see `test/unit/services/push/notification_tap_binding_test.dart`.
///
/// Requires:
///   - plugin is the main-isolate plugin instance
///
/// Ensures:
///   - the tap callback is installed
///   - when a notification launched the app, its payload is offered to [router] before this future completes
///   - returns the launch details for logging; never throws, because a plugin failure must not take down `main()`
Future<NotificationAppLaunchDetails?> bindNotificationTaps( {
  required FlutterLocalNotificationsPlugin plugin,
  required NotificationTapRouter           router,
} ) async {
  try {
    await plugin.initialize(
      kNotificationInitSettings,
      onDidReceiveNotificationResponse: notificationTapSink( router ),
    );

    final details = await plugin.getNotificationAppLaunchDetails();
    if ( details != null && details.didNotificationLaunchApp ) {
      final payload =
          NotificationTapPayload.decode( details.notificationResponse?.payload );
      debugPrint( '[NotifTap] cold start from a notification: '
                  '${ payload ?? "no routable payload" }' );
      router.offer( payload );
    }
    return details;
  } catch ( e ) {
    // An emulator without the plugin's platform side, or a plugin channel that is not ready. Taps degrade to a plain launch, never a failed startup.
    debugPrint( '[NotifTap] tap binding unavailable: $e' );
    return null;
  }
}
