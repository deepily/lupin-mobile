import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mocktail/mocktail.dart';

import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lupin_mobile/core/build_info.dart';
import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/agentic/domain/agentic_submission_bloc.dart';
import 'package:lupin_mobile/features/agentic/presentation/agentic_hub_screen.dart';
import 'package:lupin_mobile/features/broadcast/domain/broadcast_bloc.dart';
import 'package:lupin_mobile/features/claude_code/domain/claude_code_bloc.dart';
import 'package:lupin_mobile/features/claude_code/presentation/session_list_screen.dart';
import 'package:lupin_mobile/features/finished_tasks/domain/finished_tasks_bloc.dart';
import 'package:lupin_mobile/features/finished_tasks/presentation/finished_tasks_screen.dart';
import 'package:lupin_mobile/features/fleet/presentation/pane_host_screen.dart';
import 'package:lupin_mobile/features/fleet_status/presentation/fleet_status_screen.dart';
import 'package:lupin_mobile/features/holding_area/domain/holding_area_bloc.dart';
import 'package:lupin_mobile/features/settings/presentation/notification_audio_settings_screen.dart';
import 'package:lupin_mobile/features/settings/presentation/notification_filter_settings_screen.dart';
import 'package:lupin_mobile/features/task_list/domain/task_list_bloc.dart';
import 'package:lupin_mobile/services/notification_audio/notification_preferences.dart';
import 'package:lupin_mobile/services/notification_filter/notification_stop_list.dart';
import 'package:lupin_mobile/features/auth/domain/auth_bloc.dart';
import 'package:lupin_mobile/features/auth/domain/auth_event.dart';
import 'package:lupin_mobile/features/auth/domain/auth_state.dart';
import 'package:lupin_mobile/features/auth/presentation/auth_gate.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_bloc.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_event.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_state.dart';
import 'package:lupin_mobile/features/focus_mode/presentation/focus_mode_screen.dart';
import 'package:lupin_mobile/features/focus_mode/presentation/session_rail.dart';
import 'package:lupin_mobile/features/focus_mode/presentation/voice_reply_field.dart';
import 'package:lupin_mobile/features/notifications/data/notification_models.dart';
import 'package:lupin_mobile/features/notifications/domain/notification_bloc.dart';
import 'package:lupin_mobile/features/notifications/domain/notification_event.dart';
import 'package:lupin_mobile/features/notifications/domain/notification_state.dart';
import 'package:lupin_mobile/services/asr/asr_service.dart';
import 'package:lupin_mobile/services/auth/server_context_service.dart';
import 'package:lupin_mobile/services/tts/tts_orchestrator.dart';

class _MockFocusBloc extends MockBloc<FocusChatEvent, FocusChatState>
    implements FocusChatBloc {}
class _MockAuthBloc extends MockBloc<AuthEvent, AuthState>
    implements AuthBloc {}
class _MockNotifBloc extends MockBloc<NotificationEvent, NotificationState>
    implements NotificationBloc {}
class _MockTts extends Mock implements TtsOrchestrator {}
class _MockAsr extends Mock implements AsrService {}
class _MockServerCtx extends Mock implements ServerContextService {}
// Never mounted, never driven — the drawer's builder-level test only needs these
// to EXIST, so `Mock implements` is enough and a MockBloc would be ceremony.
class _MockAgenticBloc   extends Mock implements AgenticSubmissionBloc {}
class _MockClaudeBloc    extends Mock implements ClaudeCodeBloc {}
class _MockBroadcastBloc extends Mock implements BroadcastBloc {}
class _MockPrefs         extends Mock implements NotificationPreferences {}
class _MockStopList      extends Mock implements NotificationStopList {}

NotificationItem _item(
  String id,
  String sender, {
  String  priority = 'medium',
  String  type     = 'task',
  bool    ask      = false,
  String? responseType,
  Map<String, dynamic>? options,
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
  );
}

FocusChatState _st( {
  List<String>                    order    = const [],
  Map<String, List<FocusMessage>> windows  = const {},
  Map<String, int>                unread   = const {},
  String?                         focused,
  FocusHydration                  hydration = FocusHydration.ready,
  Map<String, VoicePersona?>      personas = const {},
  Map<String, DateTime>           activity = const {},
  Set<String>                     exited   = const {},
  FocusFilter                     filter   = FocusFilter.live,
  FocusSenderScope                scope    = FocusSenderScope.all,   // band fixtures are persona-less (§5f)
  DateTime?                       asOf,
  Map<String, int>                hidden   = const {},
} ) {
  return FocusChatState(
    senderOrder          : order,
    personasBySender     : personas,
    windows              : windows,
    unreadBySender       : unread,
    focusedSender        : focused,
    hydration            : hydration,
    lastActivityBySender : activity,
    exitedSenders        : exited,
    filter               : filter,
    senderScope          : scope,
    asOf                 : asOf,
    hiddenCountBySender  : hidden,
  );
}

void main() {
  late _MockFocusBloc focusBloc;
  late _MockAuthBloc  authBloc;
  late _MockNotifBloc notifBloc;
  late _MockTts       tts;
  late _MockAsr       asr;
  late StreamController<bool> pausedCtrl;
  late StreamController<int>  depthCtrl;
  late _MockAgenticBloc       agenticBloc;
  late _MockClaudeBloc        claudeBloc;

  setUpAll( () {
    registerFallbackValue( const FocusSenderSelected( 'fallback' ) );
  } );

  setUp( () {
    focusBloc  = _MockFocusBloc();
    authBloc   = _MockAuthBloc();
    notifBloc  = _MockNotifBloc();
    tts        = _MockTts();
    asr        = _MockAsr();
    pausedCtrl = StreamController<bool>.broadcast();
    depthCtrl  = StreamController<int>.broadcast();
    agenticBloc = _MockAgenticBloc();
    claudeBloc  = _MockClaudeBloc();
    when( () => agenticBloc.stream ).thenAnswer( ( _ ) => const Stream.empty() );
    when( () => claudeBloc.stream  ).thenAnswer( ( _ ) => const Stream.empty() );

    whenListen( authBloc, const Stream<AuthState>.empty(),
        initialState: const AuthAuthenticated(
          userId      : 'u1',
          email       : 'rick@test.com',
          accessToken : 'tok',
        ) );
    whenListen( notifBloc, const Stream<NotificationState>.empty(),
        initialState: const NotificationsInitial() );

    when( () => tts.pausedStream     ).thenAnswer( ( _ ) => pausedCtrl.stream );
    when( () => tts.queueDepthStream ).thenAnswer( ( _ ) => depthCtrl.stream );
    when( () => tts.isPaused         ).thenReturn( false );
    when( () => tts.queueDepth       ).thenReturn( 0 );
  } );

  tearDown( () async {
    await pausedCtrl.close();
    await depthCtrl.close();
  } );

  void seed( FocusChatState state ) {
    // A FRESH mock per seed: re-stubbing whenListen on the same instance
    // does not reach an already-built tree (element reuse keeps BlocBuilder
    // subscribed to the prior stub and it never re-reads `state`); a new
    // provider value forces re-subscription on the next pump.
    focusBloc = _MockFocusBloc();
    whenListen( focusBloc, Stream<FocusChatState>.fromIterable( [ state ] ),
        initialState: state );
  }

  /// [surfaces] is row c59457f0's one switch (ruling R1): null takes the
  /// shipped default, `false` asks for the pre-experiment drawer.
  Widget host( { bool? surfaces } ) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<FocusChatBloc>.value( value: focusBloc ),
        BlocProvider<AuthBloc>.value( value: authBloc ),
        BlocProvider<NotificationBloc>.value( value: notifBloc ),
        // The surfaces drawer reads these two the way home_screen.dart does.
        // ⚠️ `BlocProvider.value` SUBSCRIBES on the first `read`, so a bare mock
        // hands `null` to `stream` and the read throws — stub it, don't just make it.
        BlocProvider<AgenticSubmissionBloc>.value( value: agenticBloc ),
        BlocProvider<ClaudeCodeBloc>.value( value: claudeBloc ),
      ],
      child: MaterialApp(
        home: FocusModeScreen( tts: tts, asr: asr, surfacesExperiment: surfaces ),
      ),
    );
  }

  Finder railBadge( String sid ) =>
      find.byKey( Key( '${TestKeys.focusRailBadgePrefix}$sid' ) );

  group( 'FocusModeScreen (S3)', () {
    testWidgets( 'AC-S3.1 — rail renders badges in senderOrder, top-to-bottom', ( tester ) async {
      seed( _st( order: [ 'B', 'A', 'C' ] ) );
      await tester.pumpWidget( host() );
      await tester.pump();

      final dyB = tester.getTopLeft( railBadge( 'B' ) ).dy;
      final dyA = tester.getTopLeft( railBadge( 'A' ) ).dy;
      final dyC = tester.getTopLeft( railBadge( 'C' ) ).dy;
      expect( dyB < dyA && dyA < dyC, isTrue,
          reason: 'establishment order top-to-bottom: B, A, C' );
    } );

    testWidgets( 'AC-S3.2 — unread count overlays non-focused badge; absent on focused', ( tester ) async {
      seed( _st(
        order   : [ 'X', 'Y' ],
        focused : 'X',
        unread  : { 'X': 0, 'Y': 3 },
      ) );
      await tester.pumpWidget( host() );
      await tester.pump();

      expect(
        find.descendant( of: railBadge( 'Y' ), matching: find.text( '3' ) ),
        findsOneWidget,
      );
      // Focused badge renders its initial-fallback glyph but NO unread count.
      expect(
        find.descendant( of: railBadge( 'X' ), matching: find.text( '0' ) ),
        findsNothing,
        reason: 'focused badge carries no unread overlay',
      );
    } );

    testWidgets( 'AC-S3.3 — rail tap dispatches FocusSenderSelected exactly once; NO TTS calls from the tap path', ( tester ) async {
      seed( _st( order: [ 'B' ] ) );
      await tester.pumpWidget( host() );
      await tester.pump();

      await tester.tap( railBadge( 'B' ) );
      await tester.pump();

      verify( () => focusBloc.add( const FocusSenderSelected( 'B' ) ) ).called( 1 );
      verifyNever( () => tts.pause() );
      verifyNever( () => tts.resume() );
      verifyNever( () => tts.enqueueAlways(
        priority : any( named: 'priority' ),
        message  : any( named: 'message' ),
        title    : any( named: 'title' ),
        voiceId  : any( named: 'voiceId' ),
        sender   : any( named: 'sender' ),
      ) );
    } );

    testWidgets( 'AC-S3.4 — pane shows exactly the focused sender\'s window; composer hint when no pending ask', ( tester ) async {
      seed( _st(
        order   : [ 'X', 'Y' ],
        focused : 'X',
        windows : {
          'X': [ for ( var i = 1; i <= 7; i++ ) FocusMessage( item: _item( 'x$i', 'X' ) ) ],
          'Y': [ FocusMessage( item: _item( 'y1', 'Y' ) ) ],
        },
      ) );
      // Bubbles carry a lower-left timestamp since 2026-08-21, so seven of
      // them no longer fit the default 800×600 test surface and ListView.builder
      // would not build the bottom one — use a phone-tall viewport.
      tester.view.physicalSize     = const Size( 1080, 2400 );
      tester.view.devicePixelRatio = 1.0;
      addTearDown( tester.view.resetPhysicalSize );
      addTearDown( tester.view.resetDevicePixelRatio );
      await tester.pumpWidget( host() );
      await tester.pump();

      for ( var i = 1; i <= 7; i++ ) {
        expect( find.text( 'msg-x$i' ), findsOneWidget );
      }
      expect( find.text( 'msg-y1' ), findsNothing,
          reason: 'only the FOCUSED sender\'s window renders' );
      // 2026-08-21: the composer is UNGATED — no pending ask ⇒ it is a
      // direct message to the focused session, and the caption says so.
      expect( find.byType( VoiceReplyField ), findsOneWidget );
      expect( find.byKey( const Key( TestKeys.focusComposerCaption ) ), findsOneWidget );
      expect( find.textContaining( 'Direct message to' ), findsOneWidget );
    } );

    testWidgets( 'composer with NO focused sender shows the focus hint, no VoiceReplyField', ( tester ) async {
      seed( _st( order: [ 'X' ] ) );
      await tester.pumpWidget( host() );
      await tester.pump();
      expect( find.byType( VoiceReplyField ), findsNothing );
      expect( find.textContaining( 'Focus a session' ), findsOneWidget );
    } );

    testWidgets( 'speech-queue button: badge shows depth off queueDepthStream; tap opens the TtsQueueSheet (Rick 2026-08-21)', ( tester ) async {
      final queueCtrl = StreamController<List<TtsQueueItem>>.broadcast();
      addTearDown( queueCtrl.close );
      when( () => tts.queueStream   ).thenAnswer( ( _ ) => queueCtrl.stream );
      when( () => tts.lastOutcome   ).thenReturn( null );
      when( () => tts.outcomeStream ).thenAnswer( ( _ ) => const Stream<TtsOutcome>.empty() );
      when( () => tts.queueSnapshot ).thenReturn( const [
        TtsQueueItem( id: 1, priority: 'high', text: 'playing now', sender: TtsSender( name: 'Tiffany', icon: '💍' ), isCurrent: true ),
        TtsQueueItem( id: 2, priority: 'low',  text: 'pytest chatter', sender: TtsSender( senderId: 'pytest@lupin#1' ), isCurrent: false ),
      ] );
      when( () => tts.queueDepth ).thenReturn( 1 );
      seed( _st( order: [ 'A' ] ) );
      await tester.pumpWidget( host() );
      await tester.pump();

      expect( find.byKey( const Key( TestKeys.focusQueueButton ) ), findsOneWidget );
      final badge = tester.widget<Badge>( find.byKey( const Key( TestKeys.focusQueueBadge ) ) );
      expect( badge.isLabelVisible, isTrue );
      expect( ( badge.label as Text ).data, '1' );

      await tester.tap( find.byKey( const Key( TestKeys.focusQueueButton ) ) );
      await tester.pumpAndSettle();
      expect( find.byKey( const Key( TestKeys.ttsQueueSheet ) ), findsOneWidget );
      expect( find.text( 'playing now' ),    findsOneWidget );
      expect( find.text( 'pytest chatter' ), findsOneWidget );
    } );

    testWidgets( 'AC-S3.5 — pause toggle calls pause(); paused banner shows LIVE held count off queueDepthStream; resume calls resume()', ( tester ) async {
      seed( _st( order: [ 'X' ] ) );
      when( () => tts.pause()  ).thenAnswer( ( _ ) {} );
      when( () => tts.resume() ).thenAnswer( ( _ ) {} );
      await tester.pumpWidget( host() );
      await tester.pump();

      await tester.tap( find.byKey( const Key( TestKeys.focusPauseToggle ) ) );
      verify( () => tts.pause() ).called( 1 );

      // Orchestrator transitions to paused with 2 held.
      when( () => tts.isPaused   ).thenReturn( true );
      when( () => tts.queueDepth ).thenReturn( 2 );
      pausedCtrl.add( true );
      await tester.pump();

      expect( find.byKey( const Key( TestKeys.focusPausedBanner ) ), findsOneWidget );
      expect( find.textContaining( '2 message(s)' ), findsOneWidget );

      depthCtrl.add( 5 );   // accumulates under hold — live tick (F-S1-S2-3)
      await tester.pump();
      expect( find.textContaining( '5 message(s)' ), findsOneWidget );

      await tester.tap( find.byKey( const Key( TestKeys.focusPauseToggle ) ) );
      verify( () => tts.resume() ).called( 1 );
    } );

    testWidgets( 'AC-S3.6 — unanswered yes_no renders tri-state body; Yes dispatches FocusRespondRequested with explicit context; answered collapses to chip', ( tester ) async {
      final ask = FocusMessage(
          item: _item( 'ask1', 'S', ask: true, responseType: 'yes_no' ) );
      final answered = FocusMessage(
          item     : _item( 'old-ask', 'S', ask: true, responseType: 'yes_no' ),
          answered : true );
      seed( _st(
        order   : [ 'S' ],
        focused : 'S',
        windows : { 'S': [ answered, ask ] },
      ) );
      await tester.pumpWidget( host() );
      await tester.pump();

      expect( find.byKey( const Key( TestKeys.promptYesButton ) ), findsOneWidget );
      expect( find.text( 'answered' ), findsOneWidget,
          reason: 'answered prompt collapses to a result chip' );

      await tester.tap( find.byKey( const Key( TestKeys.promptYesButton ) ) );
      await tester.pump();

      final captured = verify( () => focusBloc.add( captureAny() ) ).captured;
      final ev = captured.whereType<FocusRespondRequested>().single;
      expect( ev.senderId, 'S' );
      expect( ev.text, 'yes' );
      expect( ev.promptContext?.notificationId, 'ask1',
          reason: 'inline prompts pass explicit typed context (F-S3-2)' );
    } );

    testWidgets( 'AC-S3.6 sub-case (buried ask) — ask followed by newer progress messages still renders its buttons', ( tester ) async {
      final ask = FocusMessage(
          item: _item( 'ask1', 'S', ask: true, responseType: 'yes_no',
              ts: DateTime( 2026, 6, 12, 1 ) ) );
      seed( _st(
        order   : [ 'S' ],
        focused : 'S',
        windows : {
          'S': [
            ask,
            FocusMessage( item: _item( 'p1', 'S', type: 'progress',
                ts: DateTime( 2026, 6, 12, 2 ) ) ),
            FocusMessage( item: _item( 'p2', 'S', type: 'progress',
                ts: DateTime( 2026, 6, 12, 3 ) ) ),
          ],
        },
      ) );
      await tester.pumpWidget( host() );
      await tester.pump();

      expect( find.byKey( const Key( TestKeys.promptYesButton ) ), findsOneWidget,
          reason: 'progress chatter never buries the session\'s own ask' );

      await tester.tap( find.byKey( const Key( TestKeys.promptNoButton ) ) );
      await tester.pump();
      final captured = verify( () => focusBloc.add( captureAny() ) ).captured;
      expect( captured.whereType<FocusRespondRequested>().single.text, 'no' );
    } );

    testWidgets( 'AC-S3.6 sub-case (batch fallback) — batch ask renders the affordance, NO inline chips; tap opens the legacy sheet', ( tester ) async {
      final batch = FocusMessage(
        item: _item( 'b1', 'S',
            ask          : true,
            responseType : 'open_ended_batch',
            options      : { 'questions': [ 'q one', 'q two' ] } ),
      );
      seed( _st( order: [ 'S' ], focused: 'S', windows: { 'S': [ batch ] } ) );
      await tester.pumpWidget( host() );
      await tester.pump();

      final affordance =
          find.byKey( const Key( '${TestKeys.focusBatchFallbackPrefix}b1' ) );
      expect( affordance, findsOneWidget );
      expect( find.byKey( const Key( TestKeys.promptYesButton ) ), findsNothing );

      await tester.tap( affordance );
      await tester.pumpAndSettle();

      expect( find.text( 'Respond' ), findsOneWidget,
          reason: 'legacy InteractivePromptSheet opened (Map dispatch path intact)' );
      expect( find.text( 'Submit all' ), findsOneWidget );
    } );

    testWidgets( 'AC-S3.10 — cold-start empty hint (no auto-focus), loading spinner, error retry banner re-dispatching cold start', ( tester ) async {
      // (a) cold start: no focus → hint; FocusSenderSelected NEVER dispatched.
      seed( _st( order: [ 'A' ], focused: null ) );
      await tester.pumpWidget( host() );
      await tester.pump();
      expect( find.textContaining( 'Tap a session badge' ), findsOneWidget );
      verifyNever( () => focusBloc.add( any( that: isA<FocusSenderSelected>() ) ) );

      // (b) loading → spinner.
      seed( _st( hydration: FocusHydration.loading ) );
      await tester.pumpWidget( host() );
      await tester.pump();
      expect( find.byType( CircularProgressIndicator ), findsOneWidget );

      // (c) error → retry banner; tap re-dispatches FocusColdStartRequested.
      seed( _st( order: [ 'A' ], hydration: FocusHydration.error ) );
      await tester.pumpWidget( host() );
      await tester.pump();
      final banner = find.byKey( const Key( TestKeys.focusRetryBanner ) );
      expect( banner, findsOneWidget );
      await tester.tap( banner );
      await tester.pump();
      final captured = verify( () => focusBloc.add( captureAny() ) ).captured;
      final retry = captured.whereType<FocusColdStartRequested>().last;
      expect( retry.userEmail, 'rick@test.com' );
    } );

    testWidgets( 'AC-S3.7 — post-auth route lands on FocusModeScreen (real AuthGate seam shape)', ( tester ) async {
      seed( _st( order: [ 'A' ] ) );
      await tester.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<FocusChatBloc>.value( value: focusBloc ),
            BlocProvider<AuthBloc>.value( value: authBloc ),
            BlocProvider<NotificationBloc>.value( value: notifBloc ),
          ],
          child: MaterialApp(
            home: AuthGate(
              serverContext      : _MockServerCtx(),
              authenticatedChild : FocusModeScreen( tts: tts, asr: asr ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect( find.byKey( const Key( TestKeys.focusRail ) ), findsOneWidget,
          reason: 'authenticated state lands on the focus surface (Q1 swap)' );
    } );

    // 🔴 ROW c59457f0 CHANGED THIS TEST'S BODY AND DELIBERATELY KEPT ITS NAME.
    // The default drawer no longer has a 'Legacy surfaces' header or an Inbox
    // entry, so this smoke test now asks for the legacy drawer by the one switch
    // (`surfaces: false`) — which makes it, as a bonus, the proof that flipping
    // the switch really does bring the old drawer back with its navigation
    // intact. The NAME is an AC-G2 id: renaming it would read as a lost test.
    testWidgets( 'AC-S3.7 — drawer opens and navigates to a legacy screen (smoke)', ( tester ) async {
      seed( _st( order: [ 'A' ] ) );
      await tester.pumpWidget( host( surfaces: false ) );
      await tester.pump();

      await tester.tap( find.byKey( const Key( TestKeys.focusDrawerButton ) ) );
      await tester.pumpAndSettle();
      expect( find.text( 'Legacy surfaces' ), findsOneWidget );

      await tester.tap( find.text( 'Inbox' ) );
      // Bounded pumps, NOT pumpAndSettle: InboxScreen renders a loading
      // spinner for the mock bloc's initial state and never settles.
      await tester.pump();
      await tester.pump( const Duration( milliseconds: 600 ) );

      expect( find.byKey( const Key( TestKeys.focusRail ) ), findsNothing,
          reason: 'navigated away from the focus surface' );
    } );

    testWidgets( 'composer activates with a pending ask: VoiceReplyField present, onSubmit → FocusRespondRequested without context (voice fallback path)', ( tester ) async {
      when( () => asr.startRecording()  ).thenAnswer( ( _ ) async {} );
      when( () => asr.cancelRecording() ).thenAnswer( ( _ ) async {} );
      final ask = FocusMessage(
          item: _item( 'ask1', 'S', ask: true, responseType: 'open_ended' ) );
      seed( _st( order: [ 'S' ], focused: 'S', windows: { 'S': [ ask ] } ) );
      await tester.pumpWidget( host() );
      await tester.pump();

      expect( find.byType( VoiceReplyField ), findsOneWidget );
      expect( find.textContaining( 'Replying to' ), findsOneWidget, reason: 'pending ask ⇒ reply caption' );
    } );

    testWidgets( 'DM caption names the focused persona; onSubmit dispatches FocusRespondRequested without context (bloc picks reply vs DM)', ( tester ) async {
      when( () => asr.startRecording()  ).thenAnswer( ( _ ) async {} );
      when( () => asr.cancelRecording() ).thenAnswer( ( _ ) async {} );
      final tiff = VoicePersona.fromJson( { 'name': 'Tiffany', 'icon': '💍' } );
      seed( _st( order: [ 'S' ], focused: 'S', personas: { 'S': tiff },
                 windows: { 'S': [ FocusMessage( item: _item( 'n1', 'S' ) ) ] } ) );
      await tester.pumpWidget( host() );
      await tester.pump();

      expect( find.text( 'Direct message to Tiffany' ), findsOneWidget );
      final field = tester.widget<VoiceReplyField>( find.byType( VoiceReplyField ) );
      field.onSubmit( 'status please' );
      verify( () => focusBloc.add( const FocusRespondRequested( senderId: 'S', text: 'status please' ) ) ).called( 1 );
    } );
  } );

  // ───────────────────────────────────────────────────────────────────────
  // Visibility lens — 2026.06.25 plan §4.1/§4.5 (Live/24h toggle, status
  // dots, empty state) + Rick 2026-08-21 (persona-NAME initial fallback).
  // ───────────────────────────────────────────────────────────────────────
  group( 'FocusModeScreen — rail visibility lens + icons', () {
    final at = DateTime( 2026, 8, 21, 12 );

    Finder dot( String sid )     => find.byKey( Key( '${TestKeys.focusRailStatusDotPrefix}$sid' ) );
    Finder initial( String sid ) => find.byKey( Key( '${TestKeys.focusRailInitialPrefix}$sid' ) );

    testWidgets( 'filter bar shows Live/24h counts; tapping 24h dispatches FocusFilterChanged(history)', ( tester ) async {
      seed( _st(
        order    : const [ 'L', 'H' ],
        activity : { 'L': at.subtract( const Duration( minutes: 2 ) ), 'H': at.subtract( const Duration( hours: 3 ) ) },
        asOf     : at,
      ) );
      await tester.pumpWidget( host() );
      await tester.pump();

      expect( find.byKey( const Key( TestKeys.focusFilterBar ) ), findsOneWidget );
      expect( find.text( 'Live (1)' ), findsOneWidget );
      expect( find.text( '24h (2)' ),  findsOneWidget );
      // Live lens: only L is on the rail
      expect( railBadge( 'L' ), findsOneWidget );
      expect( railBadge( 'H' ), findsNothing );

      await tester.tap( find.byKey( const Key( TestKeys.focusFilterHistory ) ) );
      await tester.pump();
      verify( () => focusBloc.add( const FocusFilterChanged( FocusFilter.history ) ) ).called( 1 );
    } );

    testWidgets( '§5f Personas/All control: default Personas hides system chips, shows counts; tapping All dispatches FocusSenderScopeChanged(all)', ( tester ) async {
      final tiff = VoicePersona.fromJson( { 'name': 'Tiffany', 'icon': '💍', 'assigned_at': at.subtract( const Duration( hours: 2 ) ).toIso8601String() } );
      final sam  = VoicePersona.fromJson( { 'name': 'Sam',     'icon': '🎷', 'assigned_at': at.subtract( const Duration( hours: 5 ) ).toIso8601String() } );
      seed( _st(
        order    : const [ 'sys1', 'tiff', 'sam' ],
        personas : { 'tiff': tiff, 'sam': sam },
        activity : { 'sys1': at, 'tiff': at, 'sam': at },
        scope    : FocusSenderScope.personas,
        asOf     : at,
      ) );
      await tester.pumpWidget( host() );
      await tester.pump();

      expect( find.text( 'Personas (2)' ), findsOneWidget );
      expect( find.text( 'All (3)' ),      findsOneWidget );
      expect( railBadge( 'sam' ),  findsOneWidget );
      expect( railBadge( 'tiff' ), findsOneWidget );
      expect( railBadge( 'sys1' ), findsNothing, reason: 'system chip hidden under Personas' );
      expect( find.byKey( const Key( TestKeys.focusRailGroupDivider ) ), findsNothing, reason: 'no orphan divider' );
      // oldest session on top: Sam (5h) above Tiffany (2h)
      expect( tester.getTopLeft( railBadge( 'sam' ) ).dy < tester.getTopLeft( railBadge( 'tiff' ) ).dy, isTrue );

      await tester.tap( find.byKey( const Key( TestKeys.focusScopeAll ) ) );
      await tester.pump();
      verify( () => focusBloc.add( const FocusSenderScopeChanged( FocusSenderScope.all ) ) ).called( 1 );
    } );

    testWidgets( '§5f All scope: persona group, divider, then system group in arrival order', ( tester ) async {
      final tiff = VoicePersona.fromJson( { 'name': 'Tiffany', 'icon': '💍', 'assigned_at': at.toIso8601String() } );
      seed( _st(
        order    : const [ 'sysB', 'tiff', 'sysA' ],
        personas : { 'tiff': tiff },
        activity : { 'sysB': at, 'tiff': at, 'sysA': at },
        scope    : FocusSenderScope.all,
        asOf     : at,
      ) );
      await tester.pumpWidget( host() );
      await tester.pump();

      final divider = find.byKey( const Key( TestKeys.focusRailGroupDivider ) );
      expect( divider, findsOneWidget );
      final yT = tester.getTopLeft( railBadge( 'tiff' ) ).dy;
      final yD = tester.getTopLeft( divider ).dy;
      final yB = tester.getTopLeft( railBadge( 'sysB' ) ).dy;
      final yA = tester.getTopLeft( railBadge( 'sysA' ) ).dy;
      expect( yT < yD && yD < yB && yB < yA, isTrue, reason: 'persona · divider · sysB · sysA (arrival order)' );
    } );

    testWidgets( 'History lens renders both bands with 🟢/🟡 status dots; exited sender shows amber', ( tester ) async {
      seed( _st(
        order    : const [ 'L', 'H', 'X' ],
        activity : {
          'L': at.subtract( const Duration( minutes: 2 ) ),
          'H': at.subtract( const Duration( hours: 3 ) ),
          'X': at,
        },
        exited   : const { 'X' },
        filter   : FocusFilter.history,
        asOf     : at,
      ) );
      await tester.pumpWidget( host() );
      await tester.pump();

      for ( final sid in [ 'L', 'H', 'X' ] ) {
        expect( railBadge( sid ), findsOneWidget );
        expect( dot( sid ), findsOneWidget );
      }
      Color colorOf( String sid ) =>
          ( ( tester.widget<Container>( dot( sid ) ).decoration ) as BoxDecoration ).color!;
      expect( colorOf( 'L' ), const Color( 0xFF2E7D32 ) );
      expect( colorOf( 'H' ), const Color( 0xFFF9A825 ) );
      expect( colorOf( 'X' ), const Color( 0xFFF9A825 ), reason: 'exited renders as history even if recent' );
    } );

    testWidgets( 'fallback avatar uses the persona NAME initial, else the sender local part — never the repo id', ( tester ) async {
      final noIcon = VoicePersona.fromJson( { 'name': 'Tiffany' } );   // no icon ⇒ initial path
      seed( _st(
        order    : const [ 'lupin.tiffany@lupin.deepily.ai#e082', 'deep.research@lupin.deepily.ai#dr-1', '' ],
        personas : { 'lupin.tiffany@lupin.deepily.ai#e082': noIcon },
        asOf     : at,
      ) );
      await tester.pumpWidget( host() );
      await tester.pump();

      expect( tester.widget<Text>( initial( 'lupin.tiffany@lupin.deepily.ai#e082' ) ).data, 'T' );
      expect( tester.widget<Text>( initial( 'deep.research@lupin.deepily.ai#dr-1' ) ).data, 'D' );
      expect( tester.widget<Text>( initial( '' ) ).data, '?' );
      expect( SessionRail.railInitial( 'x@y', VoicePersona.fromJson( { 'name': 'Rio', 'display_name': 'María' } ) ), 'M' );
      expect( SessionRail.railInitial( '#only-suffix', null ), '?' );
    } );

    testWidgets( 'Live lens with nothing live but history present → empty hint; its button dispatches FocusFilterChanged(history)', ( tester ) async {
      seed( _st(
        order    : const [ 'H' ],
        activity : { 'H': at.subtract( const Duration( hours: 5 ) ) },
        asOf     : at,
      ) );
      await tester.pumpWidget( host() );
      await tester.pump();

      expect( find.byKey( const Key( TestKeys.focusRailEmptyHint ) ), findsOneWidget );
      expect( railBadge( 'H' ), findsNothing );
      await tester.tap( find.byKey( const Key( TestKeys.focusRailEmptyHintButton ) ) );
      await tester.pump();
      verify( () => focusBloc.add( const FocusFilterChanged( FocusFilter.history ) ) ).called( 1 );
    } );

    testWidgets( 'no senders at all → no empty hint (cold rail stays blank, no misleading "no live sessions")', ( tester ) async {
      seed( _st( asOf: at ) );
      await tester.pumpWidget( host() );
      await tester.pump();
      expect( find.byKey( const Key( TestKeys.focusRailEmptyHint ) ), findsNothing );
    } );

  group( 'FocusModeScreen — surfaces drawer (row c59457f0)', () {
    /// The drawer is a `ListView`, so an entry below the fold is never built and
    /// reads as absent. A phone-TALL viewport lays all of them out, which is what
    /// makes an absence assertion mean something here.
    Future<void> openDrawer( WidgetTester tester, { bool? surfaces } ) async {
      tester.view.physicalSize     = const Size( 1080, 2400 );
      tester.view.devicePixelRatio = 1.0;
      addTearDown( tester.view.resetPhysicalSize );
      addTearDown( tester.view.resetDevicePixelRatio );
      seed( _st( order: const [ 'A' ] ) );
      await tester.pumpWidget( host( surfaces: surfaces ) );
      await tester.pump();
      await tester.tap( find.byKey( const Key( TestKeys.focusDrawerButton ) ) );
      await tester.pumpAndSettle();
    }

    Finder entry( String title ) =>
        find.byKey( Key( '${TestKeys.focusDrawerEntryPrefix}$title' ) );

    /// The row's stated sequence, item 2, verbatim.
    const surfaceOrder = <String>[
      'Agentic Jobs', 'Claude Code', 'Broadcast', 'Fleet Status',
      'Finished Tasks', 'Task List', 'Holding Area',
    ];

    testWidgets( 'the header is the one string, and Quick Ask + Lupin AF Focus head the drawer', ( tester ) async {
      await openDrawer( tester );
      expect( find.byKey( const Key( TestKeys.focusDrawerHeader ) ), findsOneWidget );
      expect( find.text( kFocusDrawerHeader ), findsOneWidget );
      expect( find.text( 'Legacy surfaces' ), findsNothing );
      // Row 74a799c9 (Rick 2026-09-28): Quick Ask, then the Focus view by its new
      // name. Asserted as the literal the user reads, not via the constant, so a
      // rename that nobody asked for fails here.
      expect( entry( 'Quick Ask' ), findsOneWidget );
      expect( entry( 'Lupin AF Focus' ), findsOneWidget );
      expect( tester.getTopLeft( entry( 'Quick Ask' ) ).dy,
              lessThan( tester.getTopLeft( entry( 'Lupin AF Focus' ) ).dy ) );
    } );

    testWidgets( 'the build line is pinned under the entries and always on screen', ( tester ) async {
      // A short phone: the entry list scrolls, the footer must not.
      await openDrawer( tester );
      tester.view.physicalSize = const Size( 800, 700 );
      await tester.pumpAndSettle();
      final line = find.byKey( const Key( TestKeys.focusDrawerBuildLine ) );
      expect( line, findsOneWidget );
      expect( tester.widget<Text>( line ).data, BuildInfo.current.describe() );
      expect( tester.widget<Text>( line ).data, startsWith( 'Build' ) );
      expect( tester.getBottomLeft( line ).dy, lessThanOrEqualTo( 700 ) );
      // Scrolling the entries does not move it.
      final before = tester.getTopLeft( line );
      await tester.drag( entry( 'Quick Ask' ), const Offset( 0, -300 ) );
      await tester.pumpAndSettle();
      expect( tester.getTopLeft( line ), before );
    } );

    testWidgets( 'Home grid is hidden from the surfaces drawer (row 74a799c9)', ( tester ) async {
      await openDrawer( tester );
      // `find.text`, not the key: the label is what would be on screen.
      expect( find.text( 'Home grid' ), findsNothing,
          reason: 'redundant with the listed destinations; hidden, not deleted' );
    } );

    testWidgets( 'lists the Home grid surfaces TOP TO BOTTOM in the row\'s order', ( tester ) async {
      await openDrawer( tester );
      // Position-based, not `findsOneWidget` seven times: the row asked for an
      // ORDER, and a set assertion passes on any permutation of the same labels.
      final dys = <String, double>{
        for ( final t in surfaceOrder ) t: tester.getTopLeft( entry( t ) ).dy,
      };
      for ( var i = 1; i < surfaceOrder.length; i++ ) {
        expect( dys[ surfaceOrder[ i ] ]!, greaterThan( dys[ surfaceOrder[ i - 1 ] ]! ),
            reason: '${surfaceOrder[ i ]} must sit below ${surfaceOrder[ i - 1 ]}' );
      }
      // …and below the two entries that head the drawer.
      expect( dys[ 'Agentic Jobs' ]!, greaterThan( tester.getTopLeft( entry( 'Lupin AF Focus' ) ).dy ) );
    } );

    testWidgets( 'Inbox, Queue Dashboard and Trust Dashboard are absent', ( tester ) async {
      await openDrawer( tester );
      for ( final gone in <String>[ 'Inbox', 'Queue Dashboard', 'Trust Dashboard' ] ) {
        expect( find.text( gone ), findsNothing, reason: '$gone is hidden by row item 1' );
      }
      // Settings, the stop-list and Log out are NOT part of item 1 and stay.
      expect( entry( 'Settings' ), findsOneWidget );
      expect( entry( 'Notification stop-list' ), findsOneWidget );
      expect( find.byKey( const Key( TestKeys.focusDrawerLogout ) ), findsOneWidget );
    } );

    testWidgets( 'every entry is wired to a route, not merely rendered', ( tester ) async {
      await openDrawer( tester );
      // A `ListTile` with a null `onTap` is indistinguishable from a live one in
      // a presence assertion and goes nowhere — the defect
      // test/widget/home/fleet_panes_reachable_test.dart exists to catch.
      for ( final t in <String>[ 'Quick Ask', 'Lupin AF Focus', ...surfaceOrder,
                                 'Settings', 'Notification stop-list' ] ) {
        expect( tester.widget<ListTile>( entry( t ) ).onTap, isNotNull, reason: t );
      }
    } );

    testWidgets( 'Lupin AF Focus closes the drawer and stays on Focus, no second copy', ( tester ) async {
      await openDrawer( tester );
      await tester.tap( entry( 'Lupin AF Focus' ) );
      await tester.pumpAndSettle();
      expect( find.text( kFocusDrawerHeader ), findsNothing, reason: 'the drawer closed' );
      expect( find.byKey( const Key( TestKeys.focusRail ) ), findsOneWidget,
          reason: 'still on the Focus screen' );
      expect( find.text( 'Lupin AF Focus' ), findsOneWidget,
          reason: 'one app bar title: no second Focus screen was pushed' );
    } );

    testWidgets( 'F7 — DOUBLE-tapping Lupin AF Focus does not black-screen the app',
        ( tester ) async {
      // The entry used to call Navigator.pop() to shut the drawer, which works
      // only because DrawerController keeps a LocalHistoryEntry while the drawer
      // is open. The controller drops that entry as soon as the close animation
      // reverses, but the tile stays mounted and hit-testable for the rest of the
      // ~250ms slide, so a second tap in that window popped the ROUTE instead —
      // and Focus is the first and only route, so the navigator emptied and the
      // screen went black until the app was killed.
      await openDrawer( tester );

      // The handler is invoked TWICE, which is what a double tap does. Driving it
      // through two `tester.tap`s would depend on the tile still passing a hit
      // test at whatever millisecond the second one lands — and a guarded
      // "tap only if still there" quietly skips itself and passes against the
      // bug, which is how the first cut of this test was useless.
      final tile = tester.widget<ListTile>( entry( 'Lupin AF Focus' ) );
      tile.onTap!();
      await tester.pump( const Duration( milliseconds: 50 ) );
      tile.onTap!();
      await tester.pumpAndSettle();

      expect( find.byKey( const Key( TestKeys.focusRail ) ), findsOneWidget,
          reason: 'the Focus screen survived both taps — an empty navigator is the black screen' );
      expect( find.text( kFocusDrawerHeader ), findsNothing, reason: 'the drawer still closed' );
      expect( find.text( 'Lupin AF Focus' ), findsOneWidget,
          reason: 'one app bar title: no second copy, and no missing first one' );
      expect( tester.takeException(), isNull );
    } );

    testWidgets( 'each entry opens ITS OWN screen, with home_screen.dart\'s bloc scoping', ( tester ) async {
      // Registered because two builders read the locator; nothing here is mounted,
      // so a stub instance is all the builders need.
      GetIt.instance.registerSingleton<BroadcastBloc>( _MockBroadcastBloc() );
      // ⚠️ Registering prefs also hands them to `FocusChatPane`'s fraction bar and
      // to `DocSplitHost`, which read them on build — an unstubbed mock returns
      // null into a `double` there. Found by running this, not by reading it.
      final prefs = _MockPrefs();
      when( () => prefs.ttsFraction        ).thenReturn( 0.5 );
      when( () => prefs.docsBelowWhenWide  ).thenReturn( false );
      GetIt.instance.registerSingleton<NotificationPreferences>( prefs );
      GetIt.instance.registerSingleton<NotificationStopList>( _MockStopList() );
      addTearDown( GetIt.instance.reset );

      await openDrawer( tester );
      final ctx = tester.element( find.byType( FocusModeScreen ) );

      // 🔴 CALLING each entry's builder, not tapping it. A label test proves a
      // string is on screen; this proves the entry is pointed at the right
      // SCREEN — repoint one and this goes red — without dragging in the five
      // repositories those panes' blocs would want if they were mounted.
      final built = {
        for ( final s in [ ...focusDrawerSurfaces( ctx ), ...focusDrawerTools( ctx ) ] )
          s.title: s.builder( ctx ),
      };
      expect( built[ 'Agentic Jobs' ], isA<BlocProvider<AgenticSubmissionBloc>>() );
      expect( ( built[ 'Agentic Jobs' ]! as BlocProvider ).child, isA<AgenticHubScreen>() );
      expect( built[ 'Claude Code' ], isA<BlocProvider<ClaudeCodeBloc>>() );
      expect( ( built[ 'Claude Code' ]! as BlocProvider ).child, isA<SessionListScreen>() );
      expect( built[ 'Broadcast' ], isA<Scaffold>() );
      expect( ( built[ 'Broadcast' ]! as Scaffold ).body, isA<BlocProvider<BroadcastBloc>>() );
      expect( built[ 'Fleet Status' ], isA<FleetStatusScreen>() );
      expect( built[ 'Finished Tasks' ], isA<BlocProvider<FinishedTasksBloc>>() );
      expect( ( built[ 'Finished Tasks' ]! as BlocProvider ).child, isA<FinishedTasksScreen>() );
      expect( built[ 'Task List' ], isA<PaneHostScreen<TaskListBloc>>() );
      expect( built[ 'Holding Area' ], isA<PaneHostScreen<HoldingAreaBloc>>() );
      expect( built[ 'Settings' ], isA<NotificationAudioSettingsScreen>() );
      expect( built[ 'Notification stop-list' ], isA<NotificationFilterSettingsScreen>() );

      // The bloc-scoping asymmetry home_screen.dart calls deliberate: the four
      // polling panes take a FACTORY (a fresh bloc per route), Broadcast takes
      // the app-root instance by `.value`. `.value` for a poller would leave a
      // timer running behind whichever pane the operator is looking at.
      expect( ( built[ 'Fleet Status' ]! as FleetStatusScreen ).blocFactory, isNotNull );
      expect( ( built[ 'Task List' ]! as PaneHostScreen<TaskListBloc> ).blocFactory, isNotNull );
      expect( ( built[ 'Holding Area' ]! as PaneHostScreen<HoldingAreaBloc> ).blocFactory, isNotNull );
// ⚠️ WHAT THIS TEST CANNOT SEE: `BlocProvider.value` exposes neither its bloc
      // nor a `create`, so "Broadcast takes the APP-ROOT instance while the four
      // pollers take a factory" is only half-assertable from here. The factory half
      // is asserted above; the `.value` half rests on the type check plus review.

    } );

    testWidgets( 'the stop-list entry opens the editor, and Log out asks AuthBloc to log out', ( tester ) async {
      // A REAL stop-list, not a mock: the editor reads `patterns` on build, so a
      // mock would throw where the real service just returns its seeds.
      SharedPreferences.setMockInitialValues( {} );
      GetIt.instance.registerSingleton<NotificationStopList>(
        NotificationStopList( await SharedPreferences.getInstance() ) );
      addTearDown( GetIt.instance.reset );

      await openDrawer( tester );
      await tester.tap( entry( 'Notification stop-list' ) );
      await tester.pumpAndSettle();
      expect( find.byType( NotificationFilterSettingsScreen ), findsOneWidget,
          reason: 'the entry is a door, not a label' );

      // Back to Focus, then the one entry that dispatches instead of navigating.
      Navigator.of( tester.element( find.byType( NotificationFilterSettingsScreen ) ) ).pop();
      await tester.pumpAndSettle();
      await tester.tap( find.byKey( const Key( TestKeys.focusDrawerButton ) ) );
      await tester.pumpAndSettle();
      await tester.tap( find.byKey( const Key( TestKeys.focusDrawerLogout ) ) );
      await tester.pumpAndSettle();
      verify( () => authBloc.add( const AuthLogoutRequested() ) ).called( 1 );
    } );

    testWidgets( 'surfacesExperiment: false restores the old drawer, entry for entry', ( tester ) async {
      await openDrawer( tester, surfaces: false );
      expect( find.text( 'Legacy surfaces' ), findsOneWidget );
      expect( find.text( kFocusDrawerHeader ), findsNothing );
      for ( final back in <String>[ 'Quick Ask', 'Home grid', 'Inbox', 'Queue Dashboard',
                                    'Trust Dashboard', 'Settings', 'Notification stop-list',
                                    'Log out' ] ) {
        expect( find.text( back ), findsOneWidget, reason: '$back belongs to the old drawer' );
      }
      // …and the experiment's additions are gone with it.
      // 🔴 `find.text`, NOT the key finder (Clayton, 2026-09-28): the legacy
      // drawer's tiles carry NO keys, so a key-based absence check passes even
      // when a tile with that label is sitting right there. The label is the
      // thing the user sees, so it is the thing asserted absent.
      for ( final t in surfaceOrder ) {
        expect( find.text( t ), findsNothing, reason: '$t is an experiment entry' );
      }
    } );
  } );

  group( 'FocusModeScreen — stop-list caption', () {
    testWidgets( 'focused sender with hidden messages shows "N hidden by your stop-list"; none ⇒ no caption', ( tester ) async {
      seed( _st( order: const [ 'S' ], focused: 'S',
                 windows: { 'S': [ FocusMessage( item: _item( '1', 'S' ) ) ] },
                 hidden: const { 'S': 3 } ) );
      await tester.pumpWidget( host() );
      await tester.pump();
      expect( find.byKey( const Key( TestKeys.focusHiddenCaption ) ), findsOneWidget );
      expect( find.text( '3 hidden by your stop-list' ), findsOneWidget );

      seed( _st( order: const [ 'S' ], focused: 'S',
                 windows: { 'S': [ FocusMessage( item: _item( '1', 'S' ) ) ] } ) );
      await tester.pumpWidget( host() );
      await tester.pump();
      expect( find.byKey( const Key( TestKeys.focusHiddenCaption ) ), findsNothing );
    } );
  } );
  } );
}
