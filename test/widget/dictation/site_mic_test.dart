import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/features/claude_code/domain/claude_code_bloc.dart';
import 'package:lupin_mobile/features/claude_code/domain/claude_code_event.dart';
import 'package:lupin_mobile/features/claude_code/domain/claude_code_state.dart';
import 'package:lupin_mobile/features/claude_code/presentation/dispatch_sheet.dart';
import 'package:lupin_mobile/features/fleet/data/task_verbs.dart';
import 'package:lupin_mobile/features/fleet/presentation/verb_reason_sheet.dart';
import 'package:lupin_mobile/features/holding_area/data/holding_area_models.dart';
import 'package:lupin_mobile/features/holding_area/presentation/filer_group_header.dart';
import 'package:lupin_mobile/features/queue/data/queue_models.dart';
import 'package:lupin_mobile/features/queue/domain/queue_bloc.dart';
import 'package:lupin_mobile/features/queue/domain/queue_event.dart';
import 'package:lupin_mobile/features/queue/domain/queue_state.dart';
import 'package:lupin_mobile/features/queue/presentation/job_detail_screen.dart';
import 'package:lupin_mobile/features/queue/presentation/submit_job_sheet.dart';
import 'package:lupin_mobile/services/asr/asr_service.dart';
import 'package:lupin_mobile/shared/widgets/dictation_text_field.dart';

class _MockAsr extends Mock implements AsrService {}
class _MockClaudeCodeBloc extends MockBloc<ClaudeCodeEvent, ClaudeCodeState> implements ClaudeCodeBloc {}
class _MockQueueBloc extends MockBloc<QueueEvent, QueueState> implements QueueBloc {}

/// Row c67f9781, one test per migrated site (plan §5): mount the real widget
/// under the app's [DictationScope], tap the mic, tap it again, and the box holds
/// the fake transcript. The site's own tests stay unchanged; this proves the mic
/// is THERE and reaches the site's own controller.
///
/// A site with no scope renders exactly as before; that is the census guard's
/// and the existing tests' job.
void main() {
  late _MockAsr asr;

  setUp( () {
    asr = _MockAsr();
    when( () => asr.startRecording()     ).thenAnswer( ( _ ) async {} );
    when( () => asr.cancelRecording()    ).thenAnswer( ( _ ) async {} );
    when( () => asr.stopAndTranscribe()  ).thenAnswer( ( _ ) async => 'from the phone' );
  } );

  Widget app( Widget home ) => MaterialApp(
    builder : ( context, child ) => DictationScope(
      asr                  : asr,
      requestMicPermission : () async => true,
      child                : child!,
    ),
    home : Scaffold( body: SingleChildScrollView( child: home ) ),
  );

  /// The first box on screen ends up holding the fake transcript.
  Future<void> dictate( WidgetTester t, { int box = 0 } ) async {
    await t.tap( find.byIcon( Icons.mic ).at( box ) );
    await t.pump();
    await t.tap( find.byIcon( Icons.stop_circle ) );
    await t.pump();
    await t.pump( const Duration( milliseconds: 20 ) );
  }

  String textOf( WidgetTester t, int i ) =>
      t.widget<TextField>( find.byType( TextField ).at( i ) ).controller!.text;

  void bigScreen( WidgetTester t ) {
    t.view.physicalSize     = const Size( 800, 1600 );
    t.view.devicePixelRatio = 1.0;
    addTearDown( t.view.resetPhysicalSize );
    addTearDown( t.view.resetDevicePixelRatio );
  }

  testWidgets( 'verb_reason_sheet: Reason', ( t ) async {
    bigScreen( t );
    await t.pumpWidget( MaterialApp(
      builder : ( c, child ) => DictationScope(
        asr: asr, requestMicPermission: () async => true, child: child! ),
      home : Scaffold( body: Builder( builder: ( context ) => TextButton(
        onPressed : () => showVerbReasonSheet( context,
            needs: verbNeeds( 'wont_fix' )!, rowTitle: 'row' ),
        child : const Text( 'open' ),
      ) ) ),
    ) );
    await t.tap( find.text( 'open' ) );
    await t.pumpAndSettle();
    await dictate( t );

    expect( textOf( t, 0 ), 'from the phone' );
  } );

  testWidgets( 'filer_group_header: Won\'t-fix reason, and a busy header has a dead mic', ( t ) async {
    const group = FilerGroup( filer: 'tiffany', rows: [] );
    Widget header( { bool busy = false } ) => app( FilerGroupHeader(
      group           : group,
      reason          : '',
      reasonError     : null,
      busy            : busy,
      expanded        : true,
      onReasonChanged : ( _ ) {},
      onApproveAll    : () {},
      onWontFixAll    : () {},
      onToggle        : () {},
    ) );
    await t.pumpWidget( header() );
    await dictate( t );
    expect( textOf( t, 0 ), 'from the phone' );

    await t.pumpWidget( header( busy: true ) );
    expect( t.widget<IconButton>( find.widgetWithIcon( IconButton, Icons.mic ) ).onPressed, isNull );
  } );

  testWidgets( 'submit_job_sheet: Question / Command', ( t ) async {
    bigScreen( t );
    final queue = _MockQueueBloc();
    whenListen( queue, const Stream<QueueState>.empty(), initialState: QueueInitial() );
    await t.pumpWidget( app( BlocProvider<QueueBloc>.value( value: queue, child: const SubmitJobSheet() ) ) );
    await dictate( t );

    expect( textOf( t, 0 ), 'from the phone' );
  } );

  testWidgets( 'dispatch_sheet: Prompt gets a mic, Project does not', ( t ) async {
    bigScreen( t );
    final cc = _MockClaudeCodeBloc();
    whenListen( cc, const Stream<ClaudeCodeState>.empty(), initialState: ClaudeCodeInitial() );
    await t.pumpWidget( app( BlocProvider<ClaudeCodeBloc>.value( value: cc, child: const DispatchSheet() ) ) );

    expect( find.byIcon( Icons.mic ), findsOneWidget );
    await dictate( t );
    expect( textOf( t, 0 ), 'from the phone' );
    expect( textOf( t, 1 ), '' );
  } );

  testWidgets( 'job_detail_screen: the Message dialog', ( t ) async {
    bigScreen( t );
    final bloc = _MockQueueBloc();
    whenListen( bloc, const Stream<QueueState>.empty(), initialState: QueueInitial() );
    await t.pumpWidget( MaterialApp(
      builder : ( c, child ) => DictationScope(
        asr: asr, requestMicPermission: () async => true, child: child! ),
      home : BlocProvider<QueueBloc>.value(
        value : bloc,
        child : const JobDetailScreen( job: JobSummary( jobId: "j1", status: "running" ) ),
      ),
    ) );
    await t.tap( find.byTooltip( 'Message' ) );
    await t.pumpAndSettle();
    await dictate( t );

    expect( textOf( t, 0 ), 'from the phone' );
  } );
}
