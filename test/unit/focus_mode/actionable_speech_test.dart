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

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_bloc.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_event.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_state.dart';
import 'package:lupin_mobile/features/notifications/data/notification_models.dart';
import 'package:lupin_mobile/features/notifications/data/notification_repository.dart';
import 'package:lupin_mobile/services/notification_audio/notification_audio_service.dart';
import 'package:lupin_mobile/services/notification_audio/notification_preferences.dart';
import 'package:lupin_mobile/services/notification_filter/notification_stop_list.dart';
import 'package:lupin_mobile/services/tts/streaming_tts_player.dart';
import 'package:lupin_mobile/services/websocket/websocket_service.dart';
import 'package:lupin_mobile/services/tts/speech_intent.dart';
import 'package:lupin_mobile/services/tts/tts_orchestrator.dart';

class _MockRepo extends Mock implements NotificationRepository {}
class _MockTts  extends Mock implements TtsOrchestrator {}
class _MockPlayer   extends Mock implements StreamingTtsPlayer {}
class _MockFallback extends Mock implements NotificationAudioService {}
class _MockWs       extends Mock implements WebSocketService {}

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
  late _MockPlayer   _lastPlayer;
  late _MockFallback _lastFallback;

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


  /// A REAL orchestrator sharing the SAME stop list as the bloc.
  ///
  /// Needed because `suppressedRule` is no longer set by the bloc from its
  /// own match — it is the orchestrator's OWN record, returned by gate 1
  /// and retained. A mock that returns null would make the field null and
  /// the assertion vacuous, so the test that checks the rule must drive the
  /// thing that produces it.
  Future<TtsOrchestrator> realOrchestrator( List<TtsSuppression> seen ) async {
    final player   = _MockPlayer();
    final fallback = _MockFallback();
    final ws       = _MockWs();
    final complete = StreamController<TtsCompleteEvent>.broadcast();
    final errors   = StreamController<TtsErrorEvent>.broadcast();
    when( () => player.completeStream ).thenAnswer( ( _ ) => complete.stream );
    when( () => player.errorStream    ).thenAnswer( ( _ ) => errors.stream );
    when( () => player.isPlaying      ).thenReturn( false );
    when( () => player.stop()         ).thenAnswer( ( _ ) async {} );
    when( () => player.speak(
      text      : any( named: 'text'      ),
      sessionId : any( named: 'sessionId' ),
      voiceId   : any( named: 'voiceId'   ),
    ) ).thenAnswer( ( _ ) async {} );
    when( () => fallback.flutterTtsSpeak( any() ) ).thenAnswer( ( _ ) async {} );
    when( () => fallback.stopFallbackSpeech()     ).thenAnswer( ( _ ) async {} );
    when( () => ws.sessionId ).thenReturn( 'wise penguin' );

    _lastPlayer = player;
    _lastFallback = fallback;
    final o = TtsOrchestrator(
      player   : player,
      fallback : fallback,
      prefs    : NotificationPreferences( await SharedPreferences.getInstance() ),
      ws       : ws,
      stopList : stopList,
    );
    o.suppressedStream.listen( seen.add );
    return o;
  }

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
      final seen = <TtsSuppression>[];
      final real = await realOrchestrator( seen );
      final b = FocusChatBloc( repo, tts: real, stopList: stopList );
      b.add( const FocusSenderScopeChanged( FocusSenderScope.all ) );
      b.add( FocusInboundNotification( _item(
        id: 'n5', sender: askFlowSenderId, message: mutedQuestion, ask: true ) ) );
      await Future<void>.delayed( Duration.zero );

      final window = b.state.windows[ askFlowSenderId ];
      expect( window, hasLength( 1 ), reason: 'not dropped at ingest' );
      expect( window!.single.suppressedRule, rule,
              reason: 'the UI must be able to NAME what muted it' );
      expect( window.single.suppression, isNotNull,
              reason: 'the orchestrator\'s OWN record is retained, so '
                      'speak-anyway replays what was refused' );
      expect( b.state.pendingPromptFor( askFlowSenderId )?.item.id, 'n5',
              reason: 'the answer affordance survives — the server is blocked '
                      'on this reply' );
      await b.close();
      await real.dispose();
    } );

    test( 'AC-S4.14 — speak-anyway hands the orchestrator back its OWN '
          'refused object, and it plays', () async {
      final seen = <TtsSuppression>[];
      final real = await realOrchestrator( seen );
      final b = FocusChatBloc( repo, tts: real, stopList: stopList );
      b.add( const FocusSenderScopeChanged( FocusSenderScope.all ) );
      b.add( FocusInboundNotification( _item(
        id: 'n9', sender: askFlowSenderId, message: mutedQuestion, ask: true ) ) );
      await Future<void>.delayed( Duration.zero );

      verifyNever( () => _lastPlayer.speak(
        text      : any( named: 'text'      ),
        sessionId : any( named: 'sessionId' ),
        voiceId   : any( named: 'voiceId'   ),
      ) );

      b.add( const FocusSpeakAnywayRequested( 'n9' ) );
      await Future<void>.delayed( Duration.zero );

      final spoken = verify( () => _lastPlayer.speak(
        text      : captureAny( named: 'text' ),
        sessionId : any( named: 'sessionId' ),
        voiceId   : any( named: 'voiceId'   ),
      ) ).captured;
      expect( spoken.single, contains( mutedQuestion ),
              reason: 'one tap speaks the thing that was refused, in full' );

      await b.close();
      await real.dispose();
    } );

    test( 'it is NOT spoken — and the muting is done by GATE 1, against a '
          'REAL orchestrator, not by skipping the call', () async {
      // Asserted against a real TtsOrchestrator sharing the SAME stop list,
      // because "not spoken" is a claim about the PLAYER, not about whether
      // a method was invoked. The bloc calls `enqueueAlways` deliberately
      // (Arnold's finding): an early return muted the item equally well and
      // meant gate 1 never fired, so no TtsSuppression was ever emitted and
      // AC-S4.15's seam spanned a wire that did not exist.
      final player   = _MockPlayer();
      final fallback = _MockFallback();
      final ws       = _MockWs();
      final complete = StreamController<TtsCompleteEvent>.broadcast();
      final errors   = StreamController<TtsErrorEvent>.broadcast();
      when( () => player.completeStream ).thenAnswer( ( _ ) => complete.stream );
      when( () => player.errorStream    ).thenAnswer( ( _ ) => errors.stream );
      when( () => player.isPlaying      ).thenReturn( false );
      when( () => player.stop()         ).thenAnswer( ( _ ) async {} );
      when( () => player.speak(
        text      : any( named: 'text'      ),
        sessionId : any( named: 'sessionId' ),
        voiceId   : any( named: 'voiceId'   ),
      ) ).thenAnswer( ( _ ) async {} );
      when( () => fallback.flutterTtsSpeak( any() ) ).thenAnswer( ( _ ) async {} );
      when( () => fallback.stopFallbackSpeech()     ).thenAnswer( ( _ ) async {} );
      when( () => ws.sessionId ).thenReturn( 'wise penguin' );

      final real = TtsOrchestrator(
        player   : player,
        fallback : fallback,
        prefs    : NotificationPreferences( await SharedPreferences.getInstance() ),
        ws       : ws,
        stopList : stopList,          // THE SAME instance the bloc holds
      );
      final suppressions = <TtsSuppression>[];
      final sub = real.suppressedStream.listen( suppressions.add );

      final b = FocusChatBloc( repo, tts: real, stopList: stopList );
      b.add( const FocusSenderScopeChanged( FocusSenderScope.all ) );
      b.add( FocusInboundNotification( _item(
        id: 'n6', sender: askFlowSenderId, message: mutedQuestion, ask: true ) ) );
      await Future<void>.delayed( Duration.zero );

      // Nothing was SPOKEN — the claim that matters to the user.
      verifyNever( () => player.speak(
        text      : any( named: 'text'      ),
        sessionId : any( named: 'sessionId' ),
        voiceId   : any( named: 'voiceId'   ),
      ) );
      verifyNever( () => fallback.flutterTtsSpeak( any() ) );
      expect( real.queueDepth, 0 );

      // …and the suppression was REPORTED, which is what gives AC-S4.14 a
      // real object to offer speak-anyway on.
      expect( suppressions, hasLength( 1 ) );
      expect( suppressions.single.rule, rule );
      expect( suppressions.single.message, mutedQuestion );

      await sub.cancel();
      await b.close();
      await real.dispose();
      await complete.close();
      await errors.close();
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
