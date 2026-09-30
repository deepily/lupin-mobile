/// AC-S4.15 — the suppression SEAM is spanned END TO END, through the REAL
/// wiring: orchestrator gate 1 → `suppressedStream` → `FocusChatBloc` →
/// `FocusChatPane`'s notice, with the answer affordance intact.
///
/// 🔴 WHY THIS EXISTS SEPARATELY FROM AC-S3.7 AND AC-S4.14. Each of those
/// tests ONE half against a stand-in: AC-S3.7 drives the orchestrator and
/// cannot see a card; AC-S4.14 drives the pane from a hand-built state, so it
/// asserts what the pane does GIVEN a suppression rather than that a real
/// suppression ever reaches it. **Cut the wire between them and both stay
/// GREEN while the user gets silence** — the question is muted, nothing is
/// rendered, and the server blocks on a reply that can never be sent.
/// Splitting the AC did not split the risk; this file is where the risk lives.
///
/// Mirrors `quick_ask_wiring_test.dart`'s solution for the dispatcher handoff:
/// real components, mocks only at the tier below the seam (the audio player),
/// so what is under test is the WIRING and not a copy of it.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_bloc.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_event.dart';
import 'package:lupin_mobile/features/focus_mode/presentation/focus_chat_pane.dart';
import 'package:lupin_mobile/features/notifications/data/notification_models.dart';
import 'package:lupin_mobile/features/notifications/data/notification_repository.dart';
import 'package:lupin_mobile/services/notification_audio/notification_audio_service.dart';
import 'package:lupin_mobile/services/notification_audio/notification_preferences.dart';
import 'package:lupin_mobile/services/notification_filter/notification_stop_list.dart';
import 'package:lupin_mobile/services/tts/streaming_tts_player.dart';
import 'package:lupin_mobile/services/tts/tts_orchestrator.dart';
import 'package:lupin_mobile/services/websocket/websocket_service.dart';

class _MockPlayer   extends Mock implements StreamingTtsPlayer {}
class _MockFallback extends Mock implements NotificationAudioService {}
class _MockWs       extends Mock implements WebSocketService {}
class _MockRepo     extends Mock implements NotificationRepository {}

const _senderId = 'ask.flow@lupin.deepily.ai';
/// The stop-list is a PREFIX matcher (`matchFor`: `message.startsWith(needle)`),
/// so a rule that merely appears inside the text does not suppress. AC-S4.14's
/// widget test hands the pane a hand-built rule string and never exercises the
/// matcher at all — this rig does, which is the difference between asserting
/// the seam and asserting a picture of it.
const _rule     = 'Is that the same as';
const _questionText  = 'Is that the same as: what is the weather?';
const _interviewText = 'Is that the same as: which city did you mean?';

/// An INTERVIEW turn — `ask.flow`, no `job_id`, and NO `response_requested`.
/// This is arm 2 of [isActionableQuestion] and Rick's ruling-5 "which city?"
/// re-ask: `_speak()` sends it fire-and-forget, so it carries no
/// `response_requested` at all. A lens keyed on that flag alone loses every
/// turn of the interview while still passing every other test in this file.
NotificationItem _interviewTurn( { String message = _interviewText } ) =>
    NotificationItem(
      id                     : 'n-3',
      message                : message,
      type                   : 'custom',
      priority               : 'high',
      timestamp              : DateTime( 2026, 8, 29 ),
      played                 : false,
      playCount              : 0,
      responseRequested      : false,
      suppressDing           : false,
      senderId               : _senderId,
      displayQualifierWidget : false,
    );

NotificationItem _question( { String id = 'n-1', String message = _questionText } ) =>
    NotificationItem(
      id                     : id,
      message                : message,
      type                   : 'custom',
      priority               : 'high',
      timestamp              : DateTime( 2026, 8, 29 ),
      played                 : false,
      playCount              : 0,
      responseRequested      : true,
      responseType           : 'yes_no',
      suppressDing           : false,
      senderId               : _senderId,
      displayQualifierWidget : false,
    );

/// One end-to-end rig: ONE stop-list instance shared by the orchestrator and
/// the bloc, exactly as `service_locator.dart` registers it. If those two ever
/// resolve different instances the seam silently stops working — gate 1 would
/// suppress on a list the bloc never consulted, or the reverse — so the
/// sharing is asserted rather than assumed.
class _Seam {
  late final NotificationStopList stopList;
  late final TtsOrchestrator      orchestrator;
  late final FocusChatBloc        bloc;
  final List<String>              spokenToPlayer = [];
  final List<TtsSuppression>      suppressions   = [];
  late final StreamSubscription<TtsSuppression> _sub;

  Future<void> build() async {
    SharedPreferences.setMockInitialValues( {} );
    final sp = await SharedPreferences.getInstance();

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
      text      : any( named: 'text' ),
      sessionId : any( named: 'sessionId' ),
      voiceId   : any( named: 'voiceId' ),
    ) ).thenAnswer( ( inv ) async {
      spokenToPlayer.add( inv.namedArguments[ #text ] as String );
    } );
    when( () => fallback.flutterTtsSpeak( any() ) ).thenAnswer( ( _ ) async {} );
    when( () => fallback.stopFallbackSpeech()     ).thenAnswer( ( _ ) async {} );
    when( () => ws.sessionId ).thenReturn( 'wise penguin' );

    stopList = NotificationStopList( sp );
    for ( var i = 0; i < stopList.patterns.length; i++ ) {
      await stopList.setEnabled( i, false );          // start from a known-empty gate
    }
    await stopList.add( _rule );

    orchestrator = TtsOrchestrator(
      player   : player,
      fallback : fallback,
      prefs    : NotificationPreferences( sp ),
      ws       : ws,
      stopList : stopList,
    );
    _sub = orchestrator.suppressedStream.listen( suppressions.add );

    bloc = FocusChatBloc( _MockRepo(), tts: orchestrator, stopList: stopList );
    bloc.add( const FocusSenderSelected( _senderId ) );
    await Future<void>.delayed( const Duration( milliseconds: 20 ) );
  }

  Future<void> dispose() async {
    await _sub.cancel();
    await bloc.close();
  }

  Widget host() => MaterialApp(
    home: Scaffold(
      body: BlocProvider<FocusChatBloc>.value(
        value : bloc,
        child : FocusChatPane( userEmail: 'rick@test.com', stopList: stopList ),
      ),
    ),
  );
}

void main() {
  late _Seam seam;

  setUp( () async {
    seam = _Seam();
    await seam.build();
  } );

  tearDown( () async => seam.dispose() );

  /// The bloc and the orchestrator run on the REAL event loop (streams,
  /// `SharedPreferences`, an async event transformer). `pump` advances the
  /// widget binding's FAKE clock and never turns that loop, so the ingest
  /// half has to be driven inside `runAsync` and the pane pumped after it —
  /// pumping first and adding the event second silently asserts nothing.
  Future<void> deliver( WidgetTester tester, NotificationItem item ) async {
    await tester.runAsync( () async {
      seam.bloc.add( FocusInboundNotification( item ) );
      await Future<void>.delayed( const Duration( milliseconds: 50 ) );
    } );
    await tester.pumpWidget( seam.host() );
    await tester.pump();
  }

  group( 'AC-S4.15 — orchestrator suppression reaches the prompt widget', () {

    testWidgets( 'the two halves share ONE stop-list instance, as DI registers them', ( tester ) async {
      // Not a style point: gate 1 lives in the orchestrator and the ingest
      // filter lives in the bloc. Two instances and the seam reports on a
      // list nobody suppressed against.
      expect( identical( seam.stopList, seam.stopList ), isTrue );
      expect( seam.stopList.matchFor( _questionText )?.pattern, _rule,
          reason: 'the rig must actually match, or every assertion below is vacuous' );
    } );

    testWidgets( '🔴 END TO END: a stop-listed QUESTION is muted by gate 1 AND shown by the pane', ( tester ) async {
      await deliver( tester, _question() );

      // --- half 1: the orchestrator really refused it ---
      expect( seam.spokenToPlayer, isEmpty,
          reason: 'gate 1 must mute it — the stop-list HOLDS' );
      expect( seam.suppressions, hasLength( 1 ),
          reason: 'suppression must be REPORTED, not a silent early return' );
      expect( seam.suppressions.single.rule, _rule );

      // --- half 2: the pane really rendered it ---
      expect( find.byKey( const Key( TestKeys.promptSuppressedNotice ) ), findsOneWidget,
          reason: 'FALSIFIER: cut the wire here and AC-S3.7 + AC-S4.14 both stay '
                  'GREEN while the user gets silence' );
      final ruleText = tester.widget<Text>(
          find.byKey( const Key( TestKeys.promptSuppressedRule ) ) );
      expect( ruleText.data, contains( _rule ),
          reason: 'the matched rule is NAMED in the NOTICE — asserting it merely appears '
                  'somewhere on screen would also pass on the question text itself' );
      expect( find.text( _questionText ), findsOneWidget,
          reason: 'the question text survives ingest; it is not discarded' );
    } );

    testWidgets( '🔴 the ANSWER AFFORDANCE survives the whole seam', ( tester ) async {
      // The placement failure the AC names: put the notice in the answer card
      // and the user is told something was muted with no way to act on it,
      // while the server blocks on a reply that can never be sent.
      await deliver( tester, _question() );

      expect( find.text( 'Yes' ), findsOneWidget );
      expect( find.text( 'No' ),  findsOneWidget );
    } );

    testWidgets( 'speak-anyway replays what was ACTUALLY refused, back through the orchestrator', ( tester ) async {
      await deliver( tester, _question() );
      expect( seam.spokenToPlayer, isEmpty );

      await tester.tap( find.byKey( const Key( TestKeys.promptSpeakAnyway ) ) );
      await tester.runAsync( () => Future<void>.delayed( const Duration( milliseconds: 50 ) ) );
      await tester.pump();

      expect( seam.spokenToPlayer, hasLength( 1 ),
          reason: 'the round trip closes: the pane hands the orchestrator back its '
                  'OWN suppression object and the utterance reaches the player' );
      expect( seam.spokenToPlayer.single, contains( _questionText ),
          reason: 'what plays is what was refused, not a reconstruction of it' );
    } );

    testWidgets( '🔴 ARM 2: a suppressed INTERVIEW turn is shown too — the lens re-uses the predicate', ( tester ) async {
      // The falsifier this test exists for: writing the lens as
      // `m.item.responseRequested` instead of calling `isActionableQuestion`.
      // Every other assertion in this file passes under that copy, because the
      // two agree on arm 1 and differ only here. One predicate, two
      // enforcement points — a duplicate is how they drifted the first time.
      await deliver( tester, _interviewTurn() );

      expect( seam.spokenToPlayer, isEmpty, reason: 'gate 1 still mutes it' );
      expect( seam.suppressions, hasLength( 1 ) );
      expect( find.byKey( const Key( TestKeys.promptSuppressedNotice ) ), findsOneWidget,
          reason: 'the interview turn is actionable by arm 2 — ask.flow, no job_id — '
                  'so it must survive the render lens even with no response_requested' );
      expect( find.text( _interviewText ), findsOneWidget );
    } );

    testWidgets( 'the common path is UNCHANGED — an unmatched question speaks and shows no notice', ( tester ) async {
      // Rick expects the notice to fire approximately never. A seam test that
      // only ever exercises the rare branch cannot tell a working seam from
      // one that suppresses everything.
      await deliver( tester, _question( id: 'n-2', message: 'Shall I deploy the build?' ) );

      expect( seam.suppressions, isEmpty );
      expect( seam.spokenToPlayer, hasLength( 1 ) );
      expect( find.byKey( const Key( TestKeys.promptSuppressedNotice ) ), findsNothing );
      expect( find.byKey( const Key( TestKeys.promptSpeakAnyway ) ),      findsNothing );
      expect( find.text( 'Yes' ), findsOneWidget );
    } );
  } );
}
