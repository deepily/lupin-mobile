/// Quick Ask hands-free: while the screen is open, the earbuds work record and send.
library;

import 'package:audio_service/audio_service.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/features/quick_ask/data/hands_free_cues.dart';
import 'package:lupin_mobile/features/quick_ask/domain/earbud_taps.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_bloc.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_event.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_state.dart';
import 'package:lupin_mobile/features/quick_ask/presentation/earbud_hands_free.dart';
import 'package:lupin_mobile/features/quick_ask/presentation/quick_ask_screen.dart';
import 'package:lupin_mobile/services/audio/lupin_media_handler.dart';
import 'package:lupin_mobile/services/tts/tts_orchestrator.dart';

class _MockQuickAskBloc extends MockBloc<QuickAskEvent, QuickAskState> implements QuickAskBloc {}

class _MockTts extends Mock implements TtsOrchestrator {}

class _Cues implements HandsFreeCuePlayer {
  final played = <HandsFreeCue>[];
  @override
  Future<void> play( HandsFreeCue cue ) async => played.add( cue );
}

class _Transport implements MediaTransport {
  final calls = <String>[];
  @override
  Duration get position => Duration.zero;
  @override
  Future<void> play()  async => calls.add( 'play' );
  @override
  Future<void> pause() async => calls.add( 'pause' );
  @override
  Future<void> seek( Duration p ) async {}
  @override
  Future<void> stop()  async {}
}

void main() {
  late _MockQuickAskBloc  bloc;
  late LupinMediaHandler  handler;
  late _Transport         podcast;
  late _Cues              cues;

  setUpAll( () => registerFallbackValue( const QuickAskDraftCleared() ) );

  setUp( () {
    bloc    = _MockQuickAskBloc();
    handler = LupinMediaHandler( rewindInterval: const Duration( seconds: 15 ) );
    podcast = _Transport();
    cues    = _Cues();
    handler.attach( podcast );
    final tts = _MockTts();
    when( () => tts.isPaused ).thenReturn( false );
    when( () => tts.pausedStream ).thenAnswer( ( _ ) => const Stream<bool>.empty() );
    when( () => tts.queueDepth ).thenReturn( 0 );
    when( () => tts.queueDepthStream ).thenAnswer( ( _ ) => const Stream<int>.empty() );
    GetIt.instance
      ..registerSingleton<TtsOrchestrator>( tts )
      ..registerSingleton<LupinMediaHandler>( handler )
      ..registerSingleton<HandsFreeCuePlayer>( cues );
  } );

  tearDown( () async { await GetIt.instance.reset(); } );

  Future<void> mount( WidgetTester tester, QuickAskState state ) async {
    whenListen( bloc, const Stream<QuickAskState>.empty(), initialState: state );
    await tester.pumpWidget( MaterialApp(
      home: BlocProvider<QuickAskBloc>.value( value: bloc, child: const QuickAskScreen() ),
    ) );
    await tester.pump();
  }

  List<QuickAskEvent> sent() =>
      verify( () => bloc.add( captureAny() ) ).captured.cast<QuickAskEvent>();

  const idle = QuickAskState( connected: true );
  const held = QuickAskState( connected: true, phase: QuickAskPhase.review, draftTranscript: 'what time is it' );

  testWidgets( 'opening the screen takes the earbuds and shows the Quick Ask card', ( tester ) async {
    await mount( tester, idle );
    expect( handler.isClaimed, isTrue );
    expect( handler.mediaItem.value, EarbudHandsFree.card );
  } );

  testWidgets( 'leaving the screen gives the earbuds back to the podcast', ( tester ) async {
    await mount( tester, idle );
    await tester.pumpWidget( const MaterialApp( home: SizedBox() ) );
    expect( handler.isClaimed, isFalse );
    await handler.click();
    expect( podcast.calls, [ 'play' ] );
  } );

  testWidgets( 'a tap starts recording, with the start tone', ( tester ) async {
    await mount( tester, idle );
    await handler.click();
    await tester.pump( EarbudTapReader.defaultWindow );

    expect( sent(), [ const QuickAskRecordPressed() ] );
    expect( cues.played, [ HandsFreeCue.started ] );
    expect( podcast.calls, isEmpty );
  } );

  testWidgets( 'a tap while recording stops it, with the stop tone', ( tester ) async {
    await mount( tester, const QuickAskState( connected: true, phase: QuickAskPhase.recording, capturing: true ) );
    await handler.click();
    await tester.pump( EarbudTapReader.defaultWindow );

    expect( sent(), [ const QuickAskRecordReleased() ] );
    expect( cues.played, [ HandsFreeCue.stopped ] );
  } );

  testWidgets( 'a double tap sends the held transcript, with the sent tone', ( tester ) async {
    await mount( tester, held );
    await handler.click();
    await tester.pump( const Duration( milliseconds: 200 ) );
    await handler.click();
    await tester.pump( EarbudTapReader.defaultWindow );

    expect( sent(), [ const QuickAskDraftSent() ] );
    expect( cues.played, [ HandsFreeCue.sent ] );
  } );

  testWidgets( 'an earbud "next track" press sends too', ( tester ) async {
    await mount( tester, held );
    await handler.click( MediaButton.next );
    await tester.pump();

    expect( sent(), [ const QuickAskDraftSent() ] );
  } );

  testWidgets( 'a double tap with nothing held sends nothing and plays the refusal', ( tester ) async {
    await mount( tester, idle );
    await handler.click( MediaButton.next );
    await tester.pump();

    verifyNever( () => bloc.add( any() ) );
    expect( cues.played, [ HandsFreeCue.refused ] );
  } );

  testWidgets( 'a press still waiting when the screen closes does nothing', ( tester ) async {
    await mount( tester, idle );
    await handler.click();
    await tester.pumpWidget( const MaterialApp( home: SizedBox() ) );
    await tester.pump( EarbudTapReader.defaultWindow );

    verifyNever( () => bloc.add( any() ) );
    expect( cues.played, isEmpty );
  } );
}
