/// AC-S3.8 / testing-strategy §Cross-Section item 2 — S2+S1 WIRING test:
/// REAL FocusChatBloc driving a REAL TtsOrchestrator (mock player tier).
/// Paused inbound accumulates the TTS queue AND increments unread; resume
/// drains in arrival order.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_bloc.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_event.dart';
import 'package:lupin_mobile/features/notifications/data/notification_models.dart';
import 'package:lupin_mobile/features/notifications/data/notification_repository.dart';
import 'package:lupin_mobile/services/notification_audio/notification_audio_service.dart';
import 'package:lupin_mobile/services/notification_audio/notification_preferences.dart';
import 'package:lupin_mobile/services/tts/streaming_tts_player.dart';
import 'package:lupin_mobile/services/tts/tts_orchestrator.dart';
import 'package:lupin_mobile/services/websocket/websocket_service.dart';

class _MockPlayer   extends Mock implements StreamingTtsPlayer {}
class _MockFallback extends Mock implements NotificationAudioService {}
class _MockWs       extends Mock implements WebSocketService {}
class _MockRepo     extends Mock implements NotificationRepository {}

NotificationItem _item( String id, String sender, { String priority = 'low' } ) {
  return NotificationItem(
    id                     : id,
    message                : 'msg-$id',
    type                   : 'task',
    priority               : priority,
    senderId               : sender,
    timestamp              : DateTime( 2026, 6, 12, 1 ),
    played                 : false,
    playCount              : 0,
    responseRequested      : false,
    suppressDing           : false,
    displayQualifierWidget : false,
  );
}

void main() {
  test( 'Cross-Section checkpoint 2 — paused inbound accumulates TTS queue + increments unread; resume drains in order', () async {
    SharedPreferences.setMockInitialValues( {} );
    final sp       = await SharedPreferences.getInstance();
    final player   = _MockPlayer();
    final fallback = _MockFallback();
    final ws       = _MockWs();
    final spoken   = <String>[];
    final completeCtrl = StreamController<TtsCompleteEvent>.broadcast();
    final errorCtrl    = StreamController<TtsErrorEvent>.broadcast();

    when( () => player.completeStream ).thenAnswer( ( _ ) => completeCtrl.stream );
    when( () => player.errorStream    ).thenAnswer( ( _ ) => errorCtrl.stream );
    when( () => player.isPlaying      ).thenReturn( false );
    when( () => player.stop()         ).thenAnswer( ( _ ) async {} );
    when( () => player.speak(
      text      : any( named: 'text' ),
      sessionId : any( named: 'sessionId' ),
      voiceId   : any( named: 'voiceId' ),
    ) ).thenAnswer( ( inv ) async {
      spoken.add( inv.namedArguments[ #text ] as String );
    } );
    when( () => fallback.flutterTtsSpeak( any() ) ).thenAnswer( ( _ ) async {} );
    when( () => fallback.stopFallbackSpeech()     ).thenAnswer( ( _ ) async {} );
    when( () => ws.sessionId ).thenReturn( 'wise penguin' );

    final orch = TtsOrchestrator(
      player   : player,
      fallback : fallback,
      prefs    : NotificationPreferences( sp ),
      ws       : ws,
    );
    final bloc = FocusChatBloc( _MockRepo(), tts: orch );

    Future<void> pump() => Future<void>.delayed( const Duration( milliseconds: 10 ) );

    // HOLD, then two inbounds (different senders, no focus).
    orch.pause();
    bloc.add( FocusInboundNotification( _item( '1', 'A' ) ) );
    bloc.add( FocusInboundNotification( _item( '2', 'B' ) ) );
    await pump();

    expect( orch.queueDepth, 2, reason: 'paused inbound ACCUMULATES (Q6 hold, not mute)' );
    expect( spoken, isEmpty );
    expect( bloc.state.unreadBySender[ 'A' ], 1 );
    expect( bloc.state.unreadBySender[ 'B' ], 1 );
    expect( bloc.state.senderOrder, [ 'A', 'B' ] );

    // RESUME → drains in arrival order through the real S1 machinery.
    orch.resume();
    await pump();
    completeCtrl.add( const TtsCompleteEvent() );
    await pump();
    completeCtrl.add( const TtsCompleteEvent() );
    await pump();

    expect( spoken, [ 'msg-1', 'msg-2' ] );
    expect( orch.queueDepth, 0 );

    await bloc.close();
    await orch.dispose();
    await completeCtrl.close();
    await errorCtrl.close();
  } );
}
