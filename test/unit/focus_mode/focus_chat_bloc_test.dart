import 'dart:async';

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

NotificationItem _item(
  String id,
  String sender, {
  String    priority = 'medium',
  String    type     = 'task',
  bool      ask      = false,
  String?   responseType,
  Map<String, dynamic>? options,
  String?   voiceId,
  DateTime? ts,
} ) {
  return NotificationItem(
    id                     : id,
    message                : 'msg-$id',
    type                   : type,
    priority               : priority,
    senderId               : sender,
    timestamp              : ts ?? DateTime( 2026, 6, 12, 1 ),
    played                 : false,
    playCount              : 0,
    responseRequested      : ask,
    responseType           : responseType,
    responseOptions        : options,
    suppressDing           : false,
    displayQualifierWidget : false,
    voicePersona           : voiceId != null
        ? VoicePersona.fromJson( { 'name': 'P-$voiceId', 'voice_id': voiceId } )
        : null,
  );
}

/// 19-field conversation wire shape per the Phase-0 capture
/// (test/fixtures/notifications/conversation_wire_sample.json) — NO
/// response_options, NO voice_persona, state fields present.
Map<String, dynamic> _wireMsg(
  String id,
  String sender, {
  String  ts                = '2026-06-12T01:00:00',
  bool    responseRequested = false,
  String? responseType,
  String  state             = 'delivered',
  dynamic responseValue,
  bool    isHidden          = false,
} ) {
  return {
    'id'                 : id,
    'sender_id'          : sender,
    'message'            : 'wire-$id',
    'title'              : '',
    'type'               : 'task',
    'priority'           : 'medium',
    'state'              : state,
    'is_hidden'          : isHidden,
    'abstract'           : '',
    'created_at'         : ts,
    'delivered_at'       : null,
    'responded_at'       : null,
    'response_requested' : responseRequested,
    'response_type'      : responseType,
    'response_value'     : responseValue,
    'job_id'             : null,
    'progress_group_id'  : null,
    'timestamp'          : ts,
    'time_display'       : '01:00 EDT',
  };
}

ConversationMessage _conv( Map<String, dynamic> wire ) =>
    ConversationMessage.fromJson( wire );

SenderSummary _sender( String id, DateTime? lastActivity ) =>
    SenderSummary( senderId: id, lastActivity: lastActivity, count: 1 );

void main() {
  group( 'FocusChatBloc (S2)', () {
    late _MockRepo repo;
    late _MockTts  tts;
    FocusChatBloc? bloc;

    setUpAll( () {
      registerFallbackValue( const NotificationResponsePayload(
        notificationId : 'fallback',
        responseValue  : 'fallback',
      ) );
    } );

    setUp( () {
      repo = _MockRepo();
      tts  = _MockTts();
      bloc = FocusChatBloc( repo, tts: tts );
    } );

    tearDown( () async {
      await bloc?.close();
    } );

    Future<void> pump() => Future<void>.delayed( const Duration( milliseconds: 10 ) );

    void stubSenders( List<SenderSummary> result ) {
      when( () => repo.senders( any(), hours: any( named: 'hours' ) ) )
          .thenAnswer( ( _ ) async => result );
    }

    void stubConversation( List<ConversationMessage> result ) {
      when( () => repo.conversation(
        any(), any(),
        hours  : any( named: 'hours'  ),
        anchor : any( named: 'anchor' ),
      ) ).thenAnswer( ( _ ) async => result );
    }

    test( 'AC-S2.1 — inbound from new senders appends to senderOrder END (establishment order B, A, C)', () async {
      bloc!.add( FocusInboundNotification( _item( '1', 'B' ) ) );
      bloc!.add( FocusInboundNotification( _item( '2', 'A' ) ) );
      bloc!.add( FocusInboundNotification( _item( '3', 'C' ) ) );
      await pump();

      expect( bloc!.state.senderOrder, [ 'B', 'A', 'C' ] );
    } );

    test( 'AC-S2.2 — 8th message evicts the oldest; window stays 7 newest-last', () async {
      for ( var i = 1; i <= 8; i++ ) {
        bloc!.add( FocusInboundNotification( _item( '$i', 'X' ) ) );
      }
      await pump();

      final window = bloc!.state.windows[ 'X' ]!;
      expect( window.length, 7 );
      expect( window.first.item.id, '2', reason: 'oldest evicted' );
      expect( window.last.item.id,  '8', reason: 'newest last' );
    } );

    test( 'AC-S2.3 — unread increments for non-focused, stays 0 for focused; viewport pointer unchanged (Q4)', () async {
      bloc!.add( const FocusSenderSelected( 'X' ) );   // no cold start yet → no backfill
      await pump();

      bloc!.add( FocusInboundNotification( _item( '1', 'Y' ) ) );
      bloc!.add( FocusInboundNotification( _item( '2', 'X' ) ) );
      await pump();

      expect( bloc!.state.unreadBySender[ 'Y' ], 1 );
      expect( bloc!.state.unreadBySender[ 'X' ], 0 );
      expect( bloc!.state.focusedSender, 'X', reason: 'Q4 — inbound never moves the viewport' );
    } );

    test( 'AC-S2.4 — select zeroes unread, sets focus, hydrates loading→ready; backfilled ask retains discriminator (thin adapter, Phase-0)', () async {
      stubSenders( [ _sender( 'S', DateTime( 2026, 6, 12 ) ) ] );
      stubConversation( [
        _conv( _wireMsg( 'm1', 'S', ts: '2026-06-12T01:00:00' ) ),
        _conv( _wireMsg( 'ask-answered', 'S',
          ts: '2026-06-12T01:01:00',
          responseRequested: true, responseType: 'yes_no',
          state: 'responded', responseValue: 'yes' ) ),
        _conv( _wireMsg( 'ask-open', 'S',
          ts: '2026-06-12T01:02:00',
          responseRequested: true, responseType: 'multiple_choice',
          state: 'delivered' ) ),
      ] );

      bloc!.add( const FocusColdStartRequested( userEmail: 'rick@test.com' ) );
      await pump();

      final hydrations = <FocusHydration>[];
      final sub = bloc!.stream.listen( ( s ) => hydrations.add( s.hydration ) );

      bloc!.add( FocusInboundNotification( _item( 'live', 'S' ) ) );   // unread 1 while unfocused
      await pump();
      expect( bloc!.state.unreadBySender[ 'S' ], 1 );

      bloc!.add( const FocusSenderSelected( 'S' ) );
      await pump();

      expect( hydrations, contains( FocusHydration.loading ) );
      expect( bloc!.state.hydration, FocusHydration.ready );
      expect( bloc!.state.unreadBySender[ 'S' ], 0 );
      expect( bloc!.state.focusedSender, 'S' );

      final window = bloc!.state.windows[ 'S' ]!;
      expect( window.map( ( m ) => m.item.id ),
          containsAll( [ 'm1', 'ask-answered', 'ask-open', 'live' ] ) );

      final answered  = window.firstWhere( ( m ) => m.item.id == 'ask-answered' );
      final unanswered = window.firstWhere( ( m ) => m.item.id == 'ask-open' );
      expect( answered.answered,  isTrue,  reason: 'state=responded → answered' );
      expect( unanswered.answered, isFalse, reason: 'delivered ask → unanswered' );
      // Phase-0 amendment (F-S2-S2-2 operative branch): the 19-field wire
      // carries NO response_options — backfilled asks arrive without them
      // (S3 fallback affordance covers); the discriminator is what the
      // mapping must retain, and does.
      expect( unanswered.item.responseOptions, isNull );
      expect( bloc!.state.pendingPromptFor( 'S' )!.item.id, 'ask-open' );

      await sub.cancel();
    } );

    test( 'AC-S2.5 — EVERY inbound (low AND urgent) → exactly one enqueueAlways each, voiceId piped', () async {
      bloc!.add( FocusInboundNotification(
          _item( '1', 'X', priority: 'low', voiceId: 'vx-1' ) ) );
      bloc!.add( FocusInboundNotification(
          _item( '2', 'X', priority: 'urgent', voiceId: 'vx-1' ) ) );
      await pump();

      verify( () => tts.enqueueAlways(
        priority : 'low',
        message  : 'msg-1',
        title    : any( named: 'title' ),
        voiceId  : 'vx-1',
      ) ).called( 1 );
      verify( () => tts.enqueueAlways(
        priority : 'urgent',
        message  : 'msg-2',
        title    : any( named: 'title' ),
        voiceId  : 'vx-1',
      ) ).called( 1 );
      verifyNever( () => tts.enqueueIfSpeakable(
        priority : any( named: 'priority' ),
        message  : any( named: 'message' ),
        title    : any( named: 'title' ),
        voiceId  : any( named: 'voiceId' ),
      ) );
    } );

    test( 'AC-S2.6 — cold start orders registry lastActivity DESC; later live arrival APPENDS (snapshot never re-sorts)', () async {
      stubSenders( [
        _sender( 'A', DateTime( 2026, 6, 12, 10 ) ),
        _sender( 'B', DateTime( 2026, 6, 12, 12 ) ),
        _sender( 'C', DateTime( 2026, 6, 12, 11 ) ),
        _sender( 'Z', null ),                          // null activity sorts last
      ] );

      bloc!.add( const FocusColdStartRequested( userEmail: 'rick@test.com' ) );
      await pump();

      expect( bloc!.state.senderOrder, [ 'B', 'C', 'A', 'Z' ] );
      expect( bloc!.state.hydration, FocusHydration.ready );

      bloc!.add( FocusInboundNotification( _item( '1', 'NEW' ) ) );
      await pump();
      expect( bloc!.state.senderOrder, [ 'B', 'C', 'A', 'Z', 'NEW' ],
          reason: 'establishment order governs live arrivals — no re-sort' );
    } );

    test( 'AC-S2.9(i) — explicit typed promptContext → respond() with THAT notificationId + user reply appended', () async {
      when( () => repo.respond( any() ) ).thenAnswer( ( _ ) async =>
          NotificationResponseAck.fromJson( { 'status': 'ok', 'notification_id': 'explicit-id' } ) );

      bloc!.add( FocusInboundNotification(
          _item( 'explicit-id', 'S', ask: true, responseType: 'yes_no' ) ) );
      await pump();

      bloc!.add( const FocusRespondRequested(
        senderId      : 'S',
        text          : 'yes',
        promptContext : FocusPromptContext( notificationId: 'explicit-id' ),
      ) );
      await pump();

      final captured = verify( () => repo.respond( captureAny() ) ).captured;
      expect( ( captured.single as NotificationResponsePayload ).notificationId, 'explicit-id' );

      final window = bloc!.state.windows[ 'S' ]!;
      expect( window.last.item.type, 'user_initiated_message' );
      expect( window.last.item.message, 'yes' );
      expect( window.firstWhere( ( m ) => m.item.id == 'explicit-id' ).answered, isTrue,
          reason: 'answered ask no longer pending' );
      expect( bloc!.state.pendingPromptFor( 'S' ), isNull );
    } );

    test( 'AC-S2.9(ii) — no context, ≥2 unanswered asks → respond() targets the NEWEST one', () async {
      when( () => repo.respond( any() ) ).thenAnswer( ( _ ) async =>
          NotificationResponseAck.fromJson( { 'status': 'ok', 'notification_id': 'ask-new' } ) );

      bloc!.add( FocusInboundNotification( _item( 'ask-old', 'S',
          ask: true, responseType: 'open_ended', ts: DateTime( 2026, 6, 12, 1 ) ) ) );
      bloc!.add( FocusInboundNotification( _item( 'ask-new', 'S',
          ask: true, responseType: 'open_ended', ts: DateTime( 2026, 6, 12, 2 ) ) ) );
      await pump();

      bloc!.add( const FocusRespondRequested( senderId: 'S', text: 'voice reply' ) );
      await pump();

      final captured = verify( () => repo.respond( captureAny() ) ).captured;
      expect( ( captured.single as NotificationResponsePayload ).notificationId, 'ask-new',
          reason: 'newest-selection rule, not any-pending' );
    } );

    test( 'AC-S2.9(iii) — no context, no pending ask → NO respond() call, no crash, state unchanged', () async {
      bloc!.add( FocusInboundNotification( _item( 'plain', 'S' ) ) );
      await pump();
      final before = bloc!.state;

      bloc!.add( const FocusRespondRequested( senderId: 'S', text: 'orphan reply' ) );
      await pump();

      verifyNever( () => repo.respond( any() ) );
      expect( bloc!.state, before );
    } );

    test( 'AC-S2.9(failure) — repository failure sets hydration = error', () async {
      when( () => repo.respond( any() ) )
          .thenThrow( const NotificationApiException( 'boom', statusCode: 500 ) );

      bloc!.add( FocusInboundNotification(
          _item( 'ask1', 'S', ask: true, responseType: 'yes_no' ) ) );
      await pump();

      bloc!.add( const FocusRespondRequested( senderId: 'S', text: 'yes' ) );
      await pump();

      expect( bloc!.state.hydration, FocusHydration.error );
    } );

    test( 'AC-S2.10 — reconnect-refresh merge contract: order kept, new sender appended, dedupe-by-id cap 7, unread preserved+incremented, focus unchanged', () async {
      // Cold start: A newest, B older.
      stubSenders( [
        _sender( 'A', DateTime( 2026, 6, 12, 12 ) ),
        _sender( 'B', DateTime( 2026, 6, 12, 11 ) ),
      ] );
      stubConversation( [
        _conv( _wireMsg( 'a1', 'A', ts: '2026-06-12T01:00:00' ) ),
        _conv( _wireMsg( 'a2', 'A', ts: '2026-06-12T01:01:00' ) ),
      ] );
      bloc!.add( const FocusColdStartRequested( userEmail: 'rick@test.com' ) );
      await pump();
      bloc!.add( const FocusSenderSelected( 'A' ) );   // hydrates A
      await pump();

      stubConversation( [ _conv( _wireMsg( 'b1', 'B', ts: '2026-06-12T01:00:00' ) ) ] );
      bloc!.add( const FocusSenderSelected( 'B' ) );   // hydrates B; focus = B
      await pump();

      bloc!.add( FocusInboundNotification( _item( 'aL', 'A', ts: DateTime( 2026, 6, 12, 1, 5 ) ) ) );
      await pump();
      expect( bloc!.state.unreadBySender[ 'A' ], 1 );
      expect( bloc!.state.senderOrder, [ 'A', 'B' ] );

      // Reconnect: server now ALSO knows C; A has a missed message a3.
      stubSenders( [
        _sender( 'C', DateTime( 2026, 6, 12, 13 ) ),   // would sort first on a re-sort
        _sender( 'A', DateTime( 2026, 6, 12, 12 ) ),
        _sender( 'B', DateTime( 2026, 6, 12, 11 ) ),
      ] );
      when( () => repo.conversation(
        'A', any(),
        hours  : any( named: 'hours'  ),
        anchor : any( named: 'anchor' ),
      ) ).thenAnswer( ( _ ) async => [
        _conv( _wireMsg( 'a1', 'A', ts: '2026-06-12T01:00:00' ) ),   // dup
        _conv( _wireMsg( 'a2', 'A', ts: '2026-06-12T01:01:00' ) ),   // dup
        _conv( _wireMsg( 'a3', 'A', ts: '2026-06-12T01:10:00' ) ),   // missed while away
      ] );
      when( () => repo.conversation(
        'B', any(),
        hours  : any( named: 'hours'  ),
        anchor : any( named: 'anchor' ),
      ) ).thenAnswer( ( _ ) async => [
        _conv( _wireMsg( 'b1', 'B', ts: '2026-06-12T01:00:00' ) ),   // dup only
      ] );

      bloc!.add( const FocusColdStartRequested( userEmail: 'rick@test.com' ) );
      await pump();

      final s = bloc!.state;
      expect( s.senderOrder, [ 'A', 'B', 'C' ],
          reason: 'existing positions kept (no re-sort), new sender APPENDED' );
      expect( s.windows[ 'A' ]!.map( ( m ) => m.item.id ).toList(),
          [ 'a1', 'a2', 'aL', 'a3' ],
          reason: 'order kept, missed message appended, deduped by id' );
      expect( s.windows[ 'B' ]!.map( ( m ) => m.item.id ).toList(), [ 'b1' ] );
      expect( s.unreadBySender[ 'A' ], 2,
          reason: 'preserved (not zeroed) + incremented for the merged missed message' );
      expect( s.unreadBySender[ 'B' ], 0, reason: 'focused sender stays read' );
      expect( s.focusedSender, 'B', reason: 'focus unchanged by refresh' );
    } );

    test( 'F-S2-IMPL-1 — live arrival during the cold-start fetch survives the emit (no orphaned window)', () async {
      final gate = Completer<List<SenderSummary>>();
      when( () => repo.senders( any(), hours: any( named: 'hours' ) ) )
          .thenAnswer( ( _ ) => gate.future );

      bloc!.add( const FocusColdStartRequested( userEmail: 'rick@test.com' ) );
      await pump();

      bloc!.add( FocusInboundNotification( _item( 'x1', 'LIVE' ) ) );   // mid-flight
      await pump();
      expect( bloc!.state.senderOrder, [ 'LIVE' ] );

      gate.complete( [ _sender( 'A', DateTime( 2026, 6, 12, 12 ) ) ] );
      await pump();

      expect( bloc!.state.senderOrder, [ 'A', 'LIVE' ],
          reason: 'snapshot first, mid-flight arrival appended — not clobbered' );
      expect( bloc!.state.windows[ 'LIVE' ]!.length, 1 );
      expect( bloc!.state.unreadBySender[ 'LIVE' ], 1 );
    } );

    test( 'F-S2-IMPL-1 — inbound during reconnect-refresh awaits survives the final emit (no stale-snapshot clobber)', () async {
      stubSenders( [ _sender( 'A', DateTime( 2026, 6, 12, 12 ) ) ] );
      stubConversation( [ _conv( _wireMsg( 'a1', 'A', ts: '2026-06-12T01:00:00' ) ) ] );
      bloc!.add( const FocusColdStartRequested( userEmail: 'rick@test.com' ) );
      await pump();
      bloc!.add( const FocusSenderSelected( 'A' ) );   // hydrate + focus A
      await pump();

      // Refresh with the per-sender fetch HELD OPEN.
      final gate = Completer<List<ConversationMessage>>();
      when( () => repo.conversation(
        'A', any(),
        hours  : any( named: 'hours'  ),
        anchor : any( named: 'anchor' ),
      ) ).thenAnswer( ( _ ) => gate.future );
      bloc!.add( const FocusColdStartRequested( userEmail: 'rick@test.com' ) );
      await pump();   // refresh parked inside its awaits

      bloc!.add( FocusInboundNotification( _item( 'n1', 'NEW' ) ) );
      bloc!.add( FocusInboundNotification(
          _item( 'aMid', 'A', ts: DateTime( 2026, 6, 12, 2 ) ) ) );
      await pump();
      expect( bloc!.state.unreadBySender[ 'NEW' ], 1 );

      gate.complete( [
        _conv( _wireMsg( 'a1', 'A', ts: '2026-06-12T01:00:00' ) ),
        _conv( _wireMsg( 'a2', 'A', ts: '2026-06-12T01:30:00' ) ),   // missed while away
      ] );
      await pump();

      final s = bloc!.state;
      expect( s.senderOrder, [ 'A', 'NEW' ],
          reason: 'mid-flight sender survives the final emit' );
      expect( s.windows[ 'NEW' ]!.map( ( m ) => m.item.id ).toList(), [ 'n1' ] );
      expect( s.unreadBySender[ 'NEW' ], 1, reason: 'mid-flight unread survives' );
      expect( s.windows[ 'A' ]!.map( ( m ) => m.item.id ).toList(),
          [ 'a1', 'aMid', 'a2' ],
          reason: 'mid-flight append AND merged missed message both present' );
      expect( s.unreadBySender[ 'A' ], 0, reason: 'A is focused' );
    } );

    test( 'persona updates — assigned stores badge data, released clears it', () async {
      final persona = VoicePersona.fromJson( { 'name': 'Tiffany', 'voice_id': 'vx9' } );
      bloc!.add( FocusPersonaUpdated( senderId: 'S', persona: persona ) );
      await pump();
      expect( bloc!.state.personasBySender[ 'S' ], isNotNull );

      bloc!.add( const FocusPersonaUpdated( senderId: 'S' ) );
      await pump();
      expect( bloc!.state.personasBySender[ 'S' ], isNull );
    } );
  } );
}
