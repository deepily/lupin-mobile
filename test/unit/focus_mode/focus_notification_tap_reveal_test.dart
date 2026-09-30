import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_bloc.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_event.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_state.dart';
import 'package:lupin_mobile/features/notifications/data/notification_models.dart';
import 'package:lupin_mobile/features/notifications/data/notification_repository.dart';
import 'package:lupin_mobile/services/tts/tts_orchestrator.dart';

class _MockRepo extends Mock implements NotificationRepository {}
class _MockTts  extends Mock implements TtsOrchestrator {}

/// Row d9bc6f6c — [FocusMessageRevealRequested]: what a notification tap does to
/// the focus surface once it reaches the bloc.
void main() {
  const who   = 'claude.code@lupin.deepily.ai#a1b2c3d4';
  const other = 'claude.code@lupin.deepily.ai#0d0d0d0d';
  const email = 'rick@test.com';

  late _MockRepo repo;
  late _MockTts  tts;

  Map<String, dynamic> wire( String id, String sender ) => {
    'id'                 : id,
    'sender_id'          : sender,
    'message'            : 'wire-$id',
    'title'              : '',
    'type'               : 'task',
    'priority'           : 'medium',
    'state'              : 'delivered',
    'is_hidden'          : false,
    'abstract'           : '',
    'created_at'         : '2026-09-28T01:00:00',
    'delivered_at'       : null,
    'responded_at'       : null,
    'response_requested' : false,
    'response_type'      : null,
    'response_value'     : null,
    'job_id'             : null,
    'progress_group_id'  : null,
    'timestamp'          : '2026-09-28T01:00:00',
    'time_display'       : '01:00 EDT',
  };

  setUpAll( () {
    SharedPreferences.setMockInitialValues( {} );
  } );

  setUp( () {
    repo = _MockRepo();
    tts  = _MockTts();
    when( () => repo.conversation( any(), any(), hours: any( named: 'hours' ) ) )
      .thenAnswer( ( _ ) async => <ConversationMessage>[] );
    when( () => repo.sendersVisible( any(), hours: any( named: 'hours' ) ) )
      .thenAnswer( ( _ ) async => <SenderSummary>[] );
    when( () => repo.activeSessions() ).thenAnswer( ( _ ) async => <ActiveSession>[] );
  } );

  FocusChatBloc newBloc() => FocusChatBloc( repo, tts: tts );

  group( "FocusMessageRevealRequested — selection and target land together", () {
    test( "selects the tap's sender AND records the message to reveal", () async {
      final bloc = newBloc();

      bloc.add( const FocusMessageRevealRequested(
        senderId       : who,
        notificationId : 'n-77',
        userEmail      : email,
      ) );
      await Future<void>.delayed( const Duration( milliseconds: 50 ) );

      expect( bloc.state.focusedSender, who,
          reason: "the must-have: Rick's complaint is having to tab through "
                  "personas to find who wrote" );
      expect( bloc.state.revealMessageId, 'n-77' );

      await bloc.close();
    } );

    test( "no intermediate state has one without the other", () async {
      // 🔴 THIS IS WHY IT IS ONE EVENT. Two events would be handled
      // CONCURRENTLY under bloc's default transformer, so a rebuild could catch
      // a selected sender with no target (no scroll) or a target with the wrong
      // sender focused (a scroll into someone else's conversation).
      final bloc = newBloc();
      final seen = <({ String? sender, String? reveal })>[];
      final sub  = bloc.stream.listen( ( s ) =>
          seen.add( ( sender: s.focusedSender, reveal: s.revealMessageId ) ) );

      bloc.add( const FocusMessageRevealRequested(
        senderId: who, notificationId: 'n-77', userEmail: email ) );
      await Future<void>.delayed( const Duration( milliseconds: 50 ) );

      expect( seen, isNotEmpty );
      for ( final s in seen ) {
        expect( s.sender, who );
        expect( s.reveal, 'n-77',
            reason: 'every emitted state carries both, or neither' );
      }

      await sub.cancel();
      await bloc.close();
    } );

    test( "zeroes the tapped sender's unread count, as a rail tap does", () async {
      final bloc = newBloc();

      bloc.add( FocusInboundNotification( NotificationItem(
        id: 'n-1', message: 'm', type: 'task', priority: 'medium',
        senderId: who, timestamp: DateTime( 2026, 9, 28 ), played: false,
        playCount: 0, responseRequested: false, suppressDing: false,
        displayQualifierWidget: false ) ) );
      await Future<void>.delayed( const Duration( milliseconds: 20 ) );
      expect( bloc.state.unreadBySender[ who ], 1, reason: 'setup' );

      bloc.add( const FocusMessageRevealRequested(
        senderId: who, notificationId: 'n-1', userEmail: email ) );
      await Future<void>.delayed( const Duration( milliseconds: 50 ) );

      expect( bloc.state.unreadBySender[ who ], 0 );

      await bloc.close();
    } );
  } );

  group( "FocusMessageRevealRequested — backfill without a cold start", () {
    test( "BACKFILLS the tapped conversation even though cold start never ran", () async {
      // 🔴 THE COLD-START CASE THIS ROW IS ACTUALLY ABOUT. The app was swiped
      // away, so the tap is drained at AuthAuthenticated — BEFORE the WS
      // `auth_success` frame that normally hands the bloc its email. A reveal
      // that waited for that would show "No messages yet in this window" for a
      // conversation that has messages, and the user would see the bug as
      // unfixed.
      when( () => repo.conversation( who, email, hours: any( named: 'hours' ) ) )
        .thenAnswer( ( _ ) async =>
            [ ConversationMessage.fromJson( wire( 'n-77', who ) ) ] );

      final bloc = newBloc();

      bloc.add( const FocusMessageRevealRequested(
        senderId: who, notificationId: 'n-77', userEmail: email ) );
      await Future<void>.delayed( const Duration( milliseconds: 80 ) );

      verify( () => repo.conversation( who, email, hours: any( named: 'hours' ) ) )
          .called( 1 );
      expect( bloc.state.windows[ who ]?.map( ( m ) => m.item.id ), [ 'n-77' ] );
      expect( bloc.state.hydration, FocusHydration.ready );

      await bloc.close();
    } );

    test( "NEGATIVE CONTROL: a plain FocusSenderSelected with no cold start "
          "fetches NOTHING", () async {
      // The behaviour the reveal path had to work around, pinned so the reason
      // the event carries an email is visible rather than folklore.
      final bloc = newBloc();

      bloc.add( const FocusSenderSelected( who ) );
      await Future<void>.delayed( const Duration( milliseconds: 80 ) );

      verifyNever( () => repo.conversation( any(), any(), hours: any( named: 'hours' ) ) );
      expect( bloc.state.windows[ who ], isNull );

      await bloc.close();
    } );

    test( "a cold start already run WINS — the event's email is only a fallback",
        () async {
      when( () => repo.sendersVisible( 'cold@test.com', hours: any( named: 'hours' ) ) )
        .thenAnswer( ( _ ) async => [ SenderSummary(
            senderId: who, lastActivity: DateTime.now(), count: 1 ) ] );

      final bloc = newBloc();
      bloc.add( const FocusColdStartRequested( userEmail: 'cold@test.com' ) );
      await Future<void>.delayed( const Duration( milliseconds: 60 ) );

      bloc.add( const FocusMessageRevealRequested(
        senderId: who, notificationId: 'n-77', userEmail: 'stale@test.com' ) );
      await Future<void>.delayed( const Duration( milliseconds: 60 ) );

      verify( () => repo.conversation( who, 'cold@test.com',
          hours: any( named: 'hours' ) ) ).called( 1 );
      verifyNever( () => repo.conversation( who, 'stale@test.com',
          hours: any( named: 'hours' ) ) );

      await bloc.close();
    } );

    test( "does not re-fetch a conversation already backfilled", () async {
      final bloc = newBloc();

      bloc.add( const FocusMessageRevealRequested(
        senderId: who, notificationId: 'n-1', userEmail: email ) );
      await Future<void>.delayed( const Duration( milliseconds: 60 ) );
      bloc.add( const FocusMessageRevealRequested(
        senderId: who, notificationId: 'n-2', userEmail: email ) );
      await Future<void>.delayed( const Duration( milliseconds: 60 ) );

      verify( () => repo.conversation( who, email, hours: any( named: 'hours' ) ) )
          .called( 1 );
      expect( bloc.state.revealMessageId, 'n-2',
          reason: 'the second tap still moves the target' );

      await bloc.close();
    } );

    test( "a failing backfill leaves the sender selected and the target intact",
        () async {
      when( () => repo.conversation( who, email, hours: any( named: 'hours' ) ) )
        .thenThrow( const NotificationApiException( 'boom' ) );

      final bloc = newBloc();
      bloc.add( const FocusMessageRevealRequested(
        senderId: who, notificationId: 'n-77', userEmail: email ) );
      await Future<void>.delayed( const Duration( milliseconds: 60 ) );

      expect( bloc.state.hydration, FocusHydration.error );
      expect( bloc.state.focusedSender, who,
          reason: 'the retry banner is shown over the RIGHT conversation' );
      expect( bloc.state.revealMessageId, 'n-77' );

      await bloc.close();
    } );
  } );

  group( "the reveal target is a ONE-SHOT instruction", () {
    test( "FocusRevealConsumed clears it", () async {
      final bloc = newBloc();
      bloc.add( const FocusMessageRevealRequested(
        senderId: who, notificationId: 'n-77', userEmail: email ) );
      await Future<void>.delayed( const Duration( milliseconds: 60 ) );

      bloc.add( const FocusRevealConsumed() );
      await Future<void>.delayed( const Duration( milliseconds: 20 ) );

      expect( bloc.state.revealMessageId, isNull );
      expect( bloc.state.focusedSender, who,
          reason: 'consuming the scroll must not deselect the conversation' );

      await bloc.close();
    } );

    test( "consuming when nothing is set emits no state at all", () async {
      final bloc = newBloc();
      final seen = <FocusChatState>[];
      final sub  = bloc.stream.listen( seen.add );

      bloc.add( const FocusRevealConsumed() );
      await Future<void>.delayed( const Duration( milliseconds: 20 ) );

      expect( seen, isEmpty, reason: 'no needless rebuild of the whole surface' );

      await sub.cancel();
      await bloc.close();
    } );

    test( "a RAIL tap clears a stale target", () async {
      // Tap a notification, then navigate by hand. Without the clear, coming
      // back to that sender would scroll to the old message again — the list
      // jumping under a user who did not ask for it.
      final bloc = newBloc();
      bloc.add( const FocusMessageRevealRequested(
        senderId: who, notificationId: 'n-77', userEmail: email ) );
      await Future<void>.delayed( const Duration( milliseconds: 60 ) );
      expect( bloc.state.revealMessageId, 'n-77', reason: 'setup' );

      bloc.add( const FocusSenderSelected( other ) );
      await Future<void>.delayed( const Duration( milliseconds: 60 ) );

      expect( bloc.state.focusedSender, other );
      expect( bloc.state.revealMessageId, isNull );

      await bloc.close();
    } );

    test( "a cold start does NOT disturb a live reveal", () async {
      // The real sequence: the tap is routed at AuthAuthenticated, and the WS
      // `auth_success` cold start arrives a moment later. It must not clear the
      // selection or the target on its way past.
      final bloc = newBloc();
      bloc.add( const FocusMessageRevealRequested(
        senderId: who, notificationId: 'n-77', userEmail: email ) );
      await Future<void>.delayed( const Duration( milliseconds: 60 ) );

      bloc.add( const FocusColdStartRequested( userEmail: email ) );
      await Future<void>.delayed( const Duration( milliseconds: 80 ) );

      expect( bloc.state.focusedSender, who );
      expect( bloc.state.revealMessageId, 'n-77' );

      await bloc.close();
    } );
  } );
}
