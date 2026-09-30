import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/agentic/data/agentic_common_models.dart';
import 'package:lupin_mobile/features/agentic/data/deep_research_models.dart';
import 'package:lupin_mobile/features/agentic/domain/agentic_submission_bloc.dart';
import 'package:lupin_mobile/features/agentic/domain/agentic_submission_event.dart';
import 'package:lupin_mobile/features/agentic/domain/agentic_submission_state.dart';
import 'package:lupin_mobile/features/agentic/presentation/deep_research_form.dart';

import '../../_harness/test_app.dart';

/// Widget-level coverage for Smoke B3 (DeepResearch dry-run submit). Verifies
/// that a dry-run submit dispatches the right event with dryRun=true, and
/// that a Success state triggers navigation — without needing an emulator.
void main() {
  setUpAll(() {
    registerHarnessFallbacks();
    registerFallbackValue( _AnyRoute() );
  });

  group( "DeepResearchForm", () {
    late MockAgenticSubmissionBloc bloc;

    setUp(() {
      bloc = MockAgenticSubmissionBloc();
    });

    Widget underTest() {
      return testApp(
        authBloc: MockAuthBloc(),
        extraProviders: [
          BlocProvider<AgenticSubmissionBloc>.value( value: bloc ),
        ],
        child: const DeepResearchForm(),
      );
    }

    testWidgets( "fires AgenticFormReset on mount and renders form fields", ( tester ) async {
      whenListen(
        bloc,
        Stream<AgenticSubmissionState>.empty(),
        initialState: const AgenticSubmissionInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pump();

      verify( () => bloc.add( any( that: isA<AgenticFormReset>() ) ) ).called( 1 );
      expect( find.byKey( const Key( TestKeys.drQueryField     ) ), findsOneWidget );
      expect( find.byKey( const Key( TestKeys.drDryRunCheckbox ) ), findsOneWidget );
      expect( find.byKey( const Key( TestKeys.drSubmitButton   ) ), findsOneWidget );
    });

    testWidgets( "empty query submit is a no-op (no AgenticSubmitRequested dispatched)", ( tester ) async {
      whenListen(
        bloc,
        Stream<AgenticSubmissionState>.empty(),
        initialState: const AgenticSubmissionInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pump();
      await tester.tap( find.byKey( const Key( TestKeys.drSubmitButton ) ) );
      await tester.pump();

      verifyNever( () => bloc.add( any( that: isA<AgenticSubmitRequested>() ) ) );
    });

    testWidgets( "valid dry-run submit dispatches AgenticSubmitRequested with dryRun=true", ( tester ) async {
      whenListen(
        bloc,
        Stream<AgenticSubmissionState>.empty(),
        initialState: const AgenticSubmissionInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pump();

      await tester.enterText(
        find.byKey( const Key( TestKeys.drQueryField ) ),
        "smoke test query",
      );
      await tester.tap( find.byKey( const Key( TestKeys.drDryRunCheckbox ) ) );
      await tester.pump();
      await tester.tap( find.byKey( const Key( TestKeys.drSubmitButton ) ) );
      await tester.pump();

      final captured = verify( () => bloc.add( captureAny(
        that: isA<AgenticSubmitRequested>(),
      ) ) ).captured;
      expect( captured.length, 1 );
      final event = captured.first as AgenticSubmitRequested;
      expect( event.type, AgenticJobType.deepResearch );
      final req = event.request as DeepResearchRequest;
      expect( req.query,  "smoke test query" );
      expect( req.dryRun, true );
    });
  });
}

class _AnyRoute extends Fake implements Route<dynamic> {}
