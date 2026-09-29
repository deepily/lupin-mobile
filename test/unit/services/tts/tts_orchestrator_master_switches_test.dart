import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lupin_mobile/services/notification_audio/notification_audio_service.dart';
import 'package:lupin_mobile/services/notification_audio/notification_preferences.dart';
import 'package:lupin_mobile/services/notification_filter/notification_stop_list.dart';
import 'package:lupin_mobile/services/tts/streaming_tts_player.dart';
import 'package:lupin_mobile/services/tts/tts_orchestrator.dart';
import 'package:lupin_mobile/services/websocket/websocket_service.dart';

class _MockPlayer   extends Mock implements StreamingTtsPlayer {}
class _MockFallback extends Mock implements NotificationAudioService {}
class _MockWs       extends Mock implements WebSocketService {}

/// Row ea716d77 (Rick 2026-09-29, "off means off"): the Focus path
/// (`enqueueAlways`) honors Notifications, Master mute, sender mute and quiet
/// hours, with the same urgent bypasses as `NotificationDeliveryPolicy`.
void main() {
  late _MockPlayer   player;
  late _MockFallback fallback;
  late _MockWs       ws;
  late NotificationPreferences prefs;
  late StreamController<TtsCompleteEvent> completeCtrl;
  late StreamController<TtsErrorEvent>    errorCtrl;
  late TtsOrchestrator orch;
  int speaks = 0;

  const key = "persona:maya";

  setUp( () async {
    SharedPreferences.setMockInitialValues( {} );
    prefs        = NotificationPreferences( await SharedPreferences.getInstance() );
    player       = _MockPlayer();
    fallback     = _MockFallback();
    ws           = _MockWs();
    completeCtrl = StreamController<TtsCompleteEvent>.broadcast();
    errorCtrl    = StreamController<TtsErrorEvent>   .broadcast();
    when( () => player.completeStream ).thenAnswer( ( _ ) => completeCtrl.stream );
    when( () => player.errorStream    ).thenAnswer( ( _ ) => errorCtrl   .stream );
    when( () => player.isPlaying      ).thenReturn( false );
    speaks = 0;
    when( () => player.speak(
      text      : any( named: "text"      ),
      sessionId : any( named: "sessionId" ),
      voiceId   : any( named: "voiceId"   ),
    ) ).thenAnswer( ( _ ) async { speaks++; } );
    when( () => player.stop() ).thenAnswer( ( _ ) async {} );
    when( () => fallback.flutterTtsSpeak( any() ) ).thenAnswer( ( _ ) async {} );
    when( () => fallback.stopFallbackSpeech()     ).thenAnswer( ( _ ) async {} );
    when( () => ws.sessionId ).thenReturn( "wise penguin" );
    orch = TtsOrchestrator( player: player, fallback: fallback, prefs: prefs, ws: ws );
  } );

  tearDown( () async {
    await orch.dispose();
    await completeCtrl.close();
    await errorCtrl   .close();
  } );

  Future<bool> spoke( String priority, { bool verbatim = false } ) async {
    speaks = 0;
    orch.enqueueAlways( priority: priority, message: "hello", verbatim: verbatim, senderKey: key );
    await Future<void>.delayed( Duration.zero );
    final calls = speaks;
    orch.stopAll();
    return calls > 0;
  }

  Future<void> quietNow() async {
    final m = DateTime.now().hour * 60 + DateTime.now().minute;
    await prefs.setQuietEnabled( true );
    await prefs.setQuietStartMinutes( m - 30 + 24 * 60 );
    await prefs.setQuietEndMinutes( m + 30 );
  }

  group( "Focus path master switches", () {
    test( "negative control: everything on — speaks", () async {
      expect( await spoke( "medium" ), isTrue );
    } );

    test( "Notifications off — silent, even verbatim and urgent", () async {
      await prefs.setEnabled( false );
      expect( await spoke( "medium" ), isFalse );
      expect( await spoke( "urgent" ), isFalse );
      expect( await spoke( "medium", verbatim: true ), isFalse );
    } );

    test( "Master mute on — silent, even verbatim and urgent", () async {
      await prefs.setMasterMute( true );
      expect( await spoke( "medium" ), isFalse );
      expect( await spoke( "urgent" ), isFalse );
      expect( await spoke( "medium", verbatim: true ), isFalse );
    } );

    test( "muted sender — silent; urgent bypass on speaks, off is silent", () async {
      await prefs.muteSender( key, "Maya" );
      expect( await spoke( "medium" ), isFalse );
      expect( await spoke( "urgent" ), isTrue, reason: "muteUrgentBypass defaults on" );
      await prefs.setMuteUrgentBypass( false );
      expect( await spoke( "urgent" ), isFalse );
    } );

    test( "another sender is not muted", () async {
      await prefs.muteSender( "persona:someone-else", "Else" );
      expect( await spoke( "medium" ), isTrue );
    } );

    test( "quiet hours — silent; urgent bypass on speaks, off is silent", () async {
      await quietNow();
      expect( await spoke( "medium" ), isFalse );
      expect( await spoke( "urgent" ), isTrue, reason: "quietUrgentBypass defaults on" );
      await prefs.setQuietUrgentBypass( false );
      expect( await spoke( "urgent" ), isFalse );
    } );

    test( "Notifications off also silences a stop-list item and its speak-anyway", () async {
      final stops = NotificationStopList( await SharedPreferences.getInstance() );
      await stops.add( "hello" );
      final o2 = TtsOrchestrator( player: player, fallback: fallback, prefs: prefs, ws: ws, stopList: stops );
      final sup = o2.enqueueAlways( priority: "medium", message: "hello", senderKey: key );
      expect( sup, isNotNull, reason: "master on: stop-list still reports" );
      await prefs.setEnabled( false );
      o2.speakAnyway( sup! );
      await Future<void>.delayed( Duration.zero );
      expect( speaks, 0 );
      await prefs.setEnabled( true );
      speaks = 0;
      o2.speakAnyway( sup );
      await Future<void>.delayed( Duration.zero );
      expect( speaks, 1, reason: "master back on: speak-anyway speaks again" );
      await prefs.setEnabled( false );
      expect( o2.enqueueAlways( priority: "medium", message: "hello", senderKey: key ), isNull,
          reason: "master off: nothing to offer back" );
      await o2.dispose();
    } );
  } );
}
