import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lupin_mobile/services/notification_audio/notification_audio_service.dart';
import 'package:lupin_mobile/services/notification_audio/notification_preferences.dart';
import 'package:lupin_mobile/services/push/notification_tap_binding.dart';
import 'package:lupin_mobile/services/push/notification_tap_payload.dart';
import 'package:lupin_mobile/services/push/notification_tap_router.dart';

class _MockPlugin extends Mock implements FlutterLocalNotificationsPlugin {}
class _MockTts extends Mock implements FlutterTts {}
class _FakeInitSettings extends Fake implements InitializationSettings {}

/// Row d9bc6f6c — the main-isolate tap binding, and the singleton hazard under it.
void main() {
  setUpAll( () => registerFallbackValue( _FakeInitSettings() ) );

  late _MockPlugin plugin;
  late NotificationTapRouter router;

  /// Capture the callback `initialize` was given, so a test can fire it the way
  /// the platform would.
  DidReceiveNotificationResponseCallback? installedCallback;

  setUp( () {
    plugin = _MockPlugin();
    router = NotificationTapRouter();
    installedCallback = null;

    when( () => plugin.initialize( any(),
        onDidReceiveNotificationResponse:
            any( named: 'onDidReceiveNotificationResponse' ) ) )
      .thenAnswer( ( inv ) async {
        installedCallback = inv.namedArguments[
            const Symbol( 'onDidReceiveNotificationResponse' ) ]
            as DidReceiveNotificationResponseCallback?;
        return true;
      } );
    when( () => plugin.getNotificationAppLaunchDetails() )
      .thenAnswer( ( _ ) async => const NotificationAppLaunchDetails( false ) );
  } );

  tearDown( () => router.dispose() );

  NotificationResponse tapOn( String? payload ) => NotificationResponse(
    notificationResponseType : NotificationResponseType.selectedNotification,
    id                       : 1,
    payload                  : payload,
  );

  group( "bindNotificationTaps — the warm callback", () {
    test( "installs a tap callback, and a tap on it reaches the router", () async {
      await bindNotificationTaps( plugin: plugin, router: router );

      expect( installedCallback, isNotNull,
          reason: "without this, a tap while the app is alive goes nowhere — the "
                  "pre-fix behaviour" );

      installedCallback!( tapOn( const NotificationTapPayload(
        notificationId : "n-55", senderId: "who#5" ).encode() ) );

      expect( router.takePending()?.notificationId, "n-55" );
    } );

    test( "a tap carrying the plugin's default empty payload is ignored", () async {
      // `show()` sends `'payload': payload ?? ''`, so every notification posted
      // by a build predating this row arrives here as "".
      await bindNotificationTaps( plugin: plugin, router: router );

      installedCallback!( tapOn( "" ) );

      expect( router.hasPending, isFalse );
    } );

    test( "a tap carrying garbage is ignored rather than thrown", () async {
      await bindNotificationTaps( plugin: plugin, router: router );

      expect( () => installedCallback!( tapOn( "{not json" ) ), returnsNormally );
      expect( router.hasPending, isFalse );
    } );
  } );

  group( "bindNotificationTaps — the cold start", () {
    test( "a launch-by-notification offers its payload BEFORE returning", () async {
      // The case Rick reported: app swiped away, notification tapped. The warm
      // callback never fires for this, so the launch intent is the only source.
      when( () => plugin.getNotificationAppLaunchDetails() ).thenAnswer(
        ( _ ) async => NotificationAppLaunchDetails( true,
            notificationResponse: tapOn( const NotificationTapPayload(
              notificationId : "n-cold", senderId: "who#cold" ).encode() ) ) );

      await bindNotificationTaps( plugin: plugin, router: router );

      expect( router.hasPending, isTrue,
          reason: "main() awaits this before runApp, so the tap must already be "
                  "held by the time the first frame builds" );
      final tap = router.takePending();
      expect( tap?.notificationId, "n-cold" );
      expect( tap?.senderId, "who#cold" );
    } );

    test( "an ORDINARY launch offers nothing", () async {
      when( () => plugin.getNotificationAppLaunchDetails() )
        .thenAnswer( ( _ ) async => const NotificationAppLaunchDetails( false ) );

      await bindNotificationTaps( plugin: plugin, router: router );

      expect( router.hasPending, isFalse,
          reason: "opening the app from its icon must not jump anywhere" );
    } );

    test( "a launch-by-notification with no payload offers nothing", () async {
      when( () => plugin.getNotificationAppLaunchDetails() ).thenAnswer(
        ( _ ) async => NotificationAppLaunchDetails( true,
            notificationResponse: tapOn( null ) ) );

      await bindNotificationTaps( plugin: plugin, router: router );

      expect( router.hasPending, isFalse );
    } );

    test( "null launch details are tolerated", () async {
      when( () => plugin.getNotificationAppLaunchDetails() )
        .thenAnswer( ( _ ) async => null );

      final details = await bindNotificationTaps( plugin: plugin, router: router );

      expect( details, isNull );
      expect( router.hasPending, isFalse );
    } );
  } );

  group( "bindNotificationTaps — never takes down main()", () {
    test( "an initialize() that throws is swallowed and reported as null", () async {
      when( () => plugin.initialize( any(),
          onDidReceiveNotificationResponse:
              any( named: 'onDidReceiveNotificationResponse' ) ) )
        .thenThrow( Exception( 'no platform channel' ) );

      // 🔴 `main()` awaits this on the line before `runApp`. A throw here would
      // be an app that will not start, which is far worse than a tap that only
      // opens the app.
      expect( await bindNotificationTaps( plugin: plugin, router: router ), isNull );
    } );

    test( "a getNotificationAppLaunchDetails() that throws is swallowed", () async {
      when( () => plugin.getNotificationAppLaunchDetails() )
        .thenThrow( Exception( 'channel not ready' ) );

      expect( await bindNotificationTaps( plugin: plugin, router: router ), isNull );
    } );
  } );

  group( "the plugin-singleton hazard (the regression this row nearly shipped)", () {
    late NotificationPreferences prefs;

    setUp( () async {
      SharedPreferences.setMockInitialValues( {} );
      prefs = NotificationPreferences( await SharedPreferences.getInstance() );
      when( () => plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>() ).thenReturn( null );
    } );

    test( "NotificationAudioService.initialize() PRESERVES the tap callback", () async {
      // 🔴 THE BUG THIS PINS. `FlutterLocalNotificationsPlugin()` is a singleton
      // (`factory … => _instance`) and `initialize()` assigns the tap handler
      // unconditionally — so a later call that omits it sets the handler to NULL.
      // This service initializes LAZILY, on the first ding. A bare call here
      // would therefore have made taps work from launch until the first
      // notification arrived and then stop: intermittent, ordering-dependent,
      // and invisible to every cold-start test above.
      final service = NotificationAudioService(
        prefs             : prefs,
        plugin            : plugin,
        tts               : _MockTts(),
        onNotificationTap : notificationTapSink( router ),
      );

      await service.initialize();

      expect( installedCallback, isNotNull,
          reason: "the audio service must install the SAME tap callback, not null" );

      // And it is a WORKING one, not merely non-null.
      installedCallback!( tapOn( const NotificationTapPayload(
        notificationId : "n-ding", senderId: "who#d" ).encode() ) );
      expect( router.takePending()?.notificationId, "n-ding" );
    } );

    test( "NEGATIVE CONTROL: constructed without a callback, it installs null", () async {
      // Proof the assertion above can fail — i.e. that it is testing the
      // injection and not something that is true either way.
      final service = NotificationAudioService(
        prefs : prefs, plugin: plugin, tts: _MockTts() );

      await service.initialize();

      expect( installedCallback, isNull );
      expect( service.hasTapCallback, isFalse );
    } );
  } );
}
