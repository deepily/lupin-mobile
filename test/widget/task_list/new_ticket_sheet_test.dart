import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/fleet/data/task_write_repository.dart';
import 'package:lupin_mobile/features/task_list/data/task_list_repository.dart';
import 'package:lupin_mobile/features/task_list/domain/task_list_bloc.dart';
import 'package:lupin_mobile/features/task_list/presentation/task_list_pane.dart';
import 'package:lupin_mobile/services/asr/asr_service.dart';
import 'package:lupin_mobile/services/asr/voice_capture_session.dart';
import 'package:mocktail/mocktail.dart';

/// M4, the New Ticket card, driven through the REAL pane and asserting what reaches the
/// wire (row b31a9ed9). A card test that stubbed `createTicket` would prove the card
/// and never the POST.
class _Recorder extends Interceptor {
  final List<RequestOptions> calls = [];
  Response<dynamic> Function( RequestOptions ) onPost;

  _Recorder( this.onPost );

  @override
  void onRequest( RequestOptions options, RequestInterceptorHandler handler ) {
    calls.add( options );
    final res = options.method == 'POST'
        ? onPost( options )
        : Response<dynamic>( requestOptions: options, statusCode: 200, data: {
            'tasks': <dynamic>[], 'total': 0, 'has_more': false, 'truncated': false,
            'warnings': <String>[],
          } );
    if ( ( res.statusCode ?? 200 ) >= 400 ) {
      handler.reject( DioException( requestOptions: options, response: res ) );
    } else {
      handler.resolve( res );
    }
  }

  List<RequestOptions> get posts => calls.where( ( c ) => c.method == 'POST' ).toList();
  int get boardReads => calls.where( ( c ) => c.method == 'GET' && c.path == TaskListRepository.path ).length;
}

class _MockAsr extends Mock implements AsrService {}

Response<dynamic> _created( RequestOptions o ) => Response<dynamic>(
  requestOptions: o, statusCode: 201,
  data: { 'id': 'b31a9ed9-0000-0000-0000-000000000000', 'status': 'queued' },
);

Future<_Recorder> _mount( WidgetTester tester, {
  Response<dynamic> Function( RequestOptions )? onPost,
  VoiceCaptureSession? voice,
} ) async {
  tester.view.physicalSize     = const Size( 1080, 2400 );
  tester.view.devicePixelRatio = 3.0;
  addTearDown( tester.view.reset );

  final rec = _Recorder( onPost ?? _created );
  final dio = Dio( BaseOptions( baseUrl: 'http://test' ) )..interceptors.add( rec );
  await tester.pumpWidget( MaterialApp(
    home : Scaffold(
      body : BlocProvider<TaskListBloc>(
        create : ( _ ) => TaskListBloc(
          TaskListRepository( dio ),
          TaskWriteRepository( dio, actorEmail: () => 'rick@example.com' ),
          voice : voice,
        ),
        child : const TaskListPane(),
      ),
    ),
  ) );
  await tester.pumpAndSettle();
  return rec;
}

Future<void> _open( WidgetTester tester ) async {
  await tester.tap( find.byKey( const Key( TestKeys.taskListNewTask ) ) );
  await tester.pumpAndSettle();
}

Future<void> _create( WidgetTester tester ) async {
  await tester.ensureVisible( find.byKey( const Key( TestKeys.newTicketCreate ) ) );
  await tester.tap( find.byKey( const Key( TestKeys.newTicketCreate ) ) );
  await tester.pumpAndSettle();
}

String _result( WidgetTester tester ) =>
    tester.widget<Text>( find.byKey( const Key( TestKeys.newTicketResult ) ) ).data!;

Map<String, dynamic> _sent( RequestOptions o ) =>
    o.data is String ? jsonDecode( o.data as String ) as Map<String, dynamic> : Map<String, dynamic>.from( o.data as Map );

void main() {
  testWidgets( 'the button is enabled and opens the card', ( tester ) async {
    await _mount( tester );
    final button = find.byKey( const Key( TestKeys.taskListNewTask ) );
    expect( tester.widget<ButtonStyleButton>( button ).onPressed, isNotNull );
    await _open( tester );
    expect( find.byKey( const Key( TestKeys.newTicketSheet ) ), findsOneWidget );
  } );

  testWidgets( "the card carries the web's nine fields, in the web's order", ( tester ) async {
    await _mount( tester );
    await _open( tester );
    const order = [
      TestKeys.newTicketTitle, TestKeys.newTicketDetails, TestKeys.newTicketOwner,
      TestKeys.newTicketManager, TestKeys.newTicketPriority, TestKeys.newTicketApproved,
      TestKeys.newTicketType, TestKeys.newTicketEpic, TestKeys.newTicketProject,
    ];
    final tops = [ for ( final k in order ) tester.getTopLeft( find.byKey( Key( k ) ) ).dy ];
    expect( tops, orderedEquals( [ ...tops ]..sort() ) );
  } );

  testWidgets( 'a blank title is refused WITHOUT a request', ( tester ) async {
    final rec = await _mount( tester );
    await _open( tester );
    await _create( tester );
    expect( rec.posts, isEmpty );
    expect( _result( tester ), 'A title is required.' );
  } );

  testWidgets( '🔴 created: the POST carries the defaults, the card closes, the board refreshes',
      ( tester ) async {
    final rec = await _mount( tester );
    final readsBefore = rec.boardReads;
    await _open( tester );
    await tester.enterText( find.byKey( const Key( TestKeys.newTicketTitle ) ), 'Fix the spinner' );
    await _create( tester );

    final body = _sent( rec.posts.single );
    expect( rec.posts.single.path, '/api/tasks' );
    expect( body, {
      'item_class': 'task', 'title': 'Fix the spinner', 'project': 'lupin', 'created_by': 'rick',
      'priority': 'P2', 'status': 'queued', 'correlation_key': 'epic:unassigned',
    } );
    expect( find.byKey( const Key( TestKeys.newTicketSheet ) ), findsNothing );
    expect( find.text( 'Created b31a9ed9 — on the board.' ), findsOneWidget );
    expect( rec.boardReads, greaterThan( readsBefore ) );
  } );

  testWidgets( 'not approved is sent as not_approved', ( tester ) async {
    final rec = await _mount( tester );
    await _open( tester );
    await tester.enterText( find.byKey( const Key( TestKeys.newTicketTitle ) ), 't' );
    await tester.tap( find.byKey( const Key( TestKeys.newTicketApproved ) ) );
    await tester.pumpAndSettle();
    await tester.tap( find.text( 'Not approved — holding area' ).last );
    await tester.pumpAndSettle();
    await _create( tester );
    expect( _sent( rec.posts.single )[ 'status' ], 'not_approved' );
  } );

  testWidgets( '🔴 a petition keeps the card OPEN — the row exists but was not granted', ( tester ) async {
    await _mount( tester, onPost: ( o ) => Response<dynamic>( requestOptions: o, statusCode: 201,
        data: { 'id': 'abcdef12-x', 'status': 'not_approved', 'petition': { 'asked': 'P0' } } ) );
    await _open( tester );
    await tester.enterText( find.byKey( const Key( TestKeys.newTicketTitle ) ), 't' );
    await _create( tester );
    expect( find.byKey( const Key( TestKeys.newTicketSheet ) ), findsOneWidget );
    expect( _result( tester ), contains( 'not on the board yet' ) );
  } );

  testWidgets( '🔴 no answer keeps the card open and warns the row may already exist', ( tester ) async {
    await _mount( tester, onPost: ( o ) => throw DioException( requestOptions: o ) );
    await _open( tester );
    await tester.enterText( find.byKey( const Key( TestKeys.newTicketTitle ) ), 't' );
    await _create( tester );
    expect( find.byKey( const Key( TestKeys.newTicketSheet ) ), findsOneWidget );
    expect( _result( tester ), contains( 'may already be saved' ) );
  } );

  testWidgets( "a 422 shows the server's own words", ( tester ) async {
    await _mount( tester, onPost: ( o ) => Response<dynamic>( requestOptions: o, statusCode: 422,
        data: { 'detail': 'no epic key' } ) );
    await _open( tester );
    await tester.enterText( find.byKey( const Key( TestKeys.newTicketTitle ) ), 't' );
    await _create( tester );
    expect( _result( tester ), 'no epic key' );
  } );

  group( 'mics', () {
    testWidgets( 'no voice session, no mics — as on the web', ( tester ) async {
      await _mount( tester );
      await _open( tester );
      expect( find.byKey( const Key( TestKeys.newTicketTitleMic ) ), findsNothing );
      expect( find.byKey( const Key( TestKeys.newTicketDetailsMic ) ), findsNothing );
    } );

    testWidgets( 'dictation lands in Details and keeps what was typed', ( tester ) async {
      final asr = _MockAsr();
      when( () => asr.startRecording() ).thenAnswer( ( _ ) async {} );
      when( () => asr.cancelRecording() ).thenAnswer( ( _ ) async {} );
      when( () => asr.isCapturing ).thenReturn( false );
      when( () => asr.stopAndTranscribe() ).thenAnswer( ( _ ) async => 'from the phone' );
      final voice = VoiceCaptureSession( asr: asr, requestPermission: () async => true );

      final rec = await _mount( tester, voice: voice );
      await _open( tester );
      await tester.enterText( find.byKey( const Key( TestKeys.newTicketTitle ) ), 't' );
      await tester.enterText( find.byKey( const Key( TestKeys.newTicketDetails ) ), 'Typed first.' );
      await tester.tap( find.byKey( const Key( TestKeys.newTicketDetailsMic ) ) );   // start
      await tester.pumpAndSettle();
      await tester.tap( find.byKey( const Key( TestKeys.newTicketDetailsMic ) ) );   // stop
      await tester.pumpAndSettle();
      await _create( tester );
      expect( _sent( rec.posts.single )[ 'body' ], 'Typed first. from the phone' );
    } );
  } );
}
