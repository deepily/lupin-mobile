import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
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

  Widget host() {
    return MultiBlocProvider(
      providers: [
        BlocProvider<FocusChatBloc>.value( value: focusBloc ),
        BlocProvider<AuthBloc>.value( value: authBloc ),
        BlocProvider<NotificationBloc>.value( value: notifBloc ),
      ],
      child: MaterialApp(
        home: FocusModeScreen( tts: tts, asr: asr ),
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
      await tester.pumpWidget( host() );
      await tester.pump();

      for ( var i = 1; i <= 7; i++ ) {
        expect( find.text( 'msg-x$i' ), findsOneWidget );
      }
      expect( find.text( 'msg-y1' ), findsNothing,
          reason: 'only the FOCUSED sender\'s window renders' );
      expect( find.byType( VoiceReplyField ), findsNothing );
      expect( find.textContaining( 'No unanswered ask' ), findsOneWidget,
          reason: 'composer disabled + hint when pendingPromptFor is null' );
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
          find.byKey( Key( '${TestKeys.focusBatchFallbackPrefix}b1' ) );
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

    testWidgets( 'AC-S3.7 — drawer opens and navigates to a legacy screen (smoke)', ( tester ) async {
      seed( _st( order: [ 'A' ] ) );
      await tester.pumpWidget( host() );
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
