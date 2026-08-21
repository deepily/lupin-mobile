import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_bloc.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_event.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_state.dart';
import 'package:lupin_mobile/features/notifications/data/notification_models.dart';
import 'package:lupin_mobile/features/notifications/data/notification_repository.dart';
import 'package:lupin_mobile/services/tts/tts_orchestrator.dart';
import 'package:lupin_mobile/services/notification_filter/notification_stop_list.dart';
import 'package:shared_preferences/shared_preferences.dart';

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


void stubConversationEmpty( NotificationRepository repo ) {
  when( () => repo.conversation( any(), any(),
      hours: any( named: 'hours' ), anchor: any( named: 'anchor' ) ) )
      .thenAnswer( ( _ ) async => const [] );
}

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
      when( () => repo.sendersVisible( any(), hours: any( named: 'hours' ) ) )
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
      when( () => repo.sendersVisible( any(), hours: any( named: 'hours' ) ) )
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

  // ───────────────────────────────────────────────────────────────────────
  // Visibility lens — 2026.06.25 plan §4 (Live <1h / History <24h), built
  // 2026-08-21 per Rick's rulings: filter = VISIBILITY, not deletion.
  // ───────────────────────────────────────────────────────────────────────
  group( 'FocusChatBloc — visibility lens (Live/24h, exit debounce, persona seeding)', () {
    late _MockRepo repo;
    late _MockTts  tts;
    FocusChatBloc? bloc;
    DateTime clock = DateTime( 2026, 8, 21, 12 );   // injectable "now"

    setUpAll( () {
      registerFallbackValue( const NotificationResponsePayload(
        notificationId : 'fallback',
        responseValue  : 'fallback',
      ) );
    } );

    setUp( () {
      repo  = _MockRepo();
      tts   = _MockTts();
      clock = DateTime( 2026, 8, 21, 12 );
      bloc  = FocusChatBloc(
        repo,
        tts          : tts,
        now          : () => clock,
        exitDebounce : const Duration( milliseconds: 30 ),
      );
      when( () => tts.enqueueAlways(
        priority : any( named: 'priority' ),
        message  : any( named: 'message'  ),
        title    : any( named: 'title'    ),
        voiceId  : any( named: 'voiceId'  ),
      ) ).thenReturn( null );
    } );

    tearDown( () async => bloc?.close() );

    Future<void> pump( [ int ms = 10 ] ) => Future<void>.delayed( Duration( milliseconds: ms ) );

    SenderSummary sv( String id, DateTime? la, { Map<String, dynamic>? persona } ) =>
        SenderSummary.fromJson( {
          'sender_id'     : id,
          'last_activity' : la?.toIso8601String(),
          'count'         : 1,
          'new_count'     : 0,
          'voice_persona' : persona,
        } );

    void stubVisible( List<SenderSummary> result ) {
      when( () => repo.sendersVisible( any(), hours: any( named: 'hours' ) ) )
          .thenAnswer( ( _ ) async => result );
    }

    test( 'cold start fetches senders-visible bounded to 24h, seeds lastActivity + personas + asOf', () async {
      stubVisible( [
        sv( 'live@x#a',  clock.subtract( const Duration( minutes: 5 ) ),
            persona: { 'name': 'Tiffany', 'icon': '💍', 'voice_id': 'v1' } ),
        sv( 'hist@x#b',  clock.subtract( const Duration( hours: 3 ) ) ),
        sv( 'noact@x',   null ),
      ] );

      bloc!.add( const FocusColdStartRequested( userEmail: 'rick@test.com' ) );
      await pump();

      verify( () => repo.sendersVisible( 'rick@test.com', hours: FocusChatBloc.sendersHours ) ).called( 1 );
      verifyNever( () => repo.senders( any(), hours: any( named: 'hours' ) ) );
      final st = bloc!.state;
      expect( st.asOf, clock );
      expect( st.lastActivityBySender[ 'live@x#a' ], clock.subtract( const Duration( minutes: 5 ) ) );
      expect( st.lastActivityBySender.containsKey( 'noact@x' ), isFalse );
      expect( st.personasBySender[ 'live@x#a' ]?.icon, '💍',
          reason: 'persona seeded from senders-visible (the cold-start badge gap)' );
      expect( st.personasBySender.containsKey( 'hist@x#b' ), isFalse );
      // Bands + default Live lens
      expect( st.bandFor( 'live@x#a' ), FocusBand.live );
      expect( st.bandFor( 'hist@x#b' ), FocusBand.history );
      expect( st.bandFor( 'noact@x'  ), FocusBand.live, reason: 'unknown activity never blanks the rail' );
      expect( st.filter, FocusFilter.live );
      expect( st.visibleOrder, [ 'live@x#a', 'noact@x' ] );
      expect( st.liveCount, 2 );
      expect( st.historyCount, 3 );
    } );

    test( 'cold-start persona seed does NOT override a live FocusPersonaUpdated already recorded', () async {
      final livePersona = VoicePersona.fromJson( { 'name': 'Rio', 'icon': '⚡' } );
      bloc!.add( FocusPersonaUpdated( senderId: 's#1', persona: livePersona ) );
      await pump();
      stubVisible( [ sv( 's#1', clock, persona: { 'name': 'Stale', 'icon': '🪦' } ) ] );
      bloc!.add( const FocusColdStartRequested( userEmail: 'rick@test.com' ) );
      await pump();
      expect( bloc!.state.personasBySender[ 's#1' ]?.icon, '⚡' );
    } );

    test( 'FocusFilterChanged(history) reveals history-band senders; switching back hides them again (nothing deleted)', () async {
      stubVisible( [
        sv( 'L', clock.subtract( const Duration( minutes: 1 ) ) ),
        sv( 'H', clock.subtract( const Duration( hours: 2 ) ) ),
      ] );
      bloc!.add( const FocusColdStartRequested( userEmail: 'rick@test.com' ) );
      await pump();
      expect( bloc!.state.visibleOrder, [ 'L' ] );

      bloc!.add( const FocusFilterChanged( FocusFilter.history ) );
      await pump();
      expect( bloc!.state.filter, FocusFilter.history );
      expect( bloc!.state.visibleOrder, [ 'L', 'H' ] );

      bloc!.add( const FocusFilterChanged( FocusFilter.live ) );
      await pump();
      expect( bloc!.state.visibleOrder, [ 'L' ] );
      expect( bloc!.state.senderOrder, [ 'L', 'H' ], reason: 'registry retained — visibility only' );
    } );

    test( 'FocusActivityTick ages a live sender into history (asOf advances, no refetch)', () async {
      stubVisible( [ sv( 'A', clock.subtract( const Duration( minutes: 50 ) ) ) ] );
      bloc!.add( const FocusColdStartRequested( userEmail: 'rick@test.com' ) );
      await pump();
      expect( bloc!.state.visibleOrder, [ 'A' ] );

      clock = clock.add( const Duration( minutes: 15 ) );   // now 65 min old
      bloc!.add( const FocusActivityTick() );
      await pump();
      expect( bloc!.state.bandFor( 'A' ), FocusBand.history );
      expect( bloc!.state.visibleOrder, isEmpty );
      expect( bloc!.state.historyCount, 1 );
      verify( () => repo.sendersVisible( any(), hours: any( named: 'hours' ) ) ).called( 1 );

      clock = clock.add( const Duration( hours: 24 ) );     // now stale
      bloc!.add( const FocusActivityTick() );
      await pump();
      expect( bloc!.state.bandFor( 'A' ), FocusBand.stale );
      bloc!.add( const FocusFilterChanged( FocusFilter.history ) );
      await pump();
      expect( bloc!.state.visibleOrder, isEmpty, reason: 'stale is hidden even in History' );
    } );

    test( 'focused sender is ALWAYS visible, even aged out (§4.6 pin invariant)', () async {
      stubVisible( [ sv( 'F', clock.subtract( const Duration( minutes: 10 ) ) ) ] );
      stubConversationEmpty( repo );
      bloc!.add( const FocusColdStartRequested( userEmail: 'rick@test.com' ) );
      await pump();
      bloc!.add( const FocusSenderSelected( 'F' ) );
      await pump();
      clock = clock.add( const Duration( hours: 30 ) );
      bloc!.add( const FocusActivityTick() );
      await pump();
      expect( bloc!.state.bandFor( 'F' ), FocusBand.stale );
      expect( bloc!.state.visibleOrder, [ 'F' ] );
    } );

    test( 'inbound bumps lastActivity to now, refreshes asOf, and re-enters Live', () async {
      stubVisible( [ sv( 'A', clock.subtract( const Duration( hours: 5 ) ) ) ] );
      bloc!.add( const FocusColdStartRequested( userEmail: 'rick@test.com' ) );
      await pump();
      expect( bloc!.state.visibleOrder, isEmpty );

      clock = clock.add( const Duration( minutes: 1 ) );
      bloc!.add( FocusInboundNotification( _item( 'n1', 'A' ) ) );
      await pump();
      expect( bloc!.state.lastActivityBySender[ 'A' ], clock );
      expect( bloc!.state.asOf, clock );
      expect( bloc!.state.visibleOrder, [ 'A' ] );
    } );

    test( 'voice_persona_released arms the exit debounce: silence ⇒ exited (hidden in Live, shown in History)', () async {
      stubVisible( [ sv( 'S', clock ) ] );
      bloc!.add( const FocusColdStartRequested( userEmail: 'rick@test.com' ) );
      await pump();
      bloc!.add( FocusPersonaUpdated( senderId: 'S', persona: VoicePersona.fromJson( { 'name': 'P' } ) ) );
      await pump();
      bloc!.add( const FocusPersonaUpdated( senderId: 'S' ) );   // released
      await pump( 5 );
      expect( bloc!.state.exitedSenders, isEmpty, reason: 'not yet — debounce running' );
      expect( bloc!.state.visibleOrder, [ 'S' ] );
      await pump( 60 );                                           // debounce (30ms) elapses
      expect( bloc!.state.exitedSenders, { 'S' } );
      expect( bloc!.state.visibleOrder, isEmpty );
      expect( bloc!.state.liveCount, 0 );
      bloc!.add( const FocusFilterChanged( FocusFilter.history ) );
      await pump();
      expect( bloc!.state.visibleOrder, [ 'S' ], reason: 'History re-reveals the exited card' );
    } );

    test( 'a re-assign inside the debounce cancels the exit (benign seat hand-back)', () async {
      stubVisible( [ sv( 'S', clock ) ] );
      bloc!.add( const FocusColdStartRequested( userEmail: 'rick@test.com' ) );
      await pump();
      bloc!.add( const FocusPersonaUpdated( senderId: 'S' ) );   // released
      await pump( 5 );
      bloc!.add( FocusPersonaUpdated( senderId: 'S', persona: VoicePersona.fromJson( { 'name': 'P2' } ) ) );
      await pump( 60 );
      expect( bloc!.state.exitedSenders, isEmpty );
      expect( bloc!.state.visibleOrder, [ 'S' ] );
      expect( bloc!.state.personasBySender[ 'S' ]?.name, 'P2' );
    } );

    test( 'an inbound inside the debounce cancels the exit too (a speaking session is alive)', () async {
      stubVisible( [ sv( 'S', clock ) ] );
      bloc!.add( const FocusColdStartRequested( userEmail: 'rick@test.com' ) );
      await pump();
      bloc!.add( const FocusPersonaUpdated( senderId: 'S' ) );
      await pump( 5 );
      bloc!.add( FocusInboundNotification( _item( 'n2', 'S' ) ) );
      await pump( 60 );
      expect( bloc!.state.exitedSenders, isEmpty );
    } );

    test( 'FocusSenderExited (session_reaped) hides immediately; a later inbound un-exits', () async {
      stubVisible( [ sv( 'W', clock ) ] );
      bloc!.add( const FocusColdStartRequested( userEmail: 'rick@test.com' ) );
      await pump();
      bloc!.add( const FocusSenderExited( 'W' ) );
      await pump();
      expect( bloc!.state.exitedSenders, { 'W' } );
      expect( bloc!.state.visibleOrder, isEmpty );
      bloc!.add( FocusInboundNotification( _item( 'n3', 'W' ) ) );
      await pump();
      expect( bloc!.state.exitedSenders, isEmpty );
      expect( bloc!.state.visibleOrder, [ 'W' ] );
    } );

    test( 'reconnect refresh also seeds activity + personas via senders-visible (24h bound)', () async {
      stubVisible( [ sv( 'A', clock ) ] );
      bloc!.add( const FocusColdStartRequested( userEmail: 'rick@test.com' ) );
      await pump();
      stubVisible( [
        sv( 'A', clock.add( const Duration( minutes: 1 ) ), persona: { 'name': 'Ana', 'icon': '🅰' } ),
        sv( 'B', clock ),
      ] );
      bloc!.add( const FocusColdStartRequested( userEmail: 'rick@test.com' ) );   // non-empty ⇒ refresh path
      await pump();
      expect( bloc!.state.senderOrder, [ 'A', 'B' ] );
      expect( bloc!.state.lastActivityBySender[ 'A' ], clock.add( const Duration( minutes: 1 ) ) );
      expect( bloc!.state.personasBySender[ 'A' ]?.icon, '🅰' );
      verify( () => repo.sendersVisible( 'rick@test.com', hours: 24 ) ).called( 2 );
    } );

    test( 'periodic tick timer fires when tickInterval is given, and close() cancels it (no late adds)', () async {
      final b = FocusChatBloc( repo, tts: tts, now: () => clock,
                               tickInterval: const Duration( milliseconds: 15 ) );
      expect( b.state.asOf, isNull );
      await pump( 40 );
      expect( b.state.asOf, clock, reason: 'tick emitted asOf' );
      await b.close();
      await pump( 40 );   // no throw after close
    } );

    test( 'close() cancels a pending exit debounce (no add-after-close)', () async {
      bloc!.add( const FocusPersonaUpdated( senderId: 'S' ) );
      await pump( 5 );
      await bloc!.close();
      await pump( 60 );
      bloc = null;   // tearDown guard
    } );
  } );

  group( 'FocusChatState — pure selectors', () {
    test( 'bandFor: null asOf or unknown activity ⇒ live; boundaries at 1h / 24h', () {
      final at = DateTime( 2026, 8, 21, 12 );
      FocusChatState st( Duration age ) => const FocusChatState.initial().copyWith(
        senderOrder          : const [ 'x' ],
        lastActivityBySender : { 'x': at.subtract( age ) },
        asOf                 : at,
      );
      expect( const FocusChatState.initial().bandFor( 'x' ), FocusBand.live );
      expect( const FocusChatState.initial().copyWith( asOf: at ).bandFor( 'x' ), FocusBand.live );
      expect( st( const Duration( minutes: 59 ) ).bandFor( 'x' ), FocusBand.live );
      expect( st( const Duration( hours: 1 ) ).bandFor( 'x' ), FocusBand.history );
      expect( st( const Duration( hours: 23, minutes: 59 ) ).bandFor( 'x' ), FocusBand.history );
      expect( st( const Duration( hours: 24 ) ).bandFor( 'x' ), FocusBand.stale );
    } );

    test( 'isVisible/visibleOrder/counts honour filter + exited + focused pin; props include the lens fields', () {
      final at = DateTime( 2026, 8, 21, 12 );
      final st = const FocusChatState.initial().copyWith(
        senderOrder          : const [ 'live', 'hist', 'stale', 'exited', 'pinned' ],
        lastActivityBySender : {
          'live'   : at.subtract( const Duration( minutes: 1 ) ),
          'hist'   : at.subtract( const Duration( hours: 2 ) ),
          'stale'  : at.subtract( const Duration( hours: 48 ) ),
          'exited' : at,
          'pinned' : at.subtract( const Duration( hours: 48 ) ),
        },
        exitedSenders : const { 'exited' },
        focusedSender : 'pinned',
        asOf          : at,
      );
      expect( st.visibleOrder, [ 'live', 'pinned' ] );
      expect( st.liveCount, 1 );       // 'live' only — 'exited' is excluded, 'pinned' is stale (the pin is a render rule, not a count)
      expect( st.historyCount, 3 );    // live, hist, exited ('stale' + 'pinned' are >24h)
      final hist = st.copyWith( filter: FocusFilter.history );
      expect( hist.visibleOrder, [ 'live', 'hist', 'exited', 'pinned' ] );
      expect( st.props, contains( FocusFilter.live ) );
      expect( st == st.copyWith( asOf: at.add( const Duration( seconds: 1 ) ) ), isFalse,
          reason: 'asOf is in props so a tick triggers a rebuild' );
    } );
  
  group( 'FocusChatBloc — stop-list seam (plan 2026.08.21 §3: hide + mute at ingest and backfill)', () {
    late _MockRepo repo;
    late _MockTts  tts;
    late NotificationStopList sl;
    FocusChatBloc? bloc;

    setUp( () async {
      SharedPreferences.setMockInitialValues( {} );
      sl   = NotificationStopList( await SharedPreferences.getInstance() );
      repo = _MockRepo();
      tts  = _MockTts();
      bloc = FocusChatBloc( repo, tts: tts, stopList: sl, now: () => DateTime( 2026, 8, 21, 12 ) );
      when( () => tts.enqueueAlways(
        priority : any( named: 'priority' ), message: any( named: 'message' ),
        title    : any( named: 'title' ),    voiceId: any( named: 'voiceId' ),
      ) ).thenReturn( null );
      registerFallbackValue( const NotificationResponsePayload( notificationId: 'f', responseValue: 'f' ) );
    } );
    tearDown( () async => bloc?.close() );
    Future<void> pump() => Future<void>.delayed( const Duration( milliseconds: 10 ) );

    NotificationItem msg( String id, String sender, String text, { String type = 'task' } ) => NotificationItem(
      id: id, message: text, type: type, priority: 'low', senderId: sender,
      timestamp: DateTime( 2026, 8, 21, 11 ), played: false, playCount: 0,
      responseRequested: false, suppressDing: false, displayQualifierWidget: false,
    );

    test( 'suppressed inbound: sender established + activity bumped, but NOT in window, NOT unread, NOT spoken; hiddenCount++', () async {
      bloc!.add( FocusInboundNotification( msg( '1', 'S', 'Done: mcp__cosa-voice__notify' ) ) );
      bloc!.add( FocusInboundNotification( msg( '2', 'S', 'Done: Bash pytest' ) ) );
      bloc!.add( FocusInboundNotification( msg( '3', 'S', 'Suite green 30/30' ) ) );
      await pump();
      final st = bloc!.state;
      expect( st.senderOrder, [ 'S' ] );
      expect( st.lastActivityBySender[ 'S' ], DateTime( 2026, 8, 21, 12 ) );
      expect( st.windows[ 'S' ]!.map( ( m ) => m.item.id ), [ '3' ] );
      expect( st.unreadBySender[ 'S' ], 1 );
      expect( st.hiddenCountBySender[ 'S' ], 2 );
      verify( () => tts.enqueueAlways(
        priority: any( named: 'priority' ), message: 'Suite green 30/30',
        title: any( named: 'title' ), voiceId: any( named: 'voiceId' ) ) ).called( 1 );
      verifyNever( () => tts.enqueueAlways(
        priority: any( named: 'priority' ), message: any( named: 'message', that: startsWith( 'Done:' ) ),
        title: any( named: 'title' ), voiceId: any( named: 'voiceId' ) ) );
    } );

    test( 'the user\'s own reply is never suppressed even if it starts with a pattern', () async {
      bloc!.add( FocusInboundNotification( msg( 'u', 'S', 'Done: Bash — yes, I ran it', type: 'user_initiated_message' ) ) );
      await pump();
      expect( bloc!.state.windows[ 'S' ]!.length, 1 );
      expect( bloc!.state.hiddenCountBySender[ 'S' ], isNull );
    } );

    test( 'backfill on select filters stop-listed rows (alongside is_hidden)', () async {
      when( () => repo.sendersVisible( any(), hours: any( named: 'hours' ) ) ).thenAnswer( ( _ ) async => const [] );
      when( () => repo.conversation( any(), any(), hours: any( named: 'hours' ), anchor: any( named: 'anchor' ) ) )
          .thenAnswer( ( _ ) async => [
            ConversationMessage.fromJson( _wireMsg( 'a', 'S' )..[ 'message' ] = 'Done: ToolSearch select:x' ),
            ConversationMessage.fromJson( _wireMsg( 'b', 'S' )..[ 'message' ] = 'Real answer' ),
            ConversationMessage.fromJson( _wireMsg( 'c', 'S', isHidden: true )..[ 'message' ] = 'server-hidden' ),
          ] );
      bloc!.add( const FocusColdStartRequested( userEmail: 'rick@test.com' ) );
      await pump();
      bloc!.add( const FocusSenderSelected( 'S' ) );
      await pump();
      expect( bloc!.state.windows[ 'S' ]!.map( ( m ) => m.item.id ), [ 'b' ] );
    } );

    test( 'without a stop-list (null) nothing is suppressed — legacy behaviour intact', () async {
      final plain = FocusChatBloc( repo, tts: tts );
      plain.add( FocusInboundNotification( msg( '1', 'S', 'Done: Bash x' ) ) );
      await pump();
      expect( plain.state.windows[ 'S' ]!.length, 1 );
      await plain.close();
    } );
  } );
} );
}
