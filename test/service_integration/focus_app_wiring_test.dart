/// AC-S2.8 + AC-S2.10 (app-level half) — service-integration tests driving
/// the REAL `app.dart` dispatch wiring (`WsBlocDispatcher`) with production
/// bloc construction parity: the legacy NotificationBloc is built WITHOUT a
/// `tts` dependency (the F-S2-1 DI withdrawal, mirrored from
/// `service_locator.dart`), FocusChatBloc with the shared mock orchestrator.
library;

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/app.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_bloc.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_event.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_state.dart';
import 'package:lupin_mobile/features/notifications/data/notification_repository.dart';
import 'package:lupin_mobile/features/notifications/domain/notification_bloc.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_bloc.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_event.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_state.dart';
import 'package:lupin_mobile/services/notification_audio/notification_audio_service.dart';
import 'package:lupin_mobile/services/tts/tts_orchestrator.dart';

class _MockRepo  extends Mock implements NotificationRepository {}
class _MockAudio extends Mock implements NotificationAudioService {}
class _MockTts   extends Mock implements TtsOrchestrator {}

/// The dispatcher reaches for `QuickAskBloc` on the belt channel (S1 §3).
/// Registered as a MOCK, deliberately: this file pins the DISPATCH wiring,
/// not Quick Ask's behavior, and a mock keeps the pin independent of that
/// bloc's constructor as S1 evolves. The plan's instruction is to register
/// it in `setUp` rather than guard the production path with `isRegistered`
/// — a production `if` would make the belt channel silently optional, and
/// nothing would notice if it were never wired at all.
class _MockQuickAsk extends MockBloc<QuickAskEvent, QuickAskState>
    implements QuickAskBloc {}

Map<String, dynamic> _queueUpdateFrame( {
  String priority = 'high',
  String type     = 'task',
} ) {
  return {
    'type'         : 'notification_queue_update',
    'notification' : {
      'id'                 : 'n-1',
      'message'            : 'frame message',
      'type'               : type,
      'priority'           : priority,
      'sender_id'          : 'sender-1',
      'timestamp'          : '2026-06-12T01:00:00',
      'response_requested' : false,
      'suppress_ding'      : false,
    },
  };
}

void main() {
  group( 'WsBlocDispatcher (S2 app wiring)', () {
    late _MockRepo  repo;
    late _MockAudio audio;
    late _MockTts   tts;
    late NotificationBloc legacyBloc;
    late FocusChatBloc    focusBloc;
    late _MockQuickAsk    quickAskBloc;
    late WsBlocDispatcher dispatcher;

    setUp( () {
      repo  = _MockRepo();
      audio = _MockAudio();
      tts   = _MockTts();

      when( () => audio.handleIncoming(
        priority     : any( named: 'priority' ),
        message      : any( named: 'message' ),
        title        : any( named: 'title' ),
        suppressDing : any( named: 'suppressDing' ),
      ) ).thenAnswer( ( _ ) async {} );

      // Production-parity construction (service_locator.dart): legacy bloc
      // gets audio but NO tts (F-S2-1 withdrawal); focus bloc owns speech.
      legacyBloc = NotificationBloc( repo, audio: audio );
      focusBloc  = FocusChatBloc( repo, tts: tts );
      // Persona-less fixtures: widen the rail scope (default Personas-only, §5f).
      focusBloc.add( const FocusSenderScopeChanged( FocusSenderScope.all ) );

      quickAskBloc = _MockQuickAsk();

      GetIt.instance.registerSingleton<NotificationBloc>( legacyBloc );
      GetIt.instance.registerSingleton<FocusChatBloc>( focusBloc );
      GetIt.instance.registerSingleton<QuickAskBloc>( quickAskBloc );

      dispatcher = WsBlocDispatcher();
    } );

    tearDown( () async {
      await GetIt.instance.reset();
    } );

    Future<void> pump() => Future<void>.delayed( const Duration( milliseconds: 20 ) );

    test( 'AC-S2.8 — one notification_queue_update frame → EXACTLY ONE orchestrator enqueue across BOTH blocs', () async {
      dispatcher.dispatch( 'notification_queue_update', _queueUpdateFrame( priority: 'high' ) );
      await pump();

      // FocusChatBloc spoke it once via the ungated path...
      verify( () => tts.enqueueAlways(
        priority : 'high',
        message  : 'frame message',
        title    : any( named: 'title' ),
        voiceId  : any( named: 'voiceId' ),
        sender   : any( named: 'sender' ),
      ) ).called( 1 );
      // ...and the legacy gated path stayed SILENT (tts not injected).
      verifyNever( () => tts.enqueueIfSpeakable(
        priority : any( named: 'priority' ),
        message  : any( named: 'message' ),
        title    : any( named: 'title' ),
        voiceId  : any( named: 'voiceId' ),
        sender   : any( named: 'sender' ),
      ) );
      // Legacy bloc still processed the frame (audio/ding ownership stays).
      verify( () => audio.handleIncoming(
        priority     : any( named: 'priority' ),
        message      : any( named: 'message' ),
        title        : any( named: 'title' ),
        suppressDing : any( named: 'suppressDing' ),
      ) ).called( 1 );
    } );

    test( 'AC-S2.10 (app half) — auth_success frame re-dispatches FocusColdStartRequested with the authenticated email', () async {
      when( () => repo.sendersVisible( any(), hours: any( named: 'hours' ) ) )
          .thenAnswer( ( _ ) async => [] );

      dispatcher.lastAuthenticatedUserId = 'rick@test.com';
      dispatcher.dispatch( 'auth_success', { 'type': 'auth_success' } );
      await pump();

      verify( () => repo.sendersVisible( 'rick@test.com', hours: any( named: 'hours' ) ) ).called( 1 );
    } );

    test( 'auth_success before any authentication → no cold-start dispatch (defensive)', () async {
      dispatcher.dispatch( 'auth_success', { 'type': 'auth_success' } );
      await pump();

      verifyNever( () => repo.sendersVisible( any(), hours: any( named: 'hours' ) ) );
    } );

    test( 'persona frames route to FocusPersonaUpdated, not the inbound path (no TTS enqueue)', () async {
      dispatcher.dispatch( 'notification_queue_update', {
        'type'         : 'notification_queue_update',
        'notification' : {
          'id'            : 'p-1',
          'message'       : 'persona admin frame',
          'type'          : 'voice_persona_assigned',
          'priority'      : 'low',
          'sender_id'     : 'sender-1',
          'timestamp'     : '2026-06-12T01:00:00',
          'voice_persona' : { 'name': 'Tiffany', 'voice_id': 'vx-1' },
        },
      } );
      await pump();

      verifyNever( () => tts.enqueueAlways(
        priority : any( named: 'priority' ),
        message  : any( named: 'message' ),
        title    : any( named: 'title' ),
        voiceId  : any( named: 'voiceId' ),
        sender   : any( named: 'sender' ),
      ) );
      expect( focusBloc.state.personasBySender[ 'sender-1' ], isNotNull );
      expect( focusBloc.state.senderOrder, isEmpty,
          reason: 'admin frames never create rail entries' );
    } );
      test( 'session_reaped frame → FocusSenderExited (immediate hide in Live; no TTS, no rail entry)', () async {
      // establish the sender first so the exit has something to hide
      dispatcher.dispatch( 'notification_queue_update', _queueUpdateFrame() );
      await pump();
      expect( focusBloc.state.visibleOrder, [ 'sender-1' ] );

      dispatcher.dispatch( 'notification_queue_update', {
        'type'         : 'notification_queue_update',
        'notification' : {
          'id'        : 'r-1',
          'message'   : 'worker reaped',
          'type'      : 'session_reaped',
          'priority'  : 'low',
          'sender_id' : 'sender-1',
          'timestamp' : '2026-06-12T01:00:00',
        },
      } );
      await pump();

      expect( focusBloc.state.exitedSenders, { 'sender-1' } );
      expect( focusBloc.state.visibleOrder, isEmpty );
      expect( focusBloc.state.senderOrder, [ 'sender-1' ], reason: 'retained — visibility only' );
    } );
  } );
}
