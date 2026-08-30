/// AC-S3.1 — ONE inbound frame produces EXACTLY ONE `enqueueAlways`, with both
/// `FocusChatBloc` and `QuickAskBloc` live on the REAL `app.dart` dispatch.
///
/// 🔴 WHY THIS FILE EXISTS. Before it, AC-S3.1 was TRUE BY ACCIDENT: the only
/// occurrence of that id anywhere in `test/` was an unrelated criterion from
/// the June focus-mode plan that happens to share the number, so an
/// AC-coverage grep reported it COVERED. The claim held only because
/// `QuickAskBloc` happens not to reference `TtsOrchestrator` at all — nothing
/// asserted that, and giving that bloc a speech dependency would have
/// reintroduced double-dispatch with no test going red.
///
/// `focus_app_wiring_test.dart` cannot cover this and says so in its own
/// header: it registers a MOCK `QuickAskBloc` deliberately, to keep its
/// dispatch pin independent of Quick Ask's constructor. A mock cannot speak,
/// so the very thing AC-S3.1 forbids is impossible there by construction.
/// **This file registers the REAL bloc, which is the whole point.**
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';

import 'dart:io';

import 'package:lupin_mobile/app.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_bloc.dart';
import 'package:lupin_mobile/features/notifications/data/notification_repository.dart';
import 'package:lupin_mobile/features/notifications/domain/notification_bloc.dart';
import 'package:lupin_mobile/features/queue/data/queue_repository.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_bloc.dart';
import 'package:lupin_mobile/services/asr/asr_service.dart';
import 'package:lupin_mobile/services/notification_audio/notification_audio_service.dart';
import 'package:lupin_mobile/services/tts/tts_orchestrator.dart';
import 'package:lupin_mobile/services/websocket/websocket_service.dart';

class _MockNotifRepo extends Mock implements NotificationRepository {}
class _MockQueueRepo extends Mock implements QueueRepository {}
class _MockAudio     extends Mock implements NotificationAudioService {}
class _MockTts       extends Mock implements TtsOrchestrator {}
class _MockAsr       extends Mock implements AsrService {}
class _MockWs        extends Mock implements WebSocketService {}

Map<String, dynamic> _queueUpdateFrame() => {
  'type'         : 'notification_queue_update',
  'notification' : {
    'id'                       : 'n-1',
    'message'                  : 'The answer is sunny.',
    'type'                     : 'task',
    'priority'                 : 'high',
    'timestamp'                : '2026-08-29T20:00:00',
    'played'                   : false,
    'play_count'               : 0,
    'response_requested'       : false,
    'suppress_ding'            : false,
    'sender_id'                : 'peer@lupin.deepily.ai',
    'display_qualifier_widget' : false,
  },
};

void main() {
  setUpAll( () { registerFallbackValue( const TtsSender() ); } );

  group( 'AC-S3.1 — the single-dispatcher pin, with the REAL QuickAskBloc', () {
    late _MockTts       tts;
    late FocusChatBloc  focusBloc;
    late QuickAskBloc   quickAsk;
    late WsBlocDispatcher dispatcher;

    setUp( () {
      final notifRepo = _MockNotifRepo();
      final queueRepo = _MockQueueRepo();
      final audio     = _MockAudio();
      final ws        = _MockWs();
      tts = _MockTts();

      when( () => audio.handleIncoming(
        priority     : any( named: 'priority' ),
        message      : any( named: 'message' ),
        title        : any( named: 'title' ),
        suppressDing : any( named: 'suppressDing' ),
      ) ).thenAnswer( ( _ ) async {} );
      when( () => ws.sessionId ).thenReturn( 'wise penguin' );
      // AC-S1.8: the bloc subscribes at construction, so the stream must exist.
      when( () => ws.connectionStream )
          .thenAnswer( ( _ ) => const Stream<bool>.empty() );

      // Production-parity construction, mirroring `service_locator.dart`:
      // the legacy bloc gets audio but NO tts (the F-S2-1 DI withdrawal), and
      // speech ownership sits with FocusChatBloc alone. The REAL QuickAskBloc
      // is what makes this test able to fail.
      GetIt.instance.registerSingleton<NotificationBloc>(
          NotificationBloc( notifRepo, audio: audio ) );
      focusBloc = FocusChatBloc( notifRepo, tts: tts );
      GetIt.instance.registerSingleton<FocusChatBloc>( focusBloc );
      quickAsk = QuickAskBloc( queueRepo, asr: _MockAsr(), ws: ws, notifications: notifRepo );
      GetIt.instance.registerSingleton<QuickAskBloc>( quickAsk );

      dispatcher = WsBlocDispatcher();
    } );

    tearDown( () async {
      await quickAsk.close();
      await focusBloc.close();
      await GetIt.instance.reset();
    } );

    test( 'ONE notification frame fans out to three blocs and yields ONE enqueue', () async {
      dispatcher.dispatch( 'notification_queue_update', _queueUpdateFrame() );
      await Future<void>.delayed( const Duration( milliseconds: 50 ) );

      verify( () => tts.enqueueAlways(
        priority : any( named: 'priority' ),
        message  : any( named: 'message' ),
        title    : any( named: 'title' ),
        voiceId  : any( named: 'voiceId' ),
        sender   : any( named: 'sender' ),
        verbatim : any( named: 'verbatim' ),
      ) ).called( 1 );
    } );

    test( 'a COMPLETED transition frame produces NO enqueue at all', () async {
      // The AC's own words: "No enqueueAlways occurs on a `completed` frame
      // from the Quick Ask path." That frame is routed to QuickAskBloc ALONE
      // (`app.dart`, eventJobStateTransition), so any speech from it would be
      // a second dispatcher appearing.
      dispatcher.dispatch( 'job_state_transition', {
        'type'       : 'job_state_transition',
        'job_id'     : 'j-1',
        'from_state' : 'running',
        'to_state'   : 'completed',
        'timestamp'  : '2026-08-29T20:00:00',
        'metadata'   : { 'question_text': 'q', 'response_text': 'It is sunny.' },
      } );
      await Future<void>.delayed( const Duration( milliseconds: 50 ) );

      verifyNever( () => tts.enqueueAlways(
        priority : any( named: 'priority' ),
        message  : any( named: 'message' ),
        title    : any( named: 'title' ),
        voiceId  : any( named: 'voiceId' ),
        sender   : any( named: 'sender' ),
        verbatim : any( named: 'verbatim' ),
      ) );
      verifyNever( () => tts.replay(
        message : any( named: 'message' ),
        title   : any( named: 'title' ),
        voiceId : any( named: 'voiceId' ),
        sender  : any( named: 'sender' ),
      ) );
    } );

    test( '🔴 STRUCTURAL: QuickAskBloc holds no speech dependency at all', () {
      // The behavioural tests above can only catch a second dispatch on the
      // frames they happen to drive. This one catches the CAPABILITY, which is
      // what the by-construction argument actually rests on: give this bloc a
      // TtsOrchestrator and this goes red on the import, before anyone has to
      // guess which frame would expose it.
      const path = 'lib/features/quick_ask/domain/quick_ask_bloc.dart';
      final raw  = File( path ).readAsStringSync();
      // Comments are stripped: this very file's rationale would otherwise be
      // matched by a scan looking for the words it is about.
      final code = raw
          .replaceAll( RegExp( r'/\*.*?\*/', dotAll: true ), '' )
          .split( '\n' )
          .map( ( l ) { final i = l.indexOf( '//' ); return i == -1 ? l : l.substring( 0, i ); } )
          .join( '\n' );

      expect( code.contains( 'tts_orchestrator' ), isFalse,
          reason: 'speech ownership is FocusChatBloc\'s alone — importing the '
                  'orchestrator here is how AC-S3.1 would silently stop holding' );
      for ( final name in [ 'TtsOrchestrator', 'enqueueAlways', 'enqueueIfSpeakable' ] ) {
        expect( code.contains( name ), isFalse, reason: '$name must not appear in $path' );
      }
    } );
  } );
}
