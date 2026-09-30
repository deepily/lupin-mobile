import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/features/agentic/domain/agentic_submission_bloc.dart';
import 'package:lupin_mobile/features/agentic/domain/agentic_submission_state.dart';
import 'package:lupin_mobile/features/agentic/presentation/bug_fix_expediter_form.dart';
import 'package:lupin_mobile/features/agentic/presentation/deep_research_form.dart';
import 'package:lupin_mobile/features/agentic/presentation/podcast_generator_form.dart';
import 'package:lupin_mobile/features/agentic/presentation/research_to_podcast_form.dart';
import 'package:lupin_mobile/features/agentic/presentation/research_to_presentation_form.dart';
import 'package:lupin_mobile/features/agentic/presentation/swe_team_form.dart';
import 'package:lupin_mobile/features/agentic/presentation/test_fix_expediter_form.dart';
import 'package:lupin_mobile/services/asr/asr_service.dart';
import 'package:lupin_mobile/shared/widgets/dictation_text_field.dart';

import '../../_harness/test_app.dart';

class _MockAsr extends Mock implements AsrService {}

/// Row c67f9781, step 5 (plus S1 and S2, Rick 2026-09-29): every agentic form's
/// free-prose box has ONE mic, and the identifier / path / number boxes beside it
/// have none. Each form: exactly one mic on screen, and tapping it twice lands the
/// fake transcript in exactly one box.
void main() {
  setUpAll( () {
    registerHarnessFallbacks();
  } );

  final forms = <String, Widget Function()>{
    'bug_fix_expediter (Extra context)'      : () => const BugFixExpediterForm(),
    'deep_research (Research query)'         : () => const DeepResearchForm(),
    'research_to_presentation (Query)'       : () => const ResearchToPresentationForm(),
    'research_to_podcast (Query)'            : () => const ResearchToPodcastForm(),
    'swe_team (Engineering task)'            : () => const SweTeamForm(),
    'podcast_generator (S1, source or text)' : () => const PodcastGeneratorForm(),
    'test_fix_expediter (S2, job or plan)'   : () => const TestFixExpediterForm(),
  };

  for ( final entry in forms.entries ) {
    testWidgets( entry.key, ( t ) async {
      t.view.physicalSize     = const Size( 800, 2400 );
      t.view.devicePixelRatio = 1.0;
      addTearDown( t.view.resetPhysicalSize );
      addTearDown( t.view.resetDevicePixelRatio );

      final asr = _MockAsr();
      when( () => asr.startRecording()    ).thenAnswer( ( _ ) async {} );
      when( () => asr.cancelRecording()   ).thenAnswer( ( _ ) async {} );
      when( () => asr.stopAndTranscribe() ).thenAnswer( ( _ ) async => 'from the phone' );

      final bloc = MockAgenticSubmissionBloc();
      whenListen( bloc, const Stream<AgenticSubmissionState>.empty(),
          initialState: const AgenticSubmissionInitial() );

      await t.pumpWidget( MaterialApp(
        builder : ( c, child ) => DictationScope(
          asr: asr, requestMicPermission: () async => true, child: child! ),
        home    : BlocProvider<AgenticSubmissionBloc>.value( value: bloc, child: entry.value() ),
      ) );
      await t.pump();

      expect( find.byIcon( Icons.mic ), findsOneWidget, reason: 'one prose box, one mic' );
      await t.tap( find.byIcon( Icons.mic ) );
      await t.pump();
      await t.tap( find.byIcon( Icons.stop_circle ) );
      await t.pump();
      await t.pump( const Duration( milliseconds: 20 ) );

      final holding = t.widgetList<TextField>( find.byType( TextField ) )
          .where( ( f ) => f.controller!.text == 'from the phone' );
      expect( holding.length, 1 );
    } );
  }
}
