import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/agentic/data/agentic_common_models.dart';
import 'package:lupin_mobile/features/agentic/data/bug_fix_expediter_models.dart';
import 'package:lupin_mobile/features/agentic/domain/agentic_submission_bloc.dart';
import 'package:lupin_mobile/features/agentic/domain/agentic_submission_event.dart';
import 'package:lupin_mobile/features/agentic/domain/agentic_submission_state.dart';
import 'package:lupin_mobile/features/agentic/presentation/bug_fix_expediter_form.dart';

import '../../_harness/test_app.dart';

void main() {
  setUpAll( () {
    registerHarnessFallbacks();
    registerFallbackValue( _AnyRoute() );
  } );

  group( "BugFixExpediterForm", () {
    late MockAgenticSubmissionBloc bloc;

    setUp( () {
      bloc = MockAgenticSubmissionBloc();
    } );

    Widget underTest( { String? deadJobId } ) {
      return testApp(
        authBloc: MockAuthBloc(),
        extraProviders: [
          BlocProvider<AgenticSubmissionBloc>.value( value: bloc ),
        ],
        child: BugFixExpediterForm( deadJobId: deadJobId ),
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
      expect( find.byKey( const Key( TestKeys.bfeDeadJobIdField ) ), findsOneWidget );
      expect( find.byKey( const Key( TestKeys.bfeDryRunSwitch   ) ), findsOneWidget );
      expect( find.byKey( const Key( TestKeys.bfeSubmitButton   ) ), findsOneWidget );
    } );

    testWidgets( "empty deadJobId submit is a no-op", ( tester ) async {
      whenListen(
        bloc,
        Stream<AgenticSubmissionState>.empty(),
        initialState: const AgenticSubmissionInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pump();
      await tester.tap( find.byKey( const Key( TestKeys.bfeSubmitButton ) ) );
      await tester.pump();

      verifyNever( () => bloc.add( any( that: isA<AgenticSubmitRequested>() ) ) );
    } );

    testWidgets( "deadJobId constructor param pre-fills the field", ( tester ) async {
      whenListen(
        bloc,
        Stream<AgenticSubmissionState>.empty(),
        initialState: const AgenticSubmissionInitial(),
      );

      await tester.pumpWidget( underTest( deadJobId: "bfe-dead-abc" ) );
      await tester.pump();

      final textField = tester.widget<TextField>(
        find.byKey( const Key( TestKeys.bfeDeadJobIdField ) ),
      );
      expect( textField.controller?.text, "bfe-dead-abc" );
    } );

    testWidgets( "valid submit dispatches with bugFixExpediter type", ( tester ) async {
      whenListen(
        bloc,
        Stream<AgenticSubmissionState>.empty(),
        initialState: const AgenticSubmissionInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pump();

      await tester.enterText(
        find.byKey( const Key( TestKeys.bfeDeadJobIdField ) ),
        "bfe-old-dead",
      );
      await tester.tap( find.byKey( const Key( TestKeys.bfeDryRunSwitch ) ) );
      await tester.pump();
      await tester.tap( find.byKey( const Key( TestKeys.bfeSubmitButton ) ) );
      await tester.pump();

      final captured = verify( () => bloc.add( captureAny(
        that: isA<AgenticSubmitRequested>(),
      ) ) ).captured;
      expect( captured.length, 1 );
      final event = captured.first as AgenticSubmitRequested;
      expect( event.type, AgenticJobType.bugFixExpediter );
      final req = event.request as BugFixExpediterRequest;
      expect( req.deadJobId, "bfe-old-dead" );
      expect( req.dryRun,    true );
    } );
  } );
}

class _AnyRoute extends Fake implements Route<dynamic> {}
