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

/// Responsibility split (2026-04-21):
///   - `NotificationAudioService` handles DINGS via Android notification
///     channels. Speech is no longer dispatched from `handleIncoming` —
///     it has moved to `TtsOrchestrator` (ElevenLabs primary, flutter_tts
///     fallback).
///   - This file covers ding behavior + the two new helpers this service
///     exposes for the orchestrator's fallback path:
///       * `flutterTtsSpeak(text)` — explicit fallback call
///       * `stopFallbackSpeech()` — preempt/cancel fallback
void main() {
  setUpAll( () {
    registerFallbackValue( _FakeInitSettings() );
    registerFallbackValue( _FakeNotifDetails() );
  } );

  group( "NotificationAudioService — ding behavior", () {
    late _MockFln fln;
    late _MockTts tts;
    late NotificationPreferences prefs;

    setUp( () async {
      SharedPreferences.setMockInitialValues( {} );
      final sp = await SharedPreferences.getInstance();
      prefs = NotificationPreferences( sp );
      fln   = _MockFln();
      tts   = _MockTts();
      when( () => fln.initialize( any(),
          onDidReceiveNotificationResponse:
              any( named: 'onDidReceiveNotificationResponse' ) ) )
          .thenAnswer( ( _ ) async => true );
      when( () => fln.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>() ).thenReturn( null );
      when( () => fln.show( any(), any(), any(), any(), payload: any( named: 'payload' ) ) ).thenAnswer( ( _ ) async {} );
      when( () => tts.stop() ).thenAnswer( ( _ ) async => 1 );
      when( () => tts.speak( any() ) ).thenAnswer( ( _ ) async => 1 );
      when( () => tts.setQueueMode( any() ) ).thenAnswer( ( _ ) async => 1 );
    } );

    NotificationAudioService newService() => NotificationAudioService(
      prefs  : prefs,
      plugin : fln,
      tts    : tts,
    );

    test( "low priority: no ding", () async {
      await newService().handleIncoming(
        priority: "low", message: "x", suppressDing: false,
      );
      verifyNever( () => fln.show( any(), any(), any(), any(), payload: any( named: 'payload' ) ) );
    } );

    test( "medium: dings", () async {
      await newService().handleIncoming(
        priority: "medium", message: "Routine update", suppressDing: false,
      );
      verify( () => fln.show( any(), any(), any(), any(), payload: any( named: 'payload' ) ) ).called( 1 );
    } );

    test( "high: dings", () async {
      await newService().handleIncoming(
        priority: "high", message: "Needs attention", suppressDing: false,
      );
      verify( () => fln.show( any(), any(), any(), any(), payload: any( named: 'payload' ) ) ).called( 1 );
    } );

    test( "urgent: dings", () async {
      await newService().handleIncoming(
        priority: "urgent", message: "Prod down", suppressDing: false,
      );
      verify( () => fln.show( any(), any(), any(), any(), payload: any( named: 'payload' ) ) ).called( 1 );
    } );

    test( "suppress_ding silences the ding", () async {
      await newService().handleIncoming(
        priority: "urgent", message: "silent emergency", suppressDing: true,
      );
      verifyNever( () => fln.show( any(), any(), any(), any(), payload: any( named: 'payload' ) ) );
    } );

    test( "master mute silences ding regardless of priority", () async {
      await prefs.setMasterMute( true );
      await newService().handleIncoming(
        priority: "urgent", message: "quiet", suppressDing: false,
      );
      verifyNever( () => fln.show( any(), any(), any(), any(), payload: any( named: 'payload' ) ) );
    } );

    test( "dingOnHigh=false → high does not ding", () async {
      await prefs.setDingOnHigh( false );
      await newService().handleIncoming(
        priority: "high", message: "silent high", suppressDing: false,
      );
      verifyNever( () => fln.show( any(), any(), any(), any(), payload: any( named: 'payload' ) ) );
    } );

    test( "handleIncoming never calls tts.speak() directly anymore", () async {
      // Speech dispatch has moved to TtsOrchestrator. Protect against
      // regression: if anyone re-adds a speech branch here, this test
      // catches it.
      await newService().handleIncoming(
        priority: "urgent", title: "CRIT", message: "prod down", suppressDing: false,
      );
      await Future<void>.delayed( const Duration( milliseconds: 350 ) );
      verifyNever( () => tts.speak( any() ) );
    } );
  } );

  group( "NotificationAudioService — fallback helpers", () {
    late _MockFln fln;
    late _MockTts tts;
    late NotificationPreferences prefs;

    setUp( () async {
      SharedPreferences.setMockInitialValues( {} );
      final sp = await SharedPreferences.getInstance();
      prefs = NotificationPreferences( sp );
      fln   = _MockFln();
      tts   = _MockTts();
      when( () => tts.stop() ).thenAnswer( ( _ ) async => 1 );
      when( () => tts.speak( any() ) ).thenAnswer( ( _ ) async => 1 );
    } );

    NotificationAudioService newService() => NotificationAudioService(
      prefs  : prefs,
      plugin : fln,
      tts    : tts,
    );

    test( "flutterTtsSpeak speaks the supplied text and never stops first", () async {
      await newService().flutterTtsSpeak( "hello world" );
      verify( () => tts.speak( "hello world" ) ).called( 1 );
      verifyNever( () => tts.stop() );
    } );

    test( "two utterances in a row are queued, so the second does not cut the first off", () async {
      final service = newService();
      await service.flutterTtsSpeak( "first" );
      await service.flutterTtsSpeak( "second" );

      verify( () => tts.setQueueMode( 1 ) ).called( 1 );
      verifyNever( () => tts.stop() );
      verifyInOrder( [
        () => tts.speak( "first" ),
        () => tts.speak( "second" ),
      ] );
    } );

    test( "an engine that refuses queue mode still speaks", () async {
      when( () => tts.setQueueMode( any() ) ).thenThrow( Exception( "unsupported" ) );
      await newService().flutterTtsSpeak( "still heard" );
      verify( () => tts.speak( "still heard" ) ).called( 1 );
    } );

    test( "flutterTtsSpeak swallows errors from the underlying engine", () async {
      when( () => tts.speak( any() ) ).thenThrow( Exception( "engine unavailable" ) );
      // Must not throw.
      await newService().flutterTtsSpeak( "any text" );
    } );

    test( "stopFallbackSpeech calls tts.stop", () async {
      await newService().stopFallbackSpeech();
      verify( () => tts.stop() ).called( 1 );
    } );
  } );
}
