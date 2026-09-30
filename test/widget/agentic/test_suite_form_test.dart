import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/agentic/data/agentic_common_models.dart';
import 'package:lupin_mobile/features/agentic/data/test_suite_models.dart';
import 'package:lupin_mobile/features/agentic/domain/agentic_submission_bloc.dart';
import 'package:lupin_mobile/features/agentic/domain/agentic_submission_event.dart';
import 'package:lupin_mobile/features/agentic/domain/agentic_submission_state.dart';
import 'package:lupin_mobile/features/agentic/presentation/test_suite_form.dart';

import '../../_harness/test_app.dart';

void main() {
  setUpAll( () {
    registerHarnessFallbacks();
    registerFallbackValue( _AnyRoute() );
  } );

  group( "TestSuiteForm", () {
    late MockAgenticSubmissionBloc bloc;

    setUp( () {
      bloc = MockAgenticSubmissionBloc();
    } );

    Widget underTest() {
      return testApp(
        authBloc: MockAuthBloc(),
        extraProviders: [
          BlocProvider<AgenticSubmissionBloc>.value( value: bloc ),
        ],
        child: const TestSuiteForm(),
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
      // Default form has integration + e2e pre-selected
      expect( find.byKey( Key( "${TestKeys.tsTestTypeCheckboxPrefix}integration" ) ), findsOneWidget );
      expect( find.byKey( Key( "${TestKeys.tsTestTypeCheckboxPrefix}e2e"         ) ), findsOneWidget );
      expect( find.byKey( Key( "${TestKeys.tsTestTypeCheckboxPrefix}unit"        ) ), findsOneWidget );
      expect( find.byKey( Key( "${TestKeys.tsTestTypeCheckboxPrefix}websocket"   ) ), findsOneWidget );
      expect( find.byKey( const Key( TestKeys.tsAutoFixSwitch ) ), findsOneWidget );
      expect( find.byKey( const Key( TestKeys.tsDryRunSwitch  ) ), findsOneWidget );
      expect( find.byKey( const Key( TestKeys.tsSubmitButton  ) ), findsOneWidget );
    } );

    testWidgets( "default selection submit dispatches with testSuite type and test_types 'integration,e2e'", ( tester ) async {
      whenListen(
        bloc,
        Stream<AgenticSubmissionState>.empty(),
        initialState: const AgenticSubmissionInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pump();
      await tester.tap( find.byKey( const Key( TestKeys.tsSubmitButton ) ) );
      await tester.pump();

      final captured = verify( () => bloc.add( captureAny(
        that: isA<AgenticSubmitRequested>(),
      ) ) ).captured;
      expect( captured.length, 1 );
      final event = captured.first as AgenticSubmitRequested;
      expect( event.type, AgenticJobType.testSuite );
      final req = event.request as TestSuiteRequest;
      expect( req.testTypes, "integration,e2e" );
    } );

    testWidgets( "unchecking all types makes submit a no-op", ( tester ) async {
      whenListen(
        bloc,
        Stream<AgenticSubmissionState>.empty(),
        initialState: const AgenticSubmissionInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pump();
      // Uncheck the two pre-selected types
      await tester.tap( find.byKey( Key( "${TestKeys.tsTestTypeCheckboxPrefix}integration" ) ) );
      await tester.pump();
      await tester.tap( find.byKey( Key( "${TestKeys.tsTestTypeCheckboxPrefix}e2e" ) ) );
      await tester.pump();
      await tester.tap( find.byKey( const Key( TestKeys.tsSubmitButton ) ) );
      await tester.pump();

      verifyNever( () => bloc.add( any( that: isA<AgenticSubmitRequested>() ) ) );
    } );
  } );
}

class _AnyRoute extends Fake implements Route<dynamic> {}
