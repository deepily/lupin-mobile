/// Quick Ask shows a multiple-choice ask's options and Other.
///
/// It answers `{"answers": {header: value}}`, as the focus pane does.
library;

import 'dart:convert';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_bloc.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_event.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_state.dart';
import 'package:lupin_mobile/features/quick_ask/presentation/quick_ask_screen.dart';
import 'package:lupin_mobile/services/tts/tts_orchestrator.dart';
import 'package:lupin_mobile/shared/widgets/prompt_bodies.dart';

class _MockQuickAskBloc extends MockBloc<QuickAskEvent, QuickAskState> implements QuickAskBloc {}

class _MockTts extends Mock implements TtsOrchestrator {}

const _single = {
  'questions': [
    {
      'question'     : 'Which database?',
      'header'       : 'Database',
      'multi_select' : false,
      'options'      : [ { 'label': 'Postgres' }, { 'label': 'SQLite' } ],
    },
  ],
};

const _multi = {
  'questions': [
    {
      'question'     : 'Which regions?',
      'header'       : 'Regions',
      'multi_select' : true,
      'options'      : [ { 'label': 'us-east' }, { 'label': 'eu-west' } ],
    },
  ],
};

void main() {
  late _MockQuickAskBloc bloc;

  setUpAll( () => registerFallbackValue( const QuickAskPromptAnswered( '' ) ) );

  setUp( () {
    bloc      = _MockQuickAskBloc();
    final tts = _MockTts();
    when( () => tts.isPaused ).thenReturn( false );
    when( () => tts.pausedStream ).thenAnswer( ( _ ) => const Stream<bool>.empty() );
    when( () => tts.queueDepth ).thenReturn( 0 );
    when( () => tts.queueDepthStream ).thenAnswer( ( _ ) => const Stream<int>.empty() );
    GetIt.instance.registerSingleton<TtsOrchestrator>( tts );
  } );

  tearDown( () async { await GetIt.instance.reset(); } );

  Future<void> mount( WidgetTester tester, Map<String, dynamic>? options ) async {
    final state = QuickAskState( connected: true, pendingPrompt: QuickAskPrompt(
      id: 'p1', question: 'Pick one', responseType: 'multiple_choice', responseOptions: options ) );
    whenListen( bloc, Stream<QuickAskState>.fromIterable( const [] ), initialState: state );
    await tester.pumpWidget( MaterialApp(
      home: BlocProvider<QuickAskBloc>.value( value: bloc, child: const QuickAskScreen() ),
    ) );
    await tester.pump();
  }

  Future<void> tapVisible( WidgetTester tester, Finder f ) async {
    await tester.ensureVisible( f );
    await tester.pump();
    await tester.tap( f );
    await tester.pump();
  }

  Map<String, dynamic> sentAnswer() {
    final sent = verify( () => bloc.add( captureAny( that: isA<QuickAskPromptAnswered>() ) ) )
        .captured.single as QuickAskPromptAnswered;
    return jsonDecode( sent.answer ) as Map<String, dynamic>;
  }

  const submit = Key( TestKeys.promptMultiQuestionSubmit );
  const other  = Key( '${TestKeys.promptMultiQuestionOtherFieldPrefix}0' );

  testWidgets( 'single-select: options and Other show, and a pick is sent as answers', ( tester ) async {
    await mount( tester, _single );

    expect( find.byType( MultiQuestionPromptBody ), findsOneWidget );
    expect( find.text( 'Postgres' ), findsOneWidget );
    expect( find.text( 'Other' ), findsOneWidget );

    await tapVisible( tester, find.text( 'SQLite' ) );
    await tapVisible( tester, find.byKey( submit ) );

    expect( sentAnswer(), { 'answers': { 'Database': 'SQLite' } } );
  } );

  testWidgets( 'single-select: a typed Other answer is sent as answers', ( tester ) async {
    await mount( tester, _single );

    await tester.ensureVisible( find.byKey( other ) );
    await tester.enterText( find.byKey( other ), 'MySQL' );
    await tester.pump();
    await tapVisible( tester, find.byKey( submit ) );

    expect( sentAnswer(), { 'answers': { 'Database': 'MySQL' } } );
  } );

  testWidgets( 'multi-select: ticked labels plus the Other text are sent as a list', ( tester ) async {
    await mount( tester, _multi );

    await tapVisible( tester, find.text( 'eu-west' ) );
    await tester.ensureVisible( find.byKey( other ) );
    await tester.enterText( find.byKey( other ), 'ap-south' );
    await tester.pump();
    await tapVisible( tester, find.byKey( submit ) );

    expect( sentAnswer(), { 'answers': { 'Regions': [ 'eu-west', 'ap-south' ] } } );
  } );

  testWidgets( 'the boxes offer no mic, because the screen\'s recorder owns the microphone', ( tester ) async {
    await mount( tester, _single );
    final body = tester.widget<MultiQuestionPromptBody>( find.byType( MultiQuestionPromptBody ) );
    expect( body.dictate, isFalse );
  } );

  testWidgets( 'a multiple-choice ask with no questions still gets the free-text box', ( tester ) async {
    await mount( tester, null );
    expect( find.byType( MultiQuestionPromptBody ), findsNothing );
    expect( find.byType( OpenEndedPromptBody ), findsOneWidget );
  } );
}
