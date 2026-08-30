/// AC-S2.8 + AC-S2.10 (app-level half) — service-integration tests driving
/// the REAL `app.dart` dispatch wiring (`WsBlocDispatcher`) with production
/// bloc construction parity: the legacy NotificationBloc is built WITHOUT a
/// `tts` dependency (the F-S2-1 DI withdrawal, mirrored from
/// `service_locator.dart`), FocusChatBloc with the shared mock orchestrator.
library;

import 'package:bloc_test/bloc_test.dart';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/app.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_bloc.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_event.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_state.dart';
import 'package:lupin_mobile/features/notifications/data/ask_resolution.dart';
import 'package:lupin_mobile/features/notifications/data/notification_models.dart';
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

    // ── AC-S4.3 — the ask LIFECYCLE frames, through the REAL dispatcher ──
    //
    // Both names appeared ZERO times in `lib/` before this: the frames
    // arrived and were dropped on the floor. An expired ask therefore
    // stayed "pending" forever and poisoned `pendingPromptFor`, so the
    // composer aimed every voice reply at a dead ask and took a 400 the
    // user never saw.
    //
    // Payload keys sit at the TOP level of the frame — verified against the
    // emit sites, `notifications.py:1442` and `:1636` — NOT nested under
    // `notification` the way `notification_queue_update` nests them. A case
    // that reads `data['notification']` here finds nothing and drops the
    // frame just as silently as having no case at all.

    NotificationItem askItem( String id ) => NotificationItem(
      id                     : id,
      message                : 'Proceed?',
      type                   : 'task',
      priority               : 'medium',
      senderId               : 'sender-1',
      timestamp              : DateTime( 2026, 8, 29, 20 ),
      played                 : false,
      playCount              : 0,
      responseRequested      : true,
      responseType           : 'yes_no',
      suppressDing           : false,
      displayQualifierWidget : false,
    );

    Future<FocusMessage> deliverThen( Map<String, dynamic> frame ) async {
      focusBloc.add( FocusInboundNotification( askItem( 'n-live' ) ) );
      await Future<void>.delayed( Duration.zero );
      dispatcher.dispatch( frame[ 'type' ] as String, frame );
      await Future<void>.delayed( Duration.zero );
      return focusBloc.state.windows[ 'sender-1' ]!
          .firstWhere( ( m ) => m.item.id == 'n-live' );
    }

    test( 'AC-S4.3 — notification_expired marks the ask dead and surfaces '
          'the default the server used', () async {
      final msg = await deliverThen( {
        'type'            : 'notification_expired',
        'notification_id' : 'n-live',
        'default_used'    : 'no',
        'timeout'         : true,
      } );

      expect( msg.answered, isTrue, reason: 'an expired ask is FINISHED' );
      expect( msg.resolution, AskResolution.expired );
      expect( msg.resolutionDetail, 'no',
              reason: '"expired" alone is thin — the user should see what the '
                      'server answered on their behalf' );
      expect( focusBloc.state.pendingPromptFor( 'sender-1' ), isNull );
    } );

    test( 'AC-S4.3 — notification_responded retires the ask as answered '
          'ELSEWHERE, which is not an error and not our answer', () async {
      final msg = await deliverThen( {
        'type'            : 'notification_responded',
        'notification_id' : 'n-live',
        'response_value'  : 'yes',
      } );

      expect( msg.answered, isTrue );
      expect( msg.resolution, AskResolution.answeredElsewhere );
      expect( msg.resolutionDetail, 'yes' );
      expect( focusBloc.state.hydration, isNot( FocusHydration.error ) );
    } );

    // ── The shared stop-list, pinned so it stays deliberate ─────────────
    test( 'the orchestrator and FocusChatBloc resolve the SAME '
          'NotificationStopList instance in production DI', () {
      // Load-bearing since the suppressed-question path stopped returning
      // early: the bloc now CALLS `enqueueAlways` and relies on the
      // orchestrator's gate 1 to mute it. If the two ever hold different
      // stop lists — or the orchestrator holds none — a question the user
      // muted starts talking, and every existing test still passes because
      // each half is individually correct.
      //
      // Asserted against the registration source rather than a running
      // container: both sites must read from the same registered singleton.
      final di = File( 'lib/core/di/service_locator.dart' ).readAsStringSync();
      final resolvers = RegExp( r'stopList\s*:\s*_getIt<NotificationStopList>\(\)' )
          .allMatches( di ).length;
      expect( resolvers, greaterThanOrEqualTo( 2 ),
              reason: 'the orchestrator and the focus bloc must BOTH take the '
                      'registered stop list; a literal or a null at either '
                      'site un-mutes suppressed questions' );
      expect( di.contains( 'registerLazySingleton<NotificationStopList>' )
           || di.contains( 'registerSingleton<NotificationStopList>' ), isTrue,
              reason: 'one instance, registered once' );
    } );

    test( 'a lifecycle frame for an UNKNOWN id changes nothing — it does not '
          'blank the window or throw', () async {
      final msg = await deliverThen( {
        'type'            : 'notification_expired',
        'notification_id' : 'someone-elses-ask',
        'default_used'    : 'no',
      } );

      expect( msg.answered, isFalse );
      expect( msg.resolution, isNull );
      expect( focusBloc.state.pendingPromptFor( 'sender-1' )?.item.id, 'n-live' );
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
