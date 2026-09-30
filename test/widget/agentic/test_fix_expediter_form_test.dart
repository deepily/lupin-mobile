import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/agentic/data/agentic_common_models.dart';
import 'package:lupin_mobile/features/agentic/data/test_fix_expediter_models.dart';
import 'package:lupin_mobile/features/agentic/domain/agentic_submission_bloc.dart';
import 'package:lupin_mobile/features/agentic/domain/agentic_submission_event.dart';
import 'package:lupin_mobile/features/agentic/domain/agentic_submission_state.dart';
import 'package:lupin_mobile/features/agentic/presentation/test_fix_expediter_form.dart';

import '../../_harness/test_app.dart';

void main() {
  setUpAll( () {
    registerHarnessFallbacks();
    registerFallbackValue( _AnyRoute() );
  } );

  group( "TestFixExpediterForm", () {
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
        child: const TestFixExpediterForm(),
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
      expect( find.byKey( const Key( TestKeys.tfeResumeFromField ) ), findsOneWidget );
      expect( find.byKey( const Key( TestKeys.tfeSubmitButton    ) ), findsOneWidget );
    } );

    testWidgets( "empty resumeFrom submit is a no-op", ( tester ) async {
      whenListen(
        bloc,
        Stream<AgenticSubmissionState>.empty(),
        initialState: const AgenticSubmissionInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pump();
      await tester.tap( find.byKey( const Key( TestKeys.tfeSubmitButton ) ) );
      await tester.pump();

      verifyNever( () => bloc.add( any( that: isA<AgenticSubmitRequested>() ) ) );
    } );

    testWidgets( "valid submit dispatches with testFixExpediter type and resumeFrom", ( tester ) async {
      whenListen(
        bloc,
        Stream<AgenticSubmissionState>.empty(),
        initialState: const AgenticSubmissionInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pump();

      await tester.enterText(
        find.byKey( const Key( TestKeys.tfeResumeFromField ) ),
        "tfe-prior-abc",
      );
      await tester.tap( find.byKey( const Key( TestKeys.tfeSubmitButton ) ) );
      await tester.pump();

      final captured = verify( () => bloc.add( captureAny(
        that: isA<AgenticSubmitRequested>(),
      ) ) ).captured;
      expect( captured.length, 1 );
      final event = captured.first as AgenticSubmitRequested;
      expect( event.type, AgenticJobType.testFixExpediter );
      final req = event.request as TfeResumeFromRequest;
      expect( req.resumeFrom, "tfe-prior-abc" );
    } );
  } );
}

class _AnyRoute extends Fake implements Route<dynamic> {}
