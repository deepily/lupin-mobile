/// Row d9bc6f6c, the SEAM — a held tap becoming a focus-surface event through the
/// REAL `app.dart` login hook, not a copy of it.
///
/// 🔴 THE FAILURE THIS TIER EXISTS TO CATCH IS AN UNWIRED SEAM, which every unit
/// test above passes over. The codec encodes, the router holds, the bloc reveals —
/// and a build where `onWsAuthenticated` simply never drains the router has all of
/// that and still ships Rick's bug unchanged. So this file calls the production
/// function and asserts what reaches the production bloc.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/app.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_bloc.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_event.dart';
import 'package:lupin_mobile/features/notifications/data/notification_models.dart';
import 'package:lupin_mobile/features/notifications/data/notification_repository.dart';
import 'package:lupin_mobile/services/push/notification_tap_payload.dart';
import 'package:lupin_mobile/services/push/notification_tap_router.dart';
import 'package:lupin_mobile/services/tts/tts_orchestrator.dart';
import 'package:lupin_mobile/services/websocket/websocket_service.dart';

class _MockRepo extends Mock implements NotificationRepository {}
class _MockTts  extends Mock implements TtsOrchestrator {}
class _MockWs   extends Mock implements WebSocketService {}

void main() {
  const uuid   = '7217ccef-72fb-4bc1-bf46-8b0ab5d82594';
  const email  = 'rick@test.com';
  const sender = 'claude.code@lupin-mobile.deepily.ai#a1b2c3d4';

  late _MockRepo             repo;
  late _MockWs               ws;
  late FocusChatBloc         focusBloc;
  late WsBlocDispatcher      dispatcher;
  late NotificationTapRouter router;

  setUp( () {
    repo       = _MockRepo();
    ws         = _MockWs();
    dispatcher = WsBlocDispatcher();
    router     = NotificationTapRouter();

    when( () => repo.conversation( any(), any(), hours: any( named: 'hours' ) ) )
      .thenAnswer( ( _ ) async => <ConversationMessage>[] );
    when( () => repo.sendersVisible( any(), hours: any( named: 'hours' ) ) )
      .thenAnswer( ( _ ) async => <SenderSummary>[] );
    when( () => repo.activeSessions() ).thenAnswer( ( _ ) async => <ActiveSession>[] );
    when( () => ws.isConnected ).thenReturn( true );
    when( () => ws.connect( userId: any( named: 'userId' ) ) ).thenAnswer( ( _ ) async {} );

    focusBloc = FocusChatBloc( repo, tts: _MockTts() );
    GetIt.instance.registerSingleton<FocusChatBloc>( focusBloc );
  } );

  tearDown( () async {
    await focusBloc.close();
    await router.dispose();
    await GetIt.instance.reset();
  } );

  Future<void> login( { NotificationTapRouter? tapRouter } ) async {
    await onWsAuthenticated(
      dispatcher           : dispatcher,
      ws                   : ws,
      userId               : uuid,
      email                : email,
      registerPush         : ( _ ) async {},
      requestNotifications : () async => true,
      tapRouter            : tapRouter,
    );
    await Future<void>.delayed( const Duration( milliseconds: 80 ) );
  }

  group( 'the login drain (cold start, and a tap taken at the lock screen)', () {
    test( 'a held tap selects its sender and marks its message for reveal', () async {
      router.offer( const NotificationTapPayload(
        notificationId: 'n-77', senderId: sender ) );

      await login( tapRouter: router );

      expect( focusBloc.state.focusedSender, sender,
          reason: "the whole point: Rick should not have to hunt for who wrote" );
      expect( focusBloc.state.revealMessageId, 'n-77' );
    } );

    test( 'it backfills with the email THIS login supplied', () async {
      // The ordering that makes the reveal event carry an email at all: the drain
      // happens at AuthAuthenticated, before the WS `auth_success` frame that
      // normally hands the bloc its email.
      router.offer( const NotificationTapPayload(
        notificationId: 'n-77', senderId: sender ) );

      await login( tapRouter: router );

      verify( () => repo.conversation( sender, email, hours: any( named: 'hours' ) ) )
          .called( 1 );
    } );

    test( 'NEGATIVE CONTROL: no held tap ⇒ nothing is selected', () async {
      await login( tapRouter: router );

      expect( focusBloc.state.focusedSender, isNull,
          reason: 'an ordinary login must land on the cold-start empty state — '
                  'Q4-LITERAL is no auto-focus, ever' );
      expect( focusBloc.state.revealMessageId, isNull );
      verifyNever( () => repo.conversation( any(), any(), hours: any( named: 'hours' ) ) );
    } );

    test( 'a null router is tolerated (the seam is optional at the call site)', () async {
      await login();

      expect( focusBloc.state.focusedSender, isNull );
    } );

    test( 'an UNROUTABLE tap selects nothing — a fallback notification', () async {
      // `ws_wake` fallbacks carry no sender. The router refuses to hold them, so
      // this asserts the end-to-end consequence: the app opens, on no conversation.
      router.offer( const NotificationTapPayload( notificationId: 'n-fallback' ) );

      await login( tapRouter: router );

      expect( focusBloc.state.focusedSender, isNull );
    } );

    test( 'the tap is consumed — a SECOND login does not re-route it', () async {
      router.offer( const NotificationTapPayload(
        notificationId: 'n-77', senderId: sender ) );
      await login( tapRouter: router );

      // Navigate away by hand, then reconnect.
      focusBloc.add( const FocusSenderSelected( 'someone-else' ) );
      await Future<void>.delayed( const Duration( milliseconds: 40 ) );

      await login( tapRouter: router );

      expect( focusBloc.state.focusedSender, 'someone-else',
          reason: 'a reconnect must not drag the user back to an hour-old '
                  'notification they have already dealt with' );
      expect( focusBloc.state.revealMessageId, isNull );
    } );

    test( 'the login still completes its other work when a tap is present', () async {
      // The drain is inserted into a function that also stamps the dispatcher,
      // connects the socket and registers for push. It must not displace any of it.
      final pushed = <String>[];
      router.offer( const NotificationTapPayload(
        notificationId: 'n-77', senderId: sender ) );
      when( () => ws.isConnected ).thenReturn( false );

      await onWsAuthenticated(
        dispatcher           : dispatcher,
        ws                   : ws,
        userId               : uuid,
        email                : email,
        registerPush         : ( e ) async => pushed.add( e ),
        requestNotifications : () async => true,
        tapRouter            : router,
      );
      await Future<void>.delayed( const Duration( milliseconds: 60 ) );

      expect( dispatcher.lastAuthenticatedEmail, email );
      expect( pushed, [ email ] );
      verify( () => ws.connect( userId: uuid ) ).called( 1 );
      expect( focusBloc.state.focusedSender, sender );
    } );
  } );

  group( 'a tap offered BEFORE login is not lost', () {
    test( 'it waits in the router across an arbitrary delay', () async {
      // The cold start, in slow motion: `main()` offers the tap, then the user
      // spends however long they like at the fingerprint prompt.
      router.offer( const NotificationTapPayload(
        notificationId: 'n-77', senderId: sender ) );

      await Future<void>.delayed( const Duration( milliseconds: 150 ) );
      expect( router.hasPending, isTrue );

      await login( tapRouter: router );

      expect( focusBloc.state.focusedSender, sender );
    } );
  } );
}
