import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppLifecycleState, VoidCallback;
import 'package:audioplayers/audioplayers.dart';
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
class _MockAudioPlayer extends Mock implements AudioPlayer {}

void main() {
  setUpAll( () {
    registerFallbackValue( AssetSource( 'audio/x.mp3' ) );
    registerFallbackValue( const AudioContext() );
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

    group( "while the app is on screen", () {
      late List<String> played;
      late int          buzzes;
      setUp( () {
        played = [];
        buzzes = 0;
      } );

      NotificationAudioService onScreen( bool shown ) => NotificationAudioService(
        prefs        : prefs,
        plugin       : fln,
        tts          : tts,
        isForeground : () => shown,
        playInApp    : ( channel ) async => played.add( channel ),
        vibrate      : () async => buzzes++,
      );

      for ( final ( priority, channel ) in const [
        ( "medium", "lupin_medium" ), ( "high", "lupin_high" ), ( "urgent", "lupin_urgent" ),
      ] ) {
        test( "$priority dings inside the app and posts nothing to Android", () async {
          await onScreen( true ).handleIncoming( priority: priority, message: "m", suppressDing: false );
          expect( played, [ channel ] );
          expect( buzzes, 1, reason: 'vibrate mode must still get a signal, as the system notification gave' );
          verifyNever( () => fln.show( any(), any(), any(), any(), payload: any( named: 'payload' ) ) );
        } );
      }

      test( "in the background the notification posts to Android as before", () async {
        await onScreen( false ).handleIncoming( priority: "high", message: "m", suppressDing: false );
        expect( played, isEmpty );
        expect( buzzes, 0 );
        verify( () => fln.show( any(), any(), any(), any(), payload: any( named: 'payload' ) ) ).called( 1 );
      } );

      test( "the ding switches, master mute and suppress_ding still silence it", () async {
        await prefs.setDingOnHigh( false );
        await onScreen( true ).handleIncoming( priority: "high", message: "m", suppressDing: false );
        await onScreen( true ).handleIncoming( priority: "urgent", message: "m", suppressDing: true );
        await onScreen( true ).handleIncoming( priority: "low", message: "m", suppressDing: false );
        await prefs.setMasterMute( true );
        await onScreen( true ).handleIncoming( priority: "medium", message: "m", suppressDing: false );
        expect( played, isEmpty );
        expect( buzzes, 0 );
        verifyNever( () => fln.show( any(), any(), any(), any(), payload: any( named: 'payload' ) ) );
      } );

      test( "a ding stops the one still playing first, so two close together don't leave audio focus held", () async {
        final player = _MockAudioPlayer();
        when( () => player.setAudioContext( any() ) ).thenAnswer( ( _ ) async {} );
        when( () => player.stop() ).thenAnswer( ( _ ) async {} );
        when( () => player.play( any() ) ).thenAnswer( ( _ ) async {} );
        final ding = InAppDingPlayer( player: player );

        await ding.play( "lupin_high" );
        await ding.play( "lupin_urgent" );

        final calls = verifyInOrder( [
          () => player.stop(), () => player.play( captureAny() ),
          () => player.stop(), () => player.play( captureAny() ),
        ] );
        final sources = calls.expand( ( c ) => c.captured ).cast<AssetSource>().map( ( a ) => a.path );
        expect( sources, [ "audio/lupin_high.mp3", "audio/lupin_urgent.mp3" ] );
      } );

      test( "each channel's in-app sound is a bundled asset", () {
        for ( final channel in const [ "lupin_medium", "lupin_high", "lupin_urgent" ] ) {
          final asset = InAppDingPlayer.assetFor( channel );
          expect( File( "assets/$asset" ).existsSync(), isTrue, reason: asset );
          expect( File( "assets/$asset" ).readAsBytesSync(),
              File( "android/app/src/main/res/raw/$channel.mp3" ).readAsBytesSync(),
              reason: "the in-app ding must sound like the notification" );
        }
      } );
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

  group( "appIsInForeground", () {
    testWidgets( "on screen when resumed or under the shade, not when hidden or paused", ( tester ) async {
      final b = tester.binding;
      b.handleAppLifecycleStateChanged( AppLifecycleState.resumed );
      expect( appIsInForeground(), isTrue );
      b.handleAppLifecycleStateChanged( AppLifecycleState.inactive );
      expect( appIsInForeground(), isTrue );
      b.handleAppLifecycleStateChanged( AppLifecycleState.hidden );
      expect( appIsInForeground(), isFalse );
      b.handleAppLifecycleStateChanged( AppLifecycleState.paused );
      expect( appIsInForeground(), isFalse );
      b.handleAppLifecycleStateChanged( AppLifecycleState.hidden );
      b.handleAppLifecycleStateChanged( AppLifecycleState.inactive );
      b.handleAppLifecycleStateChanged( AppLifecycleState.resumed );
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

    VoidCallback? completion;

    NotificationAudioService boundedService( { Duration accept = const Duration( milliseconds: 60 ),
                                               Duration done   = const Duration( milliseconds: 120 ) } ) =>
        NotificationAudioService(
          prefs: prefs, plugin: fln, tts: tts, speakAcceptBudget: accept, completionBound: done );

    setUp( () {
      completion = null;
      when( () => tts.setCompletionHandler( any() ) ).thenAnswer( ( inv ) {
        completion = inv.positionalArguments.first as VoidCallback;
      } );
    } );

    // The original id of this test, restored: the AC-G2 gate keys on the exact name. It still asserts the same
    // thing (stop, then speak), now through a speak that returns when the engine reports the utterance finished.
    test( "flutterTtsSpeak calls tts.stop then tts.speak with supplied text", () async {
      final order = <String>[];
      when( () => tts.stop() ).thenAnswer( ( _ ) async { order.add( "stop" ); return 1; } );
      when( () => tts.speak( any() ) ).thenAnswer( ( inv ) async { order.add( "speak:${inv.positionalArguments.first}" ); return 1; } );

      final future = boundedService( done: const Duration( seconds: 5 ) ).flutterTtsSpeak( "hello world" );
      await Future<void>.delayed( const Duration( milliseconds: 20 ) );
      completion!();
      await future;

      expect( order, [ "stop", "speak:hello world" ], reason: "stop first, then speak, once each" );
    } );

    test( "flutterTtsSpeak returns only when the engine reports the utterance finished", () async {
      final service = boundedService( done: const Duration( seconds: 5 ) );
      var finished  = false;
      final future  = service.flutterTtsSpeak( "hello world" ).then( ( _ ) => finished = true );
      await Future<void>.delayed( const Duration( milliseconds: 20 ) );

      verify( () => tts.speak( "hello world" ) ).called( 1 );
      expect( finished, isFalse, reason: "accepted is not finished: the orchestrator must keep its utterance" );

      completion!();
      await future;
      expect( finished, isTrue );
      verifyNever( () => tts.setQueueMode( any() ) );
    } );

    test( "stopFallbackSpeech releases a speak that is waiting, even when the engine fires no cancel callback", () async {
      final service = boundedService( done: const Duration( seconds: 5 ) );
      final future  = service.flutterTtsSpeak( "long" );
      await Future<void>.delayed( const Duration( milliseconds: 20 ) );

      await service.stopFallbackSpeech();
      await future.timeout( const Duration( seconds: 1 ) );   // would hang for 5 s without the release
    } );

    test( "R1: an engine's late cancel callback for a stopped utterance does not release the next one", () async {
      VoidCallback? cancel;
      when( () => tts.setCancelHandler( any() ) ).thenAnswer( ( inv ) {
        cancel = inv.positionalArguments.first as VoidCallback;
      } );
      final service = boundedService( done: const Duration( seconds: 5 ) );

      final first = service.flutterTtsSpeak( "skipped" );
      await Future<void>.delayed( const Duration( milliseconds: 20 ) );
      await service.stopFallbackSpeech();            // the user skipped it
      await first;

      var secondFinished = false;
      final second = service.flutterTtsSpeak( "next one" ).then( ( _ ) => secondFinished = true );
      await Future<void>.delayed( const Duration( milliseconds: 20 ) );

      cancel?.call();                                // the first one's cancel callback finally arrives
      await Future<void>.delayed( const Duration( milliseconds: 20 ) );
      expect( secondFinished, isFalse, reason: "THE BUG: the stale cancel released the utterance that was speaking" );

      completion!();
      await second;
      expect( cancel, isNull, reason: "no cancel handler is registered at all" );
    } );

    test( "an engine that never reports finishing is stopped at the completion bound", () async {
      await boundedService().flutterTtsSpeak( "wedged engine" );
      verify( () => tts.stop() ).called( greaterThanOrEqualTo( 2 ) );   // before the speak, and the bound's own stop
    } );

    test( "an engine that never accepts the text is abandoned at the acceptance budget", () async {
      final never = Completer<dynamic>();
      when( () => tts.speak( any() ) ).thenAnswer( ( _ ) => never.future );
      await boundedService().flutterTtsSpeak( "never accepted" );
      verify( () => tts.stop() ).called( greaterThanOrEqualTo( 2 ) );
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
