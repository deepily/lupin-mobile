/// AC-S4.4, AC-S4.9 — an ask that ended WITHOUT our answer.
///
/// Two doors report the same two endings (AC-S4.13 is the resume-door half,
/// classified through the same vocabulary and asserted here alongside its
/// twin so the pair cannot drift).
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

ConversationMessage _wire( { required String id, required String state } ) =>
    ConversationMessage(
      id                : id,
      senderId          : 'S',
      message           : 'Proceed?',
      type              : 'task',
      priority          : 'medium',
      state             : state,
      isHidden          : false,
      responseRequested : true,
      responseType      : 'yes_no',
      timestamp         : DateTime( 2026, 8, 29, 20 ),
      raw               : {
        'id'                 : id,
        'message'            : 'Proceed?',
        'type'               : 'task',
        'priority'           : 'medium',
        'sender_id'          : 'S',
        'timestamp'          : '2026-08-29T20:00:00',
        'response_requested' : true,
        'response_type'      : 'yes_no',
        'suppress_ding'      : false,
      },
    );

NotificationItem _ask( String id ) => NotificationItem(
  id                     : id,
  message                : 'Proceed?',
  type                   : 'task',
  priority               : 'medium',
  senderId               : 'S',
  timestamp              : DateTime( 2026, 8, 29, 20 ),
  played                 : false,
  playCount              : 0,
  responseRequested      : true,
  responseType           : 'yes_no',
  suppressDing           : false,
  displayQualifierWidget : false,
);

void main() {
  setUpAll( () => registerFallbackValue( _FakePayload() ) );

  group( 'AC-S4.4 — an EXPIRED row counts as answered', () {
    test( 'expired ⇒ answered, so pendingPromptFor stops returning it', () {
      final expired = FocusMessage.fromConversation(
        _wire( id: 'e1', state: 'expired' ) );
      expect( expired.answered, isTrue,
              reason: 'the server already substituted its response_default; '
                      'there is nothing left to answer' );

      final st = const FocusChatState.initial().copyWith(
        senderOrder : const [ 'S' ],
        windows     : { 'S': [ expired ] },
      );
      expect( st.pendingPromptFor( 'S' ), isNull,
              reason: 'a dead ask at the head of the queue makes the composer '
                      'aim every voice reply at it and take a 400' );
    } );

    test( 'the other two answered-states are unchanged', () {
      expect( FocusMessage.fromConversation(
        _wire( id: 'r1', state: 'responded' ) ).answered, isTrue );
      expect( FocusMessage.fromConversation(
        _wire( id: 'd1', state: 'delivered' ) ).answered, isFalse );
    } );

    test( 'a still-live ask IS returned — the filter did not swallow '
          'everything', () {
      final live = FocusMessage.fromConversation(
        _wire( id: 'l1', state: 'delivered' ) );
      final st = const FocusChatState.initial().copyWith(
        senderOrder : const [ 'S' ],
        windows     : { 'S': [ live ] },
      );
      expect( st.pendingPromptFor( 'S' )?.item.id, 'l1' );
    } );
  } );

  group( 'AC-S4.9 — two 400s are ENDINGS, not errors', () {
    late _MockRepo repo;
    late _MockTts  tts;

    FocusChatBloc build() {
      final b = FocusChatBloc( repo, tts: tts );
      b.add( const FocusSenderScopeChanged( FocusSenderScope.all ) );
      b.add( FocusInboundNotification( _ask( 'a1' ) ) );
      return b;
    }

    setUp( () {
      repo = _MockRepo();
      tts  = _MockTts();
      when( () => tts.enqueueAlways(
        priority : any( named: 'priority' ),
        message  : any( named: 'message'  ),
        title    : any( named: 'title'    ),
        voiceId  : any( named: 'voiceId'  ),
        sender   : any( named: 'sender'   ),
        verbatim : any( named: 'verbatim' ),
      ) ).thenReturn( null );
    } );

    Future<FocusChatBloc> respondFailing( String detail ) async {
      when( () => repo.respond( any() ) ).thenThrow(
        NotificationApiException( detail, statusCode: 400 ) );
      final b = build();
      await Future<void>.delayed( Duration.zero );
      b.add( const FocusRespondRequested( senderId: 'S', text: 'yes' ) );
      await Future<void>.delayed( Duration.zero );
      return b;
    }

    test( '"already responded" resolves the card as answered ELSEWHERE', () async {
      final b = await respondFailing( 'Notification already responded' );
      final msg = b.state.windows[ 'S' ]!.firstWhere( ( m ) => m.item.id == 'a1' );

      expect( msg.answered, isTrue );
      expect( msg.resolution, AskResolution.answeredElsewhere );
      expect( b.state.hydration, isNot( FocusHydration.error ),
              reason: 'a finished ask is not a broken surface' );
      await b.close();
    } );

    test( '"grace period exceeded" resolves the card as EXPIRED', () async {
      final b = await respondFailing( 'Grace period exceeded for this ask' );
      final msg = b.state.windows[ 'S' ]!.firstWhere( ( m ) => m.item.id == 'a1' );

      expect( msg.resolution, AskResolution.expired );
      expect( b.state.hydration, isNot( FocusHydration.error ) );
      await b.close();
    } );

    test( 'a GENUINE failure still surfaces as an error — the branch did not '
          'swallow real breakage', () async {
      final b = await respondFailing( 'Internal server error' );
      expect( b.state.hydration, FocusHydration.error );
      await b.close();
    } );
  } );

  group( 'AC-S4.13 — the resume door\'s twins, same vocabulary', () {
    test( 'pending_expired and already_resumed classify DISTINCTLY', () {
      expect( classifyResumeStatus( 'pending_expired' ), AskResolution.expired );
      expect( classifyResumeStatus( 'already_resumed' ), AskResolution.answeredElsewhere );
      expect( classifyResumeStatus( 'something_else' ),  AskResolution.failed );
      expect( classifyResumeStatus( null ),              AskResolution.failed );
    } );

    test( 'each ending says something DIFFERENT to the user — one shared '
          '"something went wrong" card fails this', () {
      expect( AskResolution.expired.userMessage,
              isNot( AskResolution.answeredElsewhere.userMessage ) );
      expect( AskResolution.expired.userMessage.toLowerCase(),
              contains( 'expired' ) );
      expect( AskResolution.answeredElsewhere.userMessage.toLowerCase(),
              contains( 'already answered' ) );
    } );

    test( 'both doors agree: the same two endings, and only those two are '
          'resolved', () {
      expect( classifyRespondFailure( 'already responded' ).isResolved, isTrue );
      expect( classifyRespondFailure( 'grace period exceeded' ).isResolved, isTrue );
      expect( classifyRespondFailure( 'boom' ).isResolved, isFalse );
      expect( classifyResumeStatus( 'pending_expired' ),
              classifyRespondFailure( 'grace period exceeded' ) );
      expect( classifyResumeStatus( 'already_resumed' ),
              classifyRespondFailure( 'already responded' ) );
    } );
  } );
}
