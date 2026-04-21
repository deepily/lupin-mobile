import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lupin_mobile/services/notification_audio/notification_audio_service.dart';
import 'package:lupin_mobile/services/notification_audio/notification_preferences.dart';

class _MockFln extends Mock implements FlutterLocalNotificationsPlugin {}
class _MockTts extends Mock implements FlutterTts {}

class _FakeInitSettings extends Fake implements InitializationSettings {}
class _FakeNotifDetails extends Fake implements NotificationDetails {}

void main() {
  setUpAll( () {
    registerFallbackValue( _FakeInitSettings() );
    registerFallbackValue( _FakeNotifDetails() );
  } );

  group( "NotificationAudioService", () {
    late _MockFln fln;
    late _MockTts tts;
    late NotificationPreferences prefs;

    setUp( () async {
      SharedPreferences.setMockInitialValues( {} );
      final sp = await SharedPreferences.getInstance();
      prefs = NotificationPreferences( sp );
      fln   = _MockFln();
      tts   = _MockTts();
      // Defaults so nothing fails unexpectedly; initialize() is idempotent.
      when( () => fln.initialize( any() ) ).thenAnswer( ( _ ) async => true );
      when( () => fln.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>() ).thenReturn( null );
      when( () => fln.show( any(), any(), any(), any() ) ).thenAnswer( ( _ ) async {} );
      when( () => tts.stop() ).thenAnswer( ( _ ) async => 1 );
      when( () => tts.speak( any() ) ).thenAnswer( ( _ ) async => 1 );
    } );

    NotificationAudioService newService() => NotificationAudioService(
      prefs  : prefs,
      plugin : fln,
      tts    : tts,
    );

    Future<void> send(
      NotificationAudioService s, {
      required String priority,
      bool  suppressDing = false,
      String? title = "Job done",
      String  message = "The thing finished.",
    } ) async {
      await s.handleIncoming(
        priority     : priority,
        message      : message,
        title        : title,
        suppressDing : suppressDing,
      );
      // Let the 300ms-delayed speech microtask drain.
      await Future<void>.delayed( const Duration( milliseconds: 350 ) );
    }

    test( "low priority: neither ding nor speak", () async {
      await send( newService(), priority: "low" );
      verifyNever( () => fln.show( any(), any(), any(), any() ) );
      verifyNever( () => tts.speak( any() ) );
    } );

    test( "medium: ding only (no speech)", () async {
      await send( newService(), priority: "medium" );
      verify( () => fln.show( any(), any(), any(), any() ) ).called( 1 );
      verifyNever( () => tts.speak( any() ) );
    } );

    test( "high: ding + speak title+message", () async {
      await send( newService(), priority: "high", title: "Alert", message: "Tests failing." );
      verify( () => fln.show( any(), any(), any(), any() ) ).called( 1 );
      verify( () => tts.speak( "Alert. Tests failing." ) ).called( 1 );
    } );

    test( "urgent: ding + speak", () async {
      await send( newService(), priority: "urgent", title: "CRIT", message: "Prod down." );
      verify( () => fln.show( any(), any(), any(), any() ) ).called( 1 );
      verify( () => tts.speak( "CRIT. Prod down." ) ).called( 1 );
    } );

    test( "suppress_ding silences ding but NOT speech (mirrors web client)", () async {
      await send( newService(), priority: "high", suppressDing: true );
      verifyNever( () => fln.show( any(), any(), any(), any() ) );
      verify( () => tts.speak( any() ) ).called( 1 );
    } );

    test( "master mute silences everything regardless of priority", () async {
      await prefs.setMasterMute( true );
      await send( newService(), priority: "urgent" );
      verifyNever( () => fln.show( any(), any(), any(), any() ) );
      verifyNever( () => tts.speak( any() ) );
    } );

    test( "dingOnHigh=false skips ding but speech still fires on high", () async {
      await prefs.setDingOnHigh( false );
      await send( newService(), priority: "high" );
      verifyNever( () => fln.show( any(), any(), any(), any() ) );
      verify( () => tts.speak( any() ) ).called( 1 );
    } );

    test( "speakOnUrgent=false → urgent dings but does not speak", () async {
      await prefs.setSpeakOnUrgent( false );
      await send( newService(), priority: "urgent" );
      verify( () => fln.show( any(), any(), any(), any() ) ).called( 1 );
      verifyNever( () => tts.speak( any() ) );
    } );

    test( "speech without title falls back to message only", () async {
      await send( newService(), priority: "high", title: null, message: "No-title body" );
      verify( () => tts.speak( "No-title body" ) ).called( 1 );
    } );
  } );
}
