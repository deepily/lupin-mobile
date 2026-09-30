/// Plan §3.4, C widget row — the Review first | Send immediately control.
///
/// 🔴 A REAL `QuickAskBloc`, not `MockBloc`, for the render/flip/persist arms.
/// The row asserts J-ABS-2's single writer end to end: a tap adds
/// `QuickAskSendModeChanged`, the BLOC writes the preference, and the control
/// re-renders from the emitted `QuickAskState` field. A mocked bloc replaces
/// exactly that computation, so it could only ever show the tap was wired.
/// The wiring arm below uses a mock on purpose, and says so.
library;

import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/notifications/data/notification_repository.dart';
import 'package:lupin_mobile/features/queue/data/queue_repository.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_bloc.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_event.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_state.dart';
import 'package:lupin_mobile/features/quick_ask/presentation/quick_ask_screen.dart';
import 'package:lupin_mobile/services/asr/asr_service.dart';
import 'package:lupin_mobile/services/quick_ask/quick_ask_preferences.dart';
import 'package:lupin_mobile/services/tts/tts_orchestrator.dart';
import 'package:lupin_mobile/services/websocket/websocket_service.dart';

class MockQuickAskBloc extends MockBloc<QuickAskEvent, QuickAskState>
    implements QuickAskBloc {}

class MockTtsOrchestrator        extends Mock implements TtsOrchestrator        {}
class MockQueueRepository        extends Mock implements QueueRepository        {}
class MockAsrService             extends Mock implements AsrService             {}
class MockWebSocketService       extends Mock implements WebSocketService       {}
class MockNotificationRepository extends Mock implements NotificationRepository {}

void main() {
  late MockTtsOrchestrator tts;

  setUpAll( () {
    registerFallbackValue( const QuickAskRecordPressed() );
    registerFallbackValue( const TtsSender() );
  } );

  setUp( () {
    tts = MockTtsOrchestrator();
    when( () => tts.isPaused ).thenReturn( false );
    when( () => tts.pausedStream ).thenAnswer( ( _ ) => const Stream<bool>.empty() );
    when( () => tts.queueDepth ).thenReturn( 0 );
    when( () => tts.queueDepthStream ).thenAnswer( ( _ ) => const Stream<int>.empty() );
    GetIt.instance.registerSingleton<TtsOrchestrator>( tts );
  } );

  tearDown( () async { await GetIt.instance.reset(); } );

  Finder toggle()          => find.byKey( const Key( TestKeys.quickAskSendModeToggle ) );
  Finder reviewSegment()   => find.descendant( of: toggle(), matching: find.text( 'Review first' ) );
  Finder sendNowSegment()  => find.descendant( of: toggle(), matching: find.text( 'Send immediately' ) );

  Set<bool> shown( WidgetTester tester ) =>
      tester.widget<SegmentedButton<bool>>( toggle() ).selected;

  /// A real bloc over mocks, with a REAL `QuickAskPreferences` on the
  /// in-memory `SharedPreferences`, so "persists" means a stored value.
  QuickAskBloc realBloc( QuickAskPreferences prefs ) {
    final ws  = MockWebSocketService();
    final asr = MockAsrService();
    when( () => ws.sessionId ).thenReturn( 'wise penguin' );
    when( () => ws.connectionStream ).thenAnswer( ( _ ) async* { yield true; } );
    when( () => asr.isCapturing ).thenReturn( false );
    return QuickAskBloc(
      MockQueueRepository(),
      asr           : asr,
      ws            : ws,
      notifications : MockNotificationRepository(),
      prefs         : prefs,
    );
  }

  Future<void> pumpScreen( WidgetTester tester, QuickAskBloc bloc ) async {
    await tester.pumpWidget( MaterialApp(
      home: BlocProvider<QuickAskBloc>.value( value: bloc, child: const QuickAskScreen() ),
    ) );
    await tester.pump();
  }

  group( 'the send-mode control on the Quick Ask screen', () {

    testWidgets( 'a fresh install shows REVIEW FIRST', ( tester ) async {
      SharedPreferences.setMockInitialValues( {} );
      final prefs = QuickAskPreferences( await SharedPreferences.getInstance() );
      final bloc  = realBloc( prefs );
      addTearDown( bloc.close );

      await pumpScreen( tester, bloc );

      expect( toggle(), findsOneWidget );
      expect( reviewSegment(), findsOneWidget );
      expect( sendNowSegment(), findsOneWidget );
      expect( shown( tester ), { false } );
    } );

    testWidgets( 'a stored Send immediately is what the control shows at start', ( tester ) async {
      SharedPreferences.setMockInitialValues( { QuickAskPreferences.keySendImmediately: true } );
      final prefs = QuickAskPreferences( await SharedPreferences.getInstance() );
      final bloc  = realBloc( prefs );
      addTearDown( bloc.close );

      await pumpScreen( tester, bloc );

      expect( shown( tester ), { true } );
    } );

    testWidgets( 'tapping flips the mode, WRITES the preference, and re-renders from state', ( tester ) async {
      SharedPreferences.setMockInitialValues( {} );
      final prefs = QuickAskPreferences( await SharedPreferences.getInstance() );
      final bloc  = realBloc( prefs );
      addTearDown( bloc.close );
      await pumpScreen( tester, bloc );

      await tester.tap( sendNowSegment() );
      await tester.pumpAndSettle();

      expect( bloc.state.sendImmediately, isTrue, reason: 'the bloc emitted the new field' );
      expect( shown( tester ), { true }, reason: 'the control re-rendered from state' );
      // Persisted: a NEW preferences object over the same store reads it back.
      final reread = QuickAskPreferences( await SharedPreferences.getInstance() );
      expect( reread.sendImmediately, isTrue, reason: 'the preference was written' );

      // And back again — a one-way flip would pass the arm above.
      await tester.tap( reviewSegment() );
      await tester.pumpAndSettle();

      expect( bloc.state.sendImmediately, isFalse );
      expect( shown( tester ), { false } );
      expect( QuickAskPreferences( await SharedPreferences.getInstance() ).sendImmediately, isFalse );
    } );

    // The header is fixed height, so the control yields its row while a
    // Door C prompt or an interview needs the space (the mic is blocked then).
    testWidgets( 'hidden while a prompt or an interview is live, shown again after', ( tester ) async {
      Future<void> pumpState( QuickAskState st ) async {
        final b = MockQuickAskBloc();
        whenListen( b, Stream<QuickAskState>.fromIterable( const [] ), initialState: st );
        await pumpScreen( tester, b );
      }

      await pumpState( const QuickAskState( connected: true,
          pendingPrompt: QuickAskPrompt( id: 'n-1', question: 'Is that the same as: weather?' ) ) );
      expect( toggle(), findsNothing );

      await pumpState( const QuickAskState( connected: true,
          interview: QuickAskInterview( pendingId: 'p-1', question: 'Which city?' ) ) );
      expect( toggle(), findsNothing );

      await pumpState( const QuickAskState( connected: true ) );
      expect( toggle(), findsOneWidget );
    } );

    // Wiring only — the mock stands in for the bloc so the assertion is
    // about WHICH event the tap adds, nothing more.
    testWidgets( 'the tap adds QuickAskSendModeChanged carrying the picked mode', ( tester ) async {
      final b = MockQuickAskBloc();
      whenListen( b, Stream<QuickAskState>.fromIterable( const [] ),
          initialState: const QuickAskState( connected: true ) );
      await pumpScreen( tester, b );

      await tester.tap( sendNowSegment() );
      await tester.pump();

      verify( () => b.add( const QuickAskSendModeChanged( true ) ) ).called( 1 );
    } );
  } );
}
