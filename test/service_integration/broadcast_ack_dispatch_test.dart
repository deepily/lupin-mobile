/// 🔴 THE ACK DISPATCH SEAM — a real socket frame reaching the REAL `BroadcastBloc`
/// through the REAL `app.dart` dispatcher.
///
/// **Why this file exists.** Every existing broadcast test dispatches `BroadcastAckReceived`
/// BY HAND. `broadcast_bloc_test.dart` proves the folding, `broadcast_models_test.dart`
/// proves `BroadcastAck.fromNotification` parses, and `broadcast_pane_test.dart` proves the
/// tally renders. Not one of them touches `app.dart:132-137`, which is the only place a
/// frame off the wire ever becomes that event.
///
/// ⚠️ THAT IS THE SAME DEFECT THIS FEATURE HAS ALREADY BEEN BITTEN BY TWICE. Unit tests on
/// either side of a seam are *structurally incapable* of failing on the seam — they each
/// prove one half while handing in the other. Delete the broadcast arm from `app.dart`
/// entirely and every one of those suites stays green while the pane renders a fleet that
/// looks like it ignored the operator.
///
/// ⇒ This file substitutes nothing above the repository. The dispatcher is real, the bloc
/// is real, the parse is real, and the frame is the shape `commons_ack_watcher.py` actually
/// pushes — `message` empty, everything identifying in `payload`.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/app.dart';
import 'package:lupin_mobile/features/broadcast/data/broadcast_models.dart';
import 'package:lupin_mobile/features/broadcast/data/broadcast_repository.dart';
import 'package:lupin_mobile/features/broadcast/domain/broadcast_bloc.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_bloc.dart';
import 'package:lupin_mobile/features/notifications/data/notification_repository.dart';
import 'package:lupin_mobile/features/notifications/domain/notification_bloc.dart';
import 'package:lupin_mobile/features/queue/data/queue_repository.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_bloc.dart';
import 'package:lupin_mobile/services/asr/asr_service.dart';
import 'package:lupin_mobile/services/notification_audio/notification_audio_service.dart';
import 'package:lupin_mobile/services/quick_ask/quick_ask_preferences.dart';
import 'package:lupin_mobile/services/tts/tts_orchestrator.dart';
import 'package:lupin_mobile/services/websocket/websocket_service.dart';

class _MockNotifRepo     extends Mock implements NotificationRepository {}
class _MockQueueRepo     extends Mock implements QueueRepository {}
class _MockAudio         extends Mock implements NotificationAudioService {}
class _MockTts           extends Mock implements TtsOrchestrator {}
class _MockAsr           extends Mock implements AsrService {}
class _MockWs            extends Mock implements WebSocketService {}
class _MockQaPrefs       extends Mock implements QuickAskPreferences {}
class _MockBroadcastRepo extends Mock implements BroadcastRepository {}

/// The envelope as it arrives on `notification_queue_update`.
///
/// 🔴 `message` IS AN EMPTY STRING ON PURPOSE. That is what the server sends
/// (`commons_ack_watcher.py`, `_push_ack_event`) — everything that identifies an ack is
/// under `payload`. A reader following this app's usual habit of looking in `message`
/// sees a blank frame and folds nothing, which is the bug this shape guards.
Map<String, dynamic> _ackFrame( {
  required String broadcastId,
  required String sessionId,
  String  personaName = 'Mr. Radio',
  String  notifId     = 'n-ack-1',
} ) => {
  'type'         : 'notification_queue_update',
  'notification' : {
    'id'                       : notifId,
    'message'                  : '',
    'type'                     : 'commons_broadcast_ack',
    'priority'                 : 'low',
    'timestamp'                : '2026-09-22T22:40:00',
    'played'                   : false,
    'play_count'               : 0,
    'response_requested'       : false,
    'suppress_ding'            : true,
    'sender_id'                : 'claude.code@lupin.deepily.ai#abc12345',
    'display_qualifier_widget' : false,
    'payload'                  : {
      'broadcast_id' : broadcastId,
      'session_id'   : sessionId,
      'persona_name' : personaName,
      'persona_icon' : '🦉',
      'status'       : 'acked',
      'body_summary' : 'on it',
    },
  },
};

/// A frame that is a perfectly ordinary notification — used to prove the broadcast arm
/// does not fire on everything that passes it.
Map<String, dynamic> _plainFrame() => {
  'type'         : 'notification_queue_update',
  'notification' : {
    'id'                       : 'n-plain-1',
    'message'                  : 'The build finished.',
    'type'                     : 'task',
    'priority'                 : 'low',
    'timestamp'                : '2026-09-22T22:41:00',
    'played'                   : false,
    'play_count'               : 0,
    'response_requested'       : false,
    'suppress_ding'            : true,
    'sender_id'                : 'claude.code@lupin.deepily.ai#abc12345',
    'display_qualifier_widget' : false,
  },
};

void main() {
  setUpAll( () { registerFallbackValue( const TtsSender() ); } );

  group( 'a commons_broadcast_ack frame folds into the live BroadcastBloc', () {
    late BroadcastBloc      broadcast;
    late _MockBroadcastRepo repo;
    late QuickAskBloc       quickAsk;
    late FocusChatBloc      focusBloc;
    late WsBlocDispatcher   dispatcher;

    /// Puts the bloc in the ONLY state that can fold an ack: one that has an aggregate,
    /// which exists only after a send. `_onAck` returns early when `aggregate == null`,
    /// so a test that skipped this would pass against a bloc that folds nothing.
    ///
    /// ⚠️ The roster load is not optional scaffolding — `canSend` is
    /// `hasBody && hasRecipients && !sending`, so a send with an empty roster returns
    /// early, no aggregate is built, and every assertion below would read 0 for a reason
    /// that has nothing to do with the dispatcher.
    Future<void> sendSoAggregateExists( { required String broadcastId, required int recipients } ) async {
      // A successful roster load chains straight into a history fetch
      // (`broadcast_bloc.dart:302`), so leaving this unstubbed fails every case in this
      // group with a `Null is not a Future<...>` from inside `_onHistory` — a cause that
      // reads nothing like the ack path under test.
      when( () => repo.fetchHistory( cancelToken: any( named: 'cancelToken' ) ) )
          .thenAnswer( ( _ ) async => const BroadcastHistory() );
      when( () => repo.fetchActiveSessions( cancelToken: any( named: 'cancelToken' ) ) ).thenAnswer(
        ( _ ) async => const ActiveSessionRoster( [
          ActiveSession( sessionId: 's-radio',  personaName: 'Mr. Radio' ),
          ActiveSession( sessionId: 's-maria',  personaName: 'María'     ),
          ActiveSession( sessionId: 's-cheech', personaName: 'Cheech'    ),
        ] ),
      );
      when( () => repo.send( message: any( named: 'message' ) ) ).thenAnswer(
        ( _ ) async => BroadcastSendResult(
          broadcastId      : broadcastId,
          recipients       : recipients,
          failedRecipients : const [],
          filteredOut      : const [],
          status           : 'queued',
        ),
      );

      broadcast.add( const BroadcastRosterRequested() );
      await Future<void>.delayed( const Duration( milliseconds: 50 ) );
      broadcast.add( const BroadcastBodyChanged( 'all hands' ) );
      broadcast.add( const BroadcastSendConfirmed() );
      await Future<void>.delayed( const Duration( milliseconds: 50 ) );
    }

    setUp( () {
      final notifRepo = _MockNotifRepo();
      final queueRepo = _MockQueueRepo();
      final audio     = _MockAudio();
      final ws        = _MockWs();
      repo            = _MockBroadcastRepo();

      when( () => audio.handleIncoming(
        priority     : any( named: 'priority' ),
        message      : any( named: 'message' ),
        title        : any( named: 'title' ),
        suppressDing : any( named: 'suppressDing' ),
      ) ).thenAnswer( ( _ ) async {} );
      when( () => ws.sessionId ).thenReturn( 'wise penguin' );
      when( () => ws.connectionStream ).thenAnswer( ( _ ) => const Stream<bool>.empty() );

      GetIt.instance.registerSingleton<NotificationBloc>( NotificationBloc( notifRepo, audio: audio ) );
      focusBloc = FocusChatBloc( notifRepo, tts: _MockTts() );
      GetIt.instance.registerSingleton<FocusChatBloc>( focusBloc );
      final qaPrefs = _MockQaPrefs();
      when( () => qaPrefs.sendImmediately ).thenReturn( false );
      quickAsk = QuickAskBloc( queueRepo, asr: _MockAsr(), ws: ws, notifications: notifRepo, prefs: qaPrefs );
      GetIt.instance.registerSingleton<QuickAskBloc>( quickAsk );

      broadcast = BroadcastBloc( repo );
      GetIt.instance.registerSingleton<BroadcastBloc>( broadcast );

      dispatcher = WsBlocDispatcher();
    } );

    tearDown( () async {
      await broadcast.close();
      await quickAsk.close();
      await focusBloc.close();
      await GetIt.instance.reset();
    } );

    test( '🔴 ONE ack frame off the wire raises the tally by one', () async {
      await sendSoAggregateExists( broadcastId: 'b-1', recipients: 3 );
      expect( broadcast.state.aggregate!.ackedCount, 0,
          reason: 'precondition: an aggregate exists and nothing has acked yet' );

      dispatcher.dispatch( 'notification_queue_update',
          _ackFrame( broadcastId: 'b-1', sessionId: 's-radio' ) );
      await Future<void>.delayed( const Duration( milliseconds: 50 ) );

      expect( broadcast.state.aggregate!.ackedCount, 1,
          reason: 'the dispatcher arm in app.dart is the ONLY path from a socket frame to '
                  'BroadcastAckReceived — if this is 0 that arm is gone or mis-typed' );
      expect( broadcast.state.aggregate!.acks.single.personaName, 'Mr. Radio',
              reason: 'the payload was read, not just counted' );
    } );

    test( 'the same frame twice is still one ack — the session keys the tally', () async {
      await sendSoAggregateExists( broadcastId: 'b-1', recipients: 3 );

      final frame = _ackFrame( broadcastId: 'b-1', sessionId: 's-radio' );
      dispatcher.dispatch( 'notification_queue_update', frame );
      dispatcher.dispatch( 'notification_queue_update', frame );
      await Future<void>.delayed( const Duration( milliseconds: 50 ) );

      expect( broadcast.state.aggregate!.ackedCount, 1,
          reason: 'a socket redelivery must not inflate the tally' );
    } );

    test( 'an ack for a DIFFERENT broadcast does not touch this tally', () async {
      await sendSoAggregateExists( broadcastId: 'b-1', recipients: 3 );

      dispatcher.dispatch( 'notification_queue_update',
          _ackFrame( broadcastId: 'b-OTHER', sessionId: 's-radio' ) );
      await Future<void>.delayed( const Duration( milliseconds: 50 ) );

      expect( broadcast.state.aggregate!.ackedCount, 0 );
    } );

    test( 'an ordinary notification frame folds nothing, and does not throw', () async {
      await sendSoAggregateExists( broadcastId: 'b-1', recipients: 3 );

      dispatcher.dispatch( 'notification_queue_update', _plainFrame() );
      await Future<void>.delayed( const Duration( milliseconds: 50 ) );

      expect( broadcast.state.aggregate!.ackedCount, 0,
          reason: 'the broadcast arm costs one type comparison on every other frame and '
                  'must fold nothing on them' );
    } );

    test( 'a MALFORMED ack frame is dropped, not fatal', () async {
      await sendSoAggregateExists( broadcastId: 'b-1', recipients: 3 );

      // A socket frame is untrusted input arriving at arbitrary times, and this stream is
      // shared with every other pane — a throw here would take them all down.
      final broken = {
        'type'         : 'notification_queue_update',
        'notification' : {
          'id'                       : 'n-bad',
          'message'                  : '',
          'type'                     : 'commons_broadcast_ack',
          'priority'                 : 'low',
          'timestamp'                : '2026-09-22T22:42:00',
          'played'                   : false,
          'play_count'               : 0,
          'response_requested'       : false,
          'suppress_ding'            : true,
          'sender_id'                : 'x',
          'display_qualifier_widget' : false,
          'payload'                  : { 'broadcast_id': '' },   // empty id — unreadable
        },
      };

      expect( () => dispatcher.dispatch( 'notification_queue_update', broken ), returnsNormally );
      await Future<void>.delayed( const Duration( milliseconds: 50 ) );
      expect( broadcast.state.aggregate!.ackedCount, 0 );
    } );
  } );
}
