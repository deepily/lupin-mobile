/// Main-isolate wiring that turns an Android notification tap into something
/// the app can route (row d9bc6f6c). Both halves of the plugin's tap API are
/// needed, and neither substitutes for the other:
///
///   `onDidReceiveNotificationResponse`  the app was ALREADY RUNNING when the
///                                      user tapped (foreground, or backgrounded
///                                      but not killed)
///   `getNotificationAppLaunchDetails()` the tap LAUNCHED the app — the case
///                                      Rick reported, since the app was swiped
///                                      away when the notification arrived
///
/// The plugin's own doc for the callback says so in as many words: *"fired when
/// the user selects a notification … [while the] application was running. To
/// handle when a notification launched an application, use
/// getNotificationAppLaunchDetails."*
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notification_tap_payload.dart';
import 'notification_tap_router.dart';

/// The Android init settings every main-isolate `initialize()` call must use.
/// Shared so the two call sites cannot drift into disagreeing about the icon.
const AndroidInitializationSettings kAndroidNotificationInit =
    AndroidInitializationSettings( '@mipmap/ic_launcher' );

const InitializationSettings kNotificationInitSettings =
    InitializationSettings( android: kAndroidNotificationInit );

/// Build the tap callback that feeds [router].
///
/// Ensures:
///   - an undecodable or sender-less payload is offered as null / non-routable
///     and the router drops it — the tap still opened the app
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

/// Initialize the plugin WITH the tap callback, then drain the launch intent.
///
/// Call this from `main()` before `runApp`, so a cold-start tap is already in
/// the router by the time the first authenticated frame can consume it.
///
/// 🔴 `initialize()` INSTALLS THE CALLBACK BY ASSIGNMENT, AND THE PLUGIN IS A
/// SINGLETON (`factory FlutterLocalNotificationsPlugin() => _instance`). So a
/// LATER `initialize()` that omits the callback sets it to null and silently
/// unbinds taps. `NotificationAudioService.initialize()` used to be exactly such
/// a call — it runs lazily, on the first ding — which would have made taps work
/// until the first notification arrived and then stop, intermittently, in a way
/// no cold-start test would catch. It now forwards the same callback; see the
/// regression test in `test/unit/services/push/notification_tap_binding_test.dart`.
///
/// Requires:
///   - plugin is the main-isolate plugin instance
///
/// Ensures:
///   - the tap callback is installed
///   - when the app WAS launched by a notification, its payload is offered to
///     [router] before this future completes
///   - returns the launch details for logging; never throws — a plugin failure
///     here must not take down `main()`, whose next line runs the app
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
    // An emulator without the plugin's platform side, or a plugin channel that
    // is not ready. Taps degrade to a plain launch, which is the pre-fix
    // behaviour — never a failed startup.
    debugPrint( '[NotifTap] tap binding unavailable: $e' );
    return null;
  }
}
