/// The tap-toggle microphone and the two small controls under it, rendered.
///
/// 🔴 Scope, same split as `quick_ask_screen_test.dart`: the bloc is mocked, so
/// these are RENDERING and WIRING assertions only. Whether stopping actually
/// holds the transcript instead of submitting it is driven against a real bloc
/// in `test/unit/quick_ask/tap_to_toggle_test.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:get_it/get_it.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/services/tts/tts_orchestrator.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_bloc.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_event.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_state.dart';
import 'package:lupin_mobile/features/quick_ask/presentation/quick_ask_screen.dart';

class MockQuickAskBloc extends MockBloc<QuickAskEvent, QuickAskState>
    implements QuickAskBloc {}

class MockTtsOrchestrator extends Mock implements TtsOrchestrator {}

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

  /// A FRESH mock per pump — `BlocBuilder` keeps its first state otherwise.
  Future<MockQuickAskBloc> pump( WidgetTester tester, QuickAskState state ) async {
    final b = MockQuickAskBloc();
    whenListen( b, Stream<QuickAskState>.fromIterable( const [] ), initialState: state );
    await tester.pumpWidget( MaterialApp(
      home: BlocProvider<QuickAskBloc>.value( value: b, child: const QuickAskScreen() ),
    ) );
    await tester.pump();
    return b;
  }

  Finder mic()   => find.byKey( const Key( TestKeys.quickAskRecordButton ) );
  Finder clear() => find.byKey( const Key( TestKeys.quickAskClearButton ) );
  Finder send()  => find.byKey( const Key( TestKeys.quickAskSendButton ) );

  const idle      = QuickAskState( connected: true );
  const listening = QuickAskState( connected: true, phase: QuickAskPhase.recording );
  const held      = QuickAskState(
    connected       : true,
    phase           : QuickAskPhase.review,
    draftTranscript : 'what is the weather',
  );

  group( 'the microphone is a TAP toggle', () {

    testWidgets( 'a tap while idle STARTS the capture', ( tester ) async {
      final b = await pump( tester, idle );

      await tester.tap( mic() );
      await tester.pump();

      verify( () => b.add( const QuickAskRecordPressed() ) ).called( 1 );
    } );

    testWidgets( 'a tap while recording STOPS it — no finger stays down', ( tester ) async {
      final b = await pump( tester, listening );

      await tester.tap( mic() );
      await tester.pump();

      verify( () => b.add( const QuickAskRecordReleased() ) ).called( 1 );
      // The falsifier for the whole gesture change: a second start here would
      // mean the button never learned it was already recording.
      verifyNever( () => b.add( const QuickAskRecordPressed() ) );
    } );

    testWidgets( 'the mic is inert while a draft is held', ( tester ) async {
      final b = await pump( tester, held );

      await tester.tap( mic() );
      await tester.pump();

      verifyNever( () => b.add( any() ) );
    } );

    testWidgets( 'the headline says TAP, not hold', ( tester ) async {
      await pump( tester, idle );
      expect( find.text( 'Tap to ask' ), findsOneWidget );
    } );
  } );

  group( 'clear and send flank the microphone', () {

    testWidgets( 'both controls are mounted, below the mic and to either side',
        ( tester ) async {
      await pump( tester, held );

      expect( clear(), findsOneWidget );
      expect( send(),  findsOneWidget );

      final micBox   = tester.getRect( mic() );
      final clearBox = tester.getRect( clear() );
      final sendBox  = tester.getRect( send() );

      // Lower: both sit below the microphone's centre.
      expect( clearBox.center.dy, greaterThan( micBox.center.dy ) );
      expect( sendBox.center.dy,  greaterThan( micBox.center.dy ) );
      // Left and right: clear on the lower LEFT, send on the lower RIGHT.
      expect( clearBox.center.dx, lessThan( micBox.center.dx ) );
      expect( sendBox.center.dx,  greaterThan( micBox.center.dx ) );
      // Much smaller than the mic — the mic is what you aim at.
      expect( clearBox.width, lessThan( micBox.width / 2 ) );
      expect( sendBox.width,  lessThan( micBox.width / 2 ) );
    } );

    testWidgets( 'send tells the bloc to submit the held draft', ( tester ) async {
      final b = await pump( tester, held );

      await tester.tap( send() );
      await tester.pump();

      verify( () => b.add( const QuickAskDraftSent() ) ).called( 1 );
    } );

    testWidgets( 'clear tells the bloc to throw the draft away', ( tester ) async {
      final b = await pump( tester, held );

      await tester.tap( clear() );
      await tester.pump();

      verify( () => b.add( const QuickAskDraftCleared() ) ).called( 1 );
    } );

    testWidgets( 'with NO draft both controls are dead — neither can fire',
        ( tester ) async {
      final b = await pump( tester, idle );

      await tester.tap( clear() );
      await tester.tap( send() );
      await tester.pump();

      verifyNever( () => b.add( const QuickAskDraftCleared() ) );
      verifyNever( () => b.add( const QuickAskDraftSent() ) );
    } );
  } );

  group( 'the held draft is SHOWN before it can be sent', () {

    testWidgets( 'the transcript and a ready-to-send headline are on screen',
        ( tester ) async {
      await pump( tester, held );

      expect( find.byKey( const Key( TestKeys.quickAskDraftText ) ), findsOneWidget );
      expect( find.textContaining( 'what is the weather' ), findsWidgets );
      expect( find.text( 'Ready to send' ), findsOneWidget );
    } );

    testWidgets( 'nothing is shown when there is no draft', ( tester ) async {
      await pump( tester, idle );
      expect( find.byKey( const Key( TestKeys.quickAskDraftText ) ), findsNothing );
    } );
  } );
}
