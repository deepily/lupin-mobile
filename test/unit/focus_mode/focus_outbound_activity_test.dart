/// Rick 2026-09-17: the rail's Live lens means "notifications sent OR
/// received in the last hour". A session the user wrote to counts as live by
/// that fact alone, so a successful send bumps its activity and pulls it back
/// into the Live band — for a reply to an ask and for a plain message alike.
///
/// The live-arrival direction was already covered; this file covers the
/// OUTBOUND one, and lives apart from focus_chat_bloc_test.dart because that
/// file is pinned by frozen_surface_test.dart.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_bloc.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_event.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_state.dart';
import 'package:lupin_mobile/features/notifications/data/notification_models.dart';
import 'package:lupin_mobile/features/notifications/data/notification_repository.dart';
import 'package:lupin_mobile/services/tts/tts_orchestrator.dart';

class _MockRepo extends Mock implements NotificationRepository {}
class _MockTts  extends Mock implements TtsOrchestrator {}

const String _sender = 'claude.code@lupin.deepily.ai#abc12345';

NotificationItem _item( String id, { bool ask = false, required DateTime ts } ) {
  return NotificationItem(
    id                     : id,
    message                : 'msg-$id',
    type                   : 'task',
    priority               : 'low',
    senderId               : _sender,
    timestamp              : ts,
    played                 : true,
    playCount              : 0,
    responseRequested      : ask,
    responseType           : ask ? 'open_ended' : null,
    suppressDing           : true,
    displayQualifierWidget : false,
  );
}

void main() {
  setUpAll( () {
    registerFallbackValue( const NotifyRequest( message: 'f', targetUser: 'f' ) );
    registerFallbackValue( const NotificationResponsePayload(
      notificationId: 'f', responseValue: 'f' ) );
  } );

  group( 'the Live lens counts what the user SENDS, not only what arrives', () {
    late _MockRepo repo;
    late _MockTts  tts;
    late DateTime  clock;
    FocusChatBloc? bloc;

    setUp( () {
      repo  = _MockRepo();
      tts   = _MockTts();
      clock = DateTime( 2026, 9, 17, 15, 0 );
      when( () => tts.enqueueAlways(
        message  : any( named: 'message'  ),
        priority : any( named: 'priority' ),
        title    : any( named: 'title'    ),
        voiceId  : any( named: 'voiceId'  ),
        sender   : any( named: 'sender'   ),
      ) ).thenReturn( null );
      when( () => repo.sendersVisible( any(), hours: any( named: 'hours' ) ) )
          .thenAnswer( ( _ ) async => const [] );
      bloc = FocusChatBloc( repo, tts: tts, now: () => clock );
      bloc!.add( const FocusColdStartRequested( userEmail: 'ricardo.felipe.ruiz@gmail.com' ) );
      // These senders carry no persona glyph; widen the scope so the default
      // Personas-only rail (2026-08-21 §5f) is not what hides them — the
      // Live/History band is what this file is about.
      bloc!.add( const FocusSenderScopeChanged( FocusSenderScope.all ) );
    } );

    tearDown( () async => bloc?.close() );

    Future<void> pump() => Future<void>.delayed( const Duration( milliseconds: 10 ) );

    /// An inbound message 90 minutes old: past the 1-hour Live window, so the
    /// sender starts in History and is hidden by the default Live lens.
    Future<void> seedStaleSender( { bool ask = false } ) async {
      bloc!.add( FocusInboundNotification(
          _item( ask ? 'ask-1' : 'plain-1', ask: ask, ts: clock ) ) );
      await pump();
      clock = clock.add( const Duration( minutes: 90 ) );
      bloc!.add( const FocusFilterChanged( FocusFilter.history ) );   // re-derives the band off the new clock
      bloc!.add( const FocusFilterChanged( FocusFilter.live ) );
      await pump();
      expect( bloc!.state.bandFor( _sender ), FocusBand.history,
          reason: 'setup: the sender must START outside the Live window' );
      expect( bloc!.state.visibleOrder, isEmpty, reason: 'setup: hidden by the Live lens' );
    }

    test( 'a plain message to a session pulls it back into Live', () async {
      when( () => repo.notify( any() ) ).thenAnswer( ( _ ) async =>
          NotifyDispatchResponse.fromJson(
              { 'status': 'queued', 'target_user': 'cc', 'connection_count': 1 } ) );
      await seedStaleSender();

      bloc!.add( const FocusRespondRequested( senderId: _sender, text: 'you there?' ) );
      await pump();

      verify( () => repo.notify( any() ) ).called( 1 );
      expect( bloc!.state.lastActivityBySender[ _sender ], clock );
      expect( bloc!.state.bandFor( _sender ), FocusBand.live );
      expect( bloc!.state.visibleOrder, [ _sender ],
          reason: 'the session the user just wrote to is on the rail' );
    } );

    test( 'answering an ask pulls it back into Live too', () async {
      when( () => repo.respond( any() ) ).thenAnswer( ( _ ) async =>
          NotificationResponseAck.fromJson(
              { 'status': 'ok', 'notification_id': 'ask-1' } ) );
      await seedStaleSender( ask: true );

      bloc!.add( const FocusRespondRequested( senderId: _sender, text: 'yes' ) );
      await pump();

      verify( () => repo.respond( any() ) ).called( 1 );
      expect( bloc!.state.lastActivityBySender[ _sender ], clock );
      expect( bloc!.state.bandFor( _sender ), FocusBand.live );
      expect( bloc!.state.visibleOrder, [ _sender ] );
    } );

    test( 'a FAILED send does not fake activity — the sender stays in History', () async {
      when( () => repo.notify( any() ) ).thenThrow(
          const NotificationApiException( 'Notify dispatch failed', statusCode: 401 ) );
      await seedStaleSender();

      bloc!.add( const FocusRespondRequested( senderId: _sender, text: 'you there?' ) );
      await pump();

      expect( bloc!.state.bandFor( _sender ), FocusBand.history,
          reason: 'nothing was delivered, so nothing is live' );
      expect( bloc!.state.visibleOrder, isEmpty );
      expect( bloc!.state.hydration, FocusHydration.error );
    } );
  } );
}
