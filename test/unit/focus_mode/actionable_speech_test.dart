/// AC-S3.6, AC-S3.6b, AC-S3.8 at the INGEST path — `FocusChatBloc`.
///
/// A separate file from `focus_chat_bloc_test.dart` on purpose: that file
/// is frozen by AC-S4.10a (`git diff --exit-code`), and these are new
/// behaviors, not re-baselined old ones. The verification table routes
/// AC-S3.6/S3.6b/S3.8 to the orchestrator test; the orchestrator cannot see
/// the bloc's ingest drop, which is where Rick's ruling actually lands, so
/// the bloc-level halves are asserted here and the pure predicate in
/// `test/unit/services/tts/speech_intent_test.dart`. The AC wins over the
/// map — the map's own preamble says so.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_bloc.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_event.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_state.dart';
import 'package:lupin_mobile/features/notifications/data/notification_models.dart';
import 'package:lupin_mobile/features/notifications/data/notification_repository.dart';
import 'package:lupin_mobile/services/notification_filter/notification_stop_list.dart';
import 'package:lupin_mobile/services/tts/speech_intent.dart';
import 'package:lupin_mobile/services/tts/tts_orchestrator.dart';

class _MockRepo extends Mock implements NotificationRepository {}
class _MockTts  extends Mock implements TtsOrchestrator {}

NotificationItem _item( {
  required String id,
  required String sender,
  String  message = 'ordinary chatter',
  bool    ask     = false,
  String? jobId,
} ) => NotificationItem(
  id                     : id,
  message                : message,
  type                   : 'task',
  priority               : 'medium',
  senderId               : sender,
  timestamp              : DateTime( 2026, 8, 29, 20 ),
  played                 : false,
  playCount              : 0,
  responseRequested      : ask,
  suppressDing           : false,
  displayQualifierWidget : false,
  jobId                  : jobId,
);

void main() {
  late _MockRepo repo;
  late _MockTts  tts;
  late NotificationStopList stopList;

  /// The pattern under test, and a message that starts with it.
  const rule           = 'Done: Bash';
  const mutedQuestion  = 'Done: Bash — is that the same as your earlier ask?';

  setUp( () async {
    SharedPreferences.setMockInitialValues( {} );
    stopList = NotificationStopList( await SharedPreferences.getInstance() );
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

  FocusChatBloc build( { bool Function( String )? isQuickAskJob } ) {
    final b = FocusChatBloc( repo, tts: tts,
                             stopList: stopList, isQuickAskJob: isQuickAskJob );
    b.add( const FocusSenderScopeChanged( FocusSenderScope.all ) );
    return b;
  }

  /// The `verbatim` argument of the single enqueue that happened.
  bool capturedVerbatim() => verify( () => tts.enqueueAlways(
    priority : any( named: 'priority' ),
    message  : any( named: 'message'  ),
    title    : any( named: 'title'    ),
    voiceId  : any( named: 'voiceId'  ),
    sender   : any( named: 'sender'   ),
    verbatim : captureAny( named: 'verbatim' ),
  ) ).captured.single as bool;

  group( 'AC-S3.6 / AC-S3.6b — questions speak VERBATIM', () {
    test( 'a response_requested question is enqueued verbatim', () async {
      final b = build();
      b.add( FocusInboundNotification( _item(
        id: 'n1', sender: askFlowSenderId, message: 'Is that the same as…?', ask: true ) ) );
      await Future<void>.delayed( Duration.zero );

      expect( capturedVerbatim(), isTrue );
      await b.close();
    } );

    test( 'AC-S3.6b — a Door A interview question (no response_requested, no '
          'job_id) is ALSO verbatim', () async {
      final b = build();
      b.add( FocusInboundNotification( _item(
        id: 'n2', sender: askFlowSenderId, message: 'Which city?' ) ) );
      await Future<void>.delayed( Duration.zero );

      expect( capturedVerbatim(), isTrue,
              reason: 'a predicate keyed only on response_requested loses '
                      'every turn of the ruling-5 interview' );
      await b.close();
    } );

    test( 'AC-S3.8(1) — this is the WHOLE focus surface, not a Quick Ask '
          'special case: no ask job in flight and it still speaks in full', () async {
      final b = build( isQuickAskJob: ( _ ) => false );
      b.add( FocusInboundNotification( _item(
        id: 'n3', sender: 'someone.else@lupin.deepily.ai',
        message: 'Deploy now?', ask: true ) ) );
      await Future<void>.delayed( Duration.zero );

      expect( capturedVerbatim(), isTrue );
      await b.close();
    } );

    test( 'ordinary chatter is NOT verbatim — the preference gates still '
          'govern everything nobody is waiting on', () async {
      final b = build();
      b.add( FocusInboundNotification( _item( id: 'n4', sender: 'peer@x' ) ) );
      await Future<void>.delayed( Duration.zero );

      expect( capturedVerbatim(), isFalse );
      await b.close();
    } );
  } );

  group( 'AC-S3.8(2) — a stop-listed item the user must ACT ON is shown, '
         'marked, and still not spoken', () {
    test( 'the question is STORED, carries the matched rule, and keeps its '
          'answer affordance', () async {
      final b = build();
      b.add( FocusInboundNotification( _item(
        id: 'n5', sender: askFlowSenderId, message: mutedQuestion, ask: true ) ) );
      await Future<void>.delayed( Duration.zero );

      final window = b.state.windows[ askFlowSenderId ];
      expect( window, hasLength( 1 ), reason: 'not dropped at ingest' );
      expect( window!.single.suppressedRule, rule,
              reason: 'the UI must be able to NAME what muted it' );
      expect( b.state.pendingPromptFor( askFlowSenderId )?.item.id, 'n5',
              reason: 'the answer affordance survives — the server is blocked '
                      'on this reply' );
      await b.close();
    } );

    test( 'it is NOT spoken — Rick kept the mute half explicitly', () async {
      final b = build();
      b.add( FocusInboundNotification( _item(
        id: 'n6', sender: askFlowSenderId, message: mutedQuestion, ask: true ) ) );
      await Future<void>.delayed( Duration.zero );

      verifyNever( () => tts.enqueueAlways(
        priority : any( named: 'priority' ),
        message  : any( named: 'message'  ),
        title    : any( named: 'title'    ),
        voiceId  : any( named: 'voiceId'  ),
        sender   : any( named: 'sender'   ),
        verbatim : any( named: 'verbatim' ),
      ) );
      await b.close();
    } );

    test( 'EVERYTHING ELSE the stop-list hides stays hidden, byte for byte: '
          'not stored, not spoken, counted', () async {
      final b = build();
      b.add( FocusInboundNotification( _item(
        id: 'n7', sender: 'peer@x', message: 'Done: Bash ls -la' ) ) );
      await Future<void>.delayed( Duration.zero );

      expect( b.state.windows[ 'peer@x' ] ?? const [], isEmpty,
              reason: 'ordinary stop-listed chatter is still dropped at ingest' );
      expect( b.state.hiddenCountBySender[ 'peer@x' ], 1 );
      verifyNever( () => tts.enqueueAlways(
        priority : any( named: 'priority' ),
        message  : any( named: 'message'  ),
        title    : any( named: 'title'    ),
        voiceId  : any( named: 'voiceId'  ),
        sender   : any( named: 'sender'   ),
        verbatim : any( named: 'verbatim' ),
      ) );
      await b.close();
    } );

    test( 'a NON-matching question is untouched: stored with no rule, and '
          'spoken', () async {
      final b = build();
      b.add( FocusInboundNotification( _item(
        id: 'n8', sender: askFlowSenderId, message: 'Which city?', ask: true ) ) );
      await Future<void>.delayed( Duration.zero );

      expect( b.state.windows[ askFlowSenderId ]!.single.suppressedRule, isNull );
      expect( capturedVerbatim(), isTrue );
      await b.close();
    } );
  } );
}
