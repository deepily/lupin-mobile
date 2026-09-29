/// Row d9bc6f6c — the DI seam, not the logic.
///
/// 🔴 THE SHAPE OF BUG 9adff476, WAITING TO HAPPEN AGAIN. Every other test in
/// this row supplies the tap callback itself, and a test that hands in the
/// dependency it exercises cannot fail on that dependency being absent from
/// production. This file asserts the one thing they structurally cannot: that
/// `ServiceLocator` actually injects it.
///
/// AND HERE THAT IS WORSE THAN A MISSING FEATURE. `FlutterLocalNotificationsPlugin`
/// is a singleton and `initialize()` installs the tap handler by assignment, so a
/// NotificationAudioService built without the callback CLEARS the handler `main()`
/// installed — on its first lazy init, which is the first ding. Taps would work
/// from launch until a notification arrived and then silently stop.
///
/// Remove `onNotificationTap` from `ServiceLocator.buildNotificationAudioService`
/// and this file goes red while every other tap test stays green.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lupin_mobile/core/di/service_locator.dart';
import 'package:lupin_mobile/services/notification_audio/notification_audio_service.dart';
import 'package:lupin_mobile/services/notification_audio/notification_preferences.dart';
import 'package:lupin_mobile/services/push/notification_tap_router.dart';

void main() {
  // `NotificationAudioService`'s default constructor builds a `FlutterTts`, which
  // sets a method-call handler and therefore needs a binary messenger. Production
  // has one; a bare `dart test` does not.
  TestWidgetsFlutterBinding.ensureInitialized();

  final getIt = GetIt.instance;

  group( 'DI wiring — the notification tap callback', () {
    setUp( () async {
      SharedPreferences.setMockInitialValues( {} );
      getIt
        ..registerSingleton<NotificationPreferences>(
            NotificationPreferences( await SharedPreferences.getInstance() ) )
        ..registerSingleton<NotificationTapRouter>( NotificationTapRouter() );
    } );

    tearDown( () async {
      await getIt<NotificationTapRouter>().dispose();
      await getIt.reset();
    } );

    test( 'PRODUCTION builds the audio service WITH a tap callback', () {
      expect( ServiceLocator.buildNotificationAudioService().hasTapCallback, isTrue );
    } );

    test( 'NEGATIVE CONTROL: the same class built without one reports false', () {
      // Proof the probe above reads the injection and is not true either way.
      expect(
        NotificationAudioService(
            prefs: getIt<NotificationPreferences>() ).hasTapCallback,
        isFalse );
    } );
  } );
}
