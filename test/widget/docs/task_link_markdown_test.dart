import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/di/service_locator.dart';
import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/docs/data/doc_repository.dart';
import 'package:lupin_mobile/features/docs/presentation/abstract_body.dart';
import 'package:lupin_mobile/features/docs/presentation/task_link_markdown.dart';
import 'package:lupin_mobile/features/fleet/data/task_write_repository.dart';
import 'package:lupin_mobile/features/task_list/data/task_list_repository.dart';

const _id  = 'a25f51b3-8c0e-4f58-a1f8-f189e250d36c';

/// Answers every request from a callback and records what was sent.
class _Wire extends Interceptor {
  final List<RequestOptions> sent = <RequestOptions>[];
  final Future<Response<dynamic>> Function( RequestOptions ) answer;
  _Wire( this.answer );

  @override
  void onRequest( RequestOptions o, RequestInterceptorHandler h ) {
    sent.add( o );
    answer( o ).then( h.resolve ).catchError( ( Object e ) {
      h.reject( e as DioException );
    } );
  }

  List<RequestOptions> get gets  => sent.where( ( o ) => o.method == 'GET' ).toList();
  List<RequestOptions> get posts => sent.where( ( o ) => o.method == 'POST' ).toList();
}

Response<dynamic> _ok( RequestOptions o, Object data ) =>
    Response<dynamic>( requestOptions: o, statusCode: 200, data: data );

Map<String, dynamic> _row( String status, { String? body } ) => <String, dynamic>{
      'id' : _id, 'title' : 'Ship the thing', 'status' : status, 'priority' : 'P1',
      'owner_persona' : 'rio', 'body' : body ?? 'line one',
    };

DioException _refuse( RequestOptions o, int code, Object data ) => DioException(
      requestOptions : o,
      response       : Response<dynamic>( requestOptions: o, statusCode: code, data: data ),
      type           : DioExceptionType.badResponse,
    );

String _md( { String second = '' } ) =>
    '- Ship [approve ☐](/app/tasks/approve?row=$_id) [📄](/app/tasks/view?row=$_id)\n$second';

Future<_Wire> _mount( WidgetTester tester, String md, Future<Response<dynamic>> Function( RequestOptions ) answer ) async {
  final wire = _Wire( answer );
  final dio  = Dio( BaseOptions( baseUrl: 'http://test' ) )..interceptors.add( wire );
  await tester.pumpWidget( MaterialApp( home: Scaffold(
    body: TaskLinkMarkdown(
      data       : md,
      repository : TaskWriteRepository( dio, actorEmail: () => 'rick@example.com' ),
      reader     : TaskListRepository( dio ),
    ),
  ) ) );
  await tester.pumpAndSettle();
  return wire;
}

const _approveHref = '/app/tasks/approve?row=$_id';
const _viewHref    = '/app/tasks/view?row=$_id';

// Selectable text has no text-range finder, so a tap is delivered the way the Markdown
// widget delivers it: through its onTapLink callback with the link's address.
Future<void> _tapLink( WidgetTester tester, String href, [ String label = '' ] ) async {
  tester.widget<Markdown>( find.byType( Markdown ) ).onTapLink!( label, href, '' );
  await tester.pump( const Duration( milliseconds: 50 ) );
}

Finder _label() => find.textContaining( 'approve ☐', findRichText: true );

void main() {
  group( 'approve link', () {
    testWidgets( 'a tap POSTs to_status queued, then reads "approved ✅"', ( tester ) async {
      final wire = await _mount( tester, _md(), ( o ) async =>
          o.method == 'GET' ? _ok( o, _row( 'not_approved' ) ) : _ok( o, { 'status': 'queued' } ) );
      expect( _label(), findsOneWidget, reason: 'a held row keeps the live link' );

      await _tapLink( tester, _approveHref );
      await tester.pumpAndSettle();

      expect( wire.posts, hasLength( 1 ) );
      expect( wire.posts.single.path, '/api/tasks/$_id/transition' );
      expect( ( wire.posts.single.data as Map )[ 'to_status' ], 'queued' );
      expect( find.textContaining( 'approved ✅', findRichText: true ), findsOneWidget );
      expect( _label(), findsNothing );
    } );

    testWidgets( 'a refusal shows the server reason word for word', ( tester ) async {
      await _mount( tester, _md(), ( o ) async {
        if ( o.method == 'GET' ) return _ok( o, _row( 'not_approved' ) );
        throw _refuse( o, 403, { 'detail': 'Only Rick may approve P0 rows.' } );
      } );

      await _tapLink( tester, _approveHref );
      await tester.pumpAndSettle();

      expect( find.textContaining( 'Only Rick may approve P0 rows.', findRichText: true ), findsOneWidget );
      expect( find.textContaining( 'approved ✅', findRichText: true ), findsNothing );
    } );

    testWidgets( 'a second tap while the request is out sends nothing', ( tester ) async {
      final gate = Completer<Response<dynamic>>();
      final wire = await _mount( tester, _md(), ( o ) =>
          o.method == 'GET' ? Future.value( _ok( o, _row( 'not_approved' ) ) ) : gate.future );

      await _tapLink( tester, _approveHref );
      expect( _label(), findsOneWidget, reason: 'plain label while sending' );
      expect( find.textContaining( 'approve ☐', findRichText: true ), findsOneWidget, reason: 'plain label, not a link' );
      await _tapLink( tester, _approveHref );

      expect( wire.posts, hasLength( 1 ) );
      gate.complete( _ok( wire.posts.single, { 'status': 'queued' } ) );
      await tester.pumpAndSettle();
      expect( find.textContaining( 'approved ✅', findRichText: true ), findsOneWidget );
    } );

    testWidgets( 'a reason with HTML entities is shown exactly as sent', ( tester ) async {
      const reason = 'Rows need &amp; review &lt;b&gt; &#35;1 <i>now</i> [x](y)';
      await _mount( tester, _md(), ( o ) async {
        if ( o.method == 'GET' ) return _ok( o, _row( 'not_approved' ) );
        throw _refuse( o, 403, { 'detail': reason } );
      } );

      await _tapLink( tester, _approveHref );
      await tester.pumpAndSettle();

      expect( find.textContaining( reason, findRichText: true ), findsOneWidget );
    } );

    testWidgets( 'a held-for-approval answer is shown, not painted approved', ( tester ) async {
      await _mount( tester, _md(), ( o ) async => o.method == 'GET'
          ? _ok( o, _row( 'not_approved' ) )
          : Response<dynamic>( requestOptions: o, statusCode: 202, data: { 'status': 'awaiting_human_approval', 'ticket_id': 't1' } ) );

      await _tapLink( tester, _approveHref );
      await tester.pumpAndSettle();

      expect( find.textContaining( 'approved ✅', findRichText: true ), findsNothing );
      expect( find.textContaining( 'awaiting_human_approval', findRichText: true ), findsOneWidget );
    } );
  } );

  group( 'redrawn card reads each row once', () {
    testWidgets( 'a row named twice is read once', ( tester ) async {
      final wire = await _mount( tester, _md( second: '- Again [approve ☐](/app/tasks/approve?row=$_id)' ),
          ( o ) async => _ok( o, _row( 'not_approved' ) ) );

      expect( wire.gets, hasLength( 1 ) );
      expect( _label(), findsNWidgets( 2 ) );
    } );

    for ( final live in <String>[ 'queued', 'in_progress', 'done' ] ) {
      testWidgets( 'a $live row shows approved ✅ without a tap', ( tester ) async {
        await _mount( tester, _md(), ( o ) async => _ok( o, _row( live ) ) );
        expect( find.textContaining( 'approved ✅', findRichText: true ), findsOneWidget );
        expect( _label(), findsNothing );
      } );
    }

    for ( final closed in <String>[ 'dropped', 'wont_fix' ] ) {
      testWidgets( 'a $closed row shows that status, never approved', ( tester ) async {
        await _mount( tester, _md(), ( o ) async => _ok( o, _row( closed ) ) );
        expect( find.textContaining( closed, findRichText: true ), findsOneWidget );
        expect( find.textContaining( 'approved ✅', findRichText: true ), findsNothing );
      } );
    }

    testWidgets( 'a failed read leaves the live link', ( tester ) async {
      await _mount( tester, _md(), ( o ) async => throw _refuse( o, 500, 'boom' ) );
      expect( _label(), findsOneWidget );
    } );
  } );

  group( 'view link', () {
    testWidgets( 'a tap GETs the row and shows its fields as plain text', ( tester ) async {
      final wire = await _mount( tester, _md(), ( o ) async =>
          _ok( o, _row( 'not_approved', body: 'a <b>bold</b> **claim**' ) ) );
      final readsBefore = wire.gets.length;

      await _tapLink( tester, _viewHref );
      await tester.pumpAndSettle();

      expect( wire.gets.length, readsBefore + 1 );
      expect( wire.gets.last.path, '/api/tasks/$_id' );
      expect( find.byKey( const Key( TestKeys.taskViewDialog ) ), findsOneWidget );
      expect( find.textContaining( 'Ship the thing' ), findsWidgets );
      expect( find.textContaining( 'Priority: P1 · Owner: rio' ), findsOneWidget );
      expect( find.textContaining( 'a <b>bold</b> **claim**' ), findsOneWidget );
    } );

    testWidgets( 'a failed read says so', ( tester ) async {
      var reads = 0;
      await _mount( tester, _md(), ( o ) async {
        if ( ++reads == 1 ) return _ok( o, _row( 'not_approved' ) );
        throw _refuse( o, 500, 'boom' );
      } );
      await _tapLink( tester, _viewHref );
      await tester.pumpAndSettle();
      expect( find.text( 'Could not read this ticket.' ), findsOneWidget );
    } );
  } );

  group( 'other links', () {
    testWidgets( 'a doc link still reaches onTapLink', ( tester ) async {
      String? tapped;
      final dio = Dio( BaseOptions( baseUrl: 'http://test' ) );
      await tester.pumpWidget( MaterialApp( home: Scaffold(
        body: TaskLinkMarkdown(
          data       : '[Open: x](/app/docs?path=lupin/x.md)',
          repository : TaskWriteRepository( dio ),
          reader     : TaskListRepository( dio ),
          onTapLink  : ( text, href, title ) => tapped = href,
        ),
      ) ) );
      await _tapLink( tester, '/app/docs?path=lupin/x.md' );
      expect( tapped, '/app/docs?path=lupin/x.md' );
    } );
  } );

  group( 'through the abstract card', () {
    testWidgets( 'opening an abstract shows live task links', ( tester ) async {
      final wire = _Wire( ( o ) async => _ok( o, _row( 'not_approved' ) ) );
      final dio  = Dio( BaseOptions( baseUrl: 'http://test' ) )..interceptors.add( wire );
      ServiceLocator.instance.registerSingleton<TaskWriteRepository>( TaskWriteRepository( dio ) );
      ServiceLocator.instance.registerSingleton<TaskListRepository>( TaskListRepository( dio ) );
      addTearDown( () {
        ServiceLocator.instance.unregister<TaskWriteRepository>();
        ServiceLocator.instance.unregister<TaskListRepository>();
      } );

      await tester.pumpWidget( MaterialApp( home: Scaffold(
        body: AbstractBody( abstractText: _md(), repository: DocRepository( dio ) ),
      ) ) );
      await tester.tap( find.byKey( const Key( TestKeys.abstractOpenButton ) ) );
      await tester.pumpAndSettle();

      expect( _label(), findsOneWidget );
      await _tapLink( tester, _approveHref );
      await tester.pumpAndSettle();
      expect( wire.posts.single.path, '/api/tasks/$_id/transition' );
      expect( find.textContaining( 'approved ✅', findRichText: true ), findsOneWidget );
    } );
  } );
}
