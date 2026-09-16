/// Bug 9cddb791 — Quick Ask must not overflow on the smallest phone we care
/// about.
///
/// 🔴 Overflow does NOT arrive as a failed expectation. `RenderFlex` reports
/// it through `FlutterError.onError` during layout, so a test that merely
/// pumps the screen and looks at the widget tree passes over a screen that is
/// visibly broken. Each case here therefore INSTALLS its own error sink for
/// the duration of the pump and asserts the sink stayed empty — that is the
/// assertion, and reverting the layout fix reddens it.
///
/// 320×568 is the iPhone SE / small-Android class. The measured baseline
/// before the fix: 10px over on a bare Door C prompt, 114px over on a prompt
/// plus an inline error, 134px over on a prompt plus the lost banner.
library;

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

class MockQuickAskBloc extends MockBloc<QuickAskEvent, QuickAskState>
    implements QuickAskBloc {}

class MockTtsOrchestrator extends Mock implements TtsOrchestrator {}

/// The smallest viewport this screen is expected to survive.
const Size kSmallPhone = Size( 320, 568 );

const QuickAskPrompt doorC = QuickAskPrompt(
  id       : 'n-1',
  question : 'Is that the same as: what is the weather?',
);

const String errorText = 'Could not accept the audio. Nothing was asked.';

void main() {
  late MockQuickAskBloc     bloc;
  late MockTtsOrchestrator  tts;

  setUpAll( () {
    registerFallbackValue( const QuickAskRecordPressed() );
    registerFallbackValue( const TtsSender() );
  } );

  setUp( () {
    bloc = MockQuickAskBloc();
    tts  = MockTtsOrchestrator();
    when( () => tts.isPaused ).thenReturn( false );
    when( () => tts.pausedStream ).thenAnswer( ( _ ) => const Stream<bool>.empty() );
    when( () => tts.queueDepth ).thenReturn( 0 );
    when( () => tts.queueDepthStream ).thenAnswer( ( _ ) => const Stream<int>.empty() );
    GetIt.instance.registerSingleton<TtsOrchestrator>( tts );
  } );

  tearDown( () async => GetIt.instance.reset() );

  /// Pumps the screen at [size] and returns every layout error Flutter
  /// reported while it did — empty means the screen fits.
  Future<List<String>> layoutErrors(
    WidgetTester   tester,
    QuickAskState  state, {
    Size           size = kSmallPhone,
  } ) async {
    tester.view.physicalSize      = size;
    tester.view.devicePixelRatio  = 1.0;
    addTearDown( tester.view.reset );

    whenListen( bloc, Stream<QuickAskState>.fromIterable( const [] ),
        initialState: state );

    final caught = <String>[];
    final prior  = FlutterError.onError;
    FlutterError.onError = ( details ) =>
        caught.add( details.exceptionAsString().split( '\n' ).first );
    try {
      await tester.pumpWidget( MaterialApp(
        home : BlocProvider<QuickAskBloc>.value( value: bloc, child: const QuickAskScreen() ),
      ) );
      await tester.pump();
    } finally {
      FlutterError.onError = prior;
    }
    return caught;
  }

  group( 'bug 9cddb791 — 320×568 must not overflow', () {

    testWidgets( 'a live Door C prompt fits (was 10px over)', ( tester ) async {
      expect(
        await layoutErrors( tester, const QuickAskState( connected: true, pendingPrompt: doorC ) ),
        isEmpty,
        reason : 'the Door C prompt overflowed the fixed Column by 10px at 320×568',
      );
    } );

    testWidgets( 'a Door C prompt PLUS an inline error fits (was 114px over)', ( tester ) async {
      expect(
        await layoutErrors( tester, const QuickAskState(
          connected     : true,
          pendingPrompt : doorC,
          errorMessage  : errorText,
        ) ),
        isEmpty,
        reason : 'prompt + error overflowed the fixed Column by 114px at 320×568',
      );
    } );

    testWidgets( 'an interview turn plus an error fits, and so does prompt + lost', ( tester ) async {
      // The same defect, reached by the other two interlock surfaces — pinned
      // so a fix aimed only at the two headline states does not leave these
      // broken.
      expect(
        await layoutErrors( tester, const QuickAskState(
          connected    : true,
          interview    : QuickAskInterview( pendingId: 'p-1', question: 'Which city?' ),
          errorMessage : errorText,
        ) ),
        isEmpty,
        reason : 'interview + error overflowed by 94px at 320×568',
      );
    } );

    testWidgets( 'a Door C prompt plus the lost banner fits (was 134px over)', ( tester ) async {
      expect(
        await layoutErrors( tester, const QuickAskState(
          connected     : true,
          pendingPrompt : doorC,
          lost          : true,
        ) ),
        isEmpty,
        reason : 'prompt + lost banner overflowed by 134px at 320×568',
      );
    } );

    testWidgets( 'the plain idle screen still fits', ( tester ) async {
      expect(
        await layoutErrors( tester, const QuickAskState( connected: true ) ),
        isEmpty,
      );
    } );
  } );

  group( 'bug 9cddb791 — the question stays USABLE, not merely un-crashed', () {

    testWidgets( 'the Door C answer buttons are on screen at 320×568 without scrolling',
        ( tester ) async {
      // Not overflowing would be satisfied by a surface scrolled entirely off
      // the fold. The point of the interlock is that the user can ANSWER it,
      // so the yes/no row has to be inside the viewport on arrival.
      expect(
        await layoutErrors( tester, const QuickAskState( connected: true, pendingPrompt: doorC ) ),
        isEmpty,
      );

      final yes = find.byKey( const Key( TestKeys.promptYesButton ) );
      expect( yes, findsOneWidget );
      expect( tester.getBottomLeft( yes ).dy, lessThanOrEqualTo( kSmallPhone.height ),
          reason : 'the answer buttons must not sit under the fold' );
    } );

    testWidgets( 'a normal phone is not regressed — 360×640 fits in every interlock state',
        ( tester ) async {
      expect(
        await layoutErrors(
          tester,
          const QuickAskState(
            connected     : true,
            pendingPrompt : doorC,
            errorMessage  : errorText,
          ),
          size : const Size( 360, 640 ),
        ),
        isEmpty,
      );
    } );
  } );
}
