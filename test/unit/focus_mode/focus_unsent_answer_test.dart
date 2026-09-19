/// Row b00e076c (phone half of lupin e4dc53a9, card 2411f68e, 2026-09-18):
/// Rick answered a card while the phone was offline. The answer was POSTed
/// once, failed, and vanished — not sent, not queued, and the card never said
/// so. Chloé's evidence: it never reached :7999.
///
/// Now the answer stays on its card as "not sent", can be resent with a tap,
/// is resent automatically on reconnect while the ask is open, and a card the
/// server closed meanwhile says the answer was not sent.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_bloc.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_event.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_state.dart';
import 'package:lupin_mobile/features/notifications/data/ask_resolution.dart';
import 'package:lupin_mobile/features/notifications/data/notification_models.dart';
import 'package:lupin_mobile/features/notifications/data/notification_repository.dart';
import 'package:lupin_mobile/services/tts/tts_orchestrator.dart';

class _MockRepo extends Mock implements NotificationRepository {}
class _MockTts  extends Mock implements TtsOrchestrator {}
class _FakePayload extends Fake implements NotificationResponsePayload {}

const String _sender = 'claude.code@lupin-mobile.deepily.ai#fe56dccd';

NotificationItem _ask( String id ) => NotificationItem(
  id                     : id,
  message                : 'Beside or below?',
  type                   : 'task',
  priority               : 'high',
  senderId               : _sender,
  timestamp              : DateTime( 2026, 9, 18, 22, 34 ),
  played                 : true,
  playCount              : 0,
  responseRequested      : true,
  responseType           : 'multiple_choice',
  suppressDing           : true,
  displayQualifierWidget : false,
);

ConversationMessage _wire( String id, String state ) => ConversationMessage.fromJson( {
  'id'                 : id,
  'sender_id'          : _sender,
  'message'            : 'Beside or below?',
  'type'               : 'task',
  'priority'           : 'high',
  'state'              : state,
  'response_requested' : true,
  'response_type'      : 'multiple_choice',
  'timestamp'          : '2026-09-18T22:34:00',
} );

/// What Dio produces with no network: no status code at all.
const _offline = NotificationApiException( 'Notify response failed: connection error' );

void main() {
  setUpAll( () => registerFallbackValue( _FakePayload() ) );

  late _MockRepo repo;
  late _MockTts  tts;
  late int       failuresLeft;
  late List<NotificationResponsePayload> sent;
  FocusChatBloc? bloc;

  Future<void> pump() => Future<void>.delayed( const Duration( milliseconds: 10 ) );

  FocusMessage card() => bloc!.state.windows[ _sender ]!.firstWhere( ( m ) => m.item.id == 'a1' );

  Future<void> answerWhileOffline( String text ) async {
    bloc!.add( FocusRespondRequested(
      senderId      : _sender,
      text          : text,
      promptContext : const FocusPromptContext( notificationId: 'a1', promptType: 'multiple_choice' ),
    ) );
    await pump();
  }

  setUp( () async {
    repo         = _MockRepo();
    tts          = _MockTts();
    failuresLeft = 1;
    sent         = [];
    when( () => tts.enqueueAlways(
      priority : any( named: 'priority' ),
      message  : any( named: 'message'  ),
      title    : any( named: 'title'    ),
      voiceId  : any( named: 'voiceId'  ),
      sender   : any( named: 'sender'   ),
      verbatim : any( named: 'verbatim' ),
    ) ).thenReturn( null );
    when( () => repo.respond( any() ) ).thenAnswer( ( inv ) async {
      if ( failuresLeft > 0 ) {
        failuresLeft--;
        throw _offline;
      }
      sent.add( inv.positionalArguments.first as NotificationResponsePayload );
      return NotificationResponseAck.fromJson( { 'status': 'ok', 'notification_id': 'a1' } );
    } );
    when( () => repo.sendersVisible( any(), hours: any( named: 'hours' ) ) ).thenAnswer( ( _ ) async => const [] );
    when( () => repo.activeSessions() ).thenAnswer( ( _ ) async => const [] );
    when( () => repo.conversation( any(), any(), hours: any( named: 'hours' ) ) ).thenAnswer( ( _ ) async => const [] );

    bloc = FocusChatBloc( repo, tts: tts );
    bloc!.add( const FocusColdStartRequested( userEmail: 'ricardo.felipe.ruiz@gmail.com' ) );
    await pump();
    bloc!.add( FocusInboundNotification( _ask( 'a1' ) ) );
    await pump();
  } );

  tearDown( () async => bloc?.close() );

  test( 'an answer that fails to send stays ON the card as not sent — it is not dropped', () async {
    await answerWhileOffline( 'Viewer toggle' );

    expect( card().unsentAnswer, 'Viewer toggle' );
    expect( card().answered,     isFalse, reason: 'still open: it can still be answered' );
    expect( sent,                isEmpty );
  } );

  test( 'resending delivers it and clears the not-sent mark', () async {
    await answerWhileOffline( 'Viewer toggle' );
    await answerWhileOffline( 'Viewer toggle' );   // the card's "tap to resend"

    expect( sent.single.responseValue,  'Viewer toggle' );
    expect( sent.single.notificationId, 'a1' );
    expect( card().answered,     isTrue );
    expect( card().unsentAnswer, isNull );
  } );

  test( 'on reconnect, an unsent answer to a still-open ask is sent by itself', () async {
    await answerWhileOffline( 'Viewer toggle' );
    when( () => repo.conversation( any(), any(), hours: any( named: 'hours' ) ) )
        .thenAnswer( ( _ ) async => [ _wire( 'a1', 'delivered' ) ] );

    bloc!.add( const FocusColdStartRequested( userEmail: 'ricardo.felipe.ruiz@gmail.com' ) );   // WS re-auth
    await pump();
    await pump();

    expect( sent.single.responseValue, 'Viewer toggle' );
    expect( card().answered,     isTrue );
    expect( card().unsentAnswer, isNull );
  } );

  test( 'an ask that EXPIRED while offline is not resent, and keeps the answer so the card can say so', () async {
    await answerWhileOffline( 'Viewer toggle' );
    bloc!.add( const FocusAskExpired( notificationId: 'a1', defaultUsed: 'none' ) );
    await pump();

    bloc!.add( const FocusColdStartRequested( userEmail: 'ricardo.felipe.ruiz@gmail.com' ) );
    await pump();
    await pump();

    expect( sent,                 isEmpty, reason: 'a dead ask is never answered late' );
    expect( card().resolution,    AskResolution.expired );
    expect( card().unsentAnswer,  'Viewer toggle' );
  } );

  test( 'an ask the server closed while offline (seen on refresh) is not resent either', () async {
    await answerWhileOffline( 'Viewer toggle' );
    when( () => repo.conversation( any(), any(), hours: any( named: 'hours' ) ) )
        .thenAnswer( ( _ ) async => [ _wire( 'a1', 'expired' ) ] );
    bloc!.add( const FocusSenderSelected( _sender ) );   // backfill marks it answered-by-the-server
    await pump();

    bloc!.add( const FocusColdStartRequested( userEmail: 'ricardo.felipe.ruiz@gmail.com' ) );
    await pump();
    await pump();

    expect( sent,                isEmpty );
    expect( card().answered,     isTrue );
    expect( card().unsentAnswer, 'Viewer toggle' );
  } );
}
