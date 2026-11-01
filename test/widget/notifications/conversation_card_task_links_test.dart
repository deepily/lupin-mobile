import 'package:bloc_test/bloc_test.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lupin_mobile/core/di/service_locator.dart';
import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/docs/data/doc_repository.dart';
import 'package:lupin_mobile/features/fleet/data/task_write_repository.dart';
import 'package:lupin_mobile/features/notifications/data/notification_models.dart';
import 'package:lupin_mobile/features/task_list/data/task_list_repository.dart';
import 'package:lupin_mobile/features/notifications/domain/notification_bloc.dart';
import 'package:lupin_mobile/features/notifications/domain/notification_state.dart';
import 'package:lupin_mobile/features/notifications/presentation/conversation_screen.dart';

import '../../_harness/test_app.dart';
import '../../unit/_helpers/stub_dio.dart';

/// Conversation card tests for the approve and view links in an abstract.
///
/// Each test draws a real card, opens its abstract, and taps a link.
/// A Dio adapter answers with the shapes the task router sends.
/// A transition is 200 with an item and an event. A refusal is 403 with a string detail.
/// A missing row is 404 with "task <id> not found".
const _a = 'a25f51b3-8c0e-4f58-a1f8-f189e250d36c';
const _b = '39624bae-1111-4222-8333-444455556666';

String _line( String id, String title ) =>
    '- $title [approve ☐](/app/tasks/approve?row=$id) [📄](/app/tasks/view?row=$id)';

Map<String, dynamic> _row( String id, String status, { String body = 'Do the thing.\nSecond line.' } ) => {
      'id'            : id,
      'item_class'    : 'task',
      'title'         : 'Title of $id',
      'body'          : body,
      'project'       : 'lupin',
      'owner_persona' : 'rio',
      'status'        : status,
      'priority'      : 'P2',
    };

ResponseBody _transitionOk( String id ) =>
    jsonBody( { 'item': _row( id, 'queued' ), 'event': { 'to_status': 'queued' } } );

ResponseBody _detail( int code, String detail ) => jsonBody( { 'detail': detail }, status: code );

Finder _approveLabel() => find.textContaining( 'approve ☐', findRichText: true );
Finder _approvedText() => find.textContaining( 'approved ✅', findRichText: true );

Future<void> _tapHref( WidgetTester tester, String href ) async {
  tester.widget<Markdown>( find.byType( Markdown ) ).onTapLink!( '', href, '' );
  await tester.pump( const Duration( milliseconds: 50 ) );
}

void main() {
  setUpAll( registerHarnessFallbacks );

  late StubAdapter adapter;
  late MockNotificationBloc bloc;

  List<RequestOptions> posts() => adapter.captured.where( ( o ) => o.method == 'POST' ).toList();
  List<RequestOptions> gets()  => adapter.captured.where( ( o ) => o.method == 'GET' ).toList();

  /// Draws the conversation card carrying [abstractText], then opens its abstract.
  Future<void> openCard( WidgetTester tester, String abstractText, Map<String, ResponseBody Function( RequestOptions )> handlers ) async {
    adapter = StubAdapter( handlers );
    final dio = makeDio( adapter );
    final sl  = ServiceLocator.instance;
    sl.registerSingleton<TaskWriteRepository>( TaskWriteRepository( dio, actorEmail: () => 'rick@example.com' ) );
    sl.registerSingleton<TaskListRepository>( TaskListRepository( dio ) );
    sl.registerSingleton<DocRepository>( DocRepository( dio ) );
    addTearDown( () async {
      await sl.unregister<TaskWriteRepository>();
      await sl.unregister<TaskListRepository>();
      await sl.unregister<DocRepository>();
    } );

    bloc = MockNotificationBloc();
    whenListen(
      bloc,
      Stream<NotificationState>.fromIterable( [
        NotificationsConversationLoaded(
          senderId  : 's-1',
          userEmail : 'u@x.y',
          messages  : [
            ConversationMessage(
              id           : 'c-1',
              message      : 'Two tickets need your approval',
              abstractText : abstractText,
              type         : 'task',
              priority     : 'high',
              state        : 'delivered',
              isHidden     : false,
              responseRequested : false,
              timestamp    : DateTime( 2026, 11, 1, 10 ),
            ),
          ],
        ),
      ] ),
      initialState: const NotificationsInitial(),
    );
    await tester.pumpWidget( testApp(
      authBloc       : MockAuthBloc(),
      extraProviders : [ BlocProvider<NotificationBloc>.value( value: bloc ) ],
      child          : const ConversationScreen( senderId: 's-1', userEmail: 'u@x.y' ),
    ) );
    await tester.pump();
    await tester.tap( find.byKey( const Key( TestKeys.abstractOpenButton ) ) );
    await tester.pumpAndSettle();
  }

  Map<String, ResponseBody Function( RequestOptions )> held( String id ) => {
        'GET /api/tasks/$id'             : ( _ ) => jsonBody( _row( id, 'not_approved' ) ),
        'POST /api/tasks/$id/transition' : ( _ ) => _transitionOk( id ),
      };

  group( 'approve link on a real conversation card', () {
    testWidgets( 'tap sends one POST {to_status: queued}, then reads approved ✅', ( tester ) async {
      await openCard( tester, _line( _a, 'Ship it' ), held( _a ) );
      expect( _approveLabel(), findsOneWidget );

      await _tapHref( tester, '/app/tasks/approve?row=$_a' );
      await tester.pumpAndSettle();

      expect( posts(), hasLength( 1 ) );
      expect( posts().single.path, '/api/tasks/$_a/transition' );
      expect( ( posts().single.data as Map )[ 'to_status' ], 'queued' );
      expect( _approvedText(), findsOneWidget );
      expect( _approveLabel(), findsNothing );
    } );

    testWidgets( 'a 403 refusal shows the server reason verbatim and sends one POST', ( tester ) async {
      const reason = 'Only Rick can approve this row: it is gated to the operator.';
      await openCard( tester, _line( _a, 'Ship it' ), {
        'GET /api/tasks/$_a'             : ( _ ) => jsonBody( _row( _a, 'not_approved' ) ),
        'POST /api/tasks/$_a/transition' : ( _ ) => _detail( 403, reason ),
      } );

      await _tapHref( tester, '/app/tasks/approve?row=$_a' );
      await tester.pumpAndSettle();

      expect( find.textContaining( reason, findRichText: true ), findsOneWidget );
      expect( _approvedText(), findsNothing );
      expect( posts(), hasLength( 1 ) );
    } );

    testWidgets( 'a refusal with an entity and markdown characters shows as typed', ( tester ) async {
      const reason = 'Rick &amp; Tiffany must approve <b>this</b> row: *gated* [see](x) _now_\nTitle\n=====\nnext';
      await openCard( tester, _line( _a, 'Ship it' ), {
        'GET /api/tasks/$_a'             : ( _ ) => jsonBody( _row( _a, 'not_approved' ) ),
        'POST /api/tasks/$_a/transition' : ( _ ) => _detail( 403, reason ),
      } );

      await _tapHref( tester, '/app/tasks/approve?row=$_a' );
      await tester.pumpAndSettle();

      final shown = tester.widgetList<EditableText>( find.byType( EditableText ) ).map( ( e ) => e.controller.text ).join( '|' );
      expect( shown, contains( reason ), reason: 'markdown would turn the = line into a heading and eat the newline' );
      expect( _approvedText(), findsNothing );
    } );

    testWidgets( 'a double tap while the request is out sends exactly one POST', ( tester ) async {
      await openCard( tester, _line( _a, 'Ship it' ), held( _a ) );

      final md = tester.widget<Markdown>( find.byType( Markdown ) );
      md.onTapLink!( '', '/app/tasks/approve?row=$_a', '' );
      md.onTapLink!( '', '/app/tasks/approve?row=$_a', '' );
      await tester.pumpAndSettle();
      await _tapHref( tester, '/app/tasks/approve?row=$_a' ); // a third tap after it settled

      expect( posts(), hasLength( 1 ) );
      expect( _approvedText(), findsOneWidget );
    } );

    testWidgets( 'approving one row leaves the other row live', ( tester ) async {
      await openCard( tester, '${_line( _a, 'One' )}\n${_line( _b, 'Two' )}', { ...held( _a ), ...held( _b ) } );

      await _tapHref( tester, '/app/tasks/approve?row=$_a' );
      await tester.pumpAndSettle();

      expect( posts().single.path, '/api/tasks/$_a/transition' );
      expect( _approvedText(), findsOneWidget );
      expect( _approveLabel(), findsOneWidget );
    } );
  } );

  group( 'view link on a real conversation card', () {
    testWidgets( 'tap GETs the row and shows title, priority, owner, body as plain text', ( tester ) async {
      await openCard( tester, _line( _a, 'Ship it' ), {
        'GET /api/tasks/$_a': ( _ ) => jsonBody( _row( _a, 'not_approved', body: 'Line <b>one</b>\n**not bold**' ) ),
      } );
      final readsBefore = gets().length;

      await _tapHref( tester, '/app/tasks/view?row=$_a' );
      await tester.pumpAndSettle();

      expect( gets().length, readsBefore + 1 );
      expect( gets().last.path, '/api/tasks/$_a' );
      expect( find.byKey( const Key( TestKeys.taskViewDialog ) ), findsOneWidget );
      expect( find.textContaining( 'Title of $_a' ), findsOneWidget );
      expect( find.textContaining( 'Priority: P2' ), findsOneWidget );
      expect( find.textContaining( 'Owner: rio' ), findsOneWidget );
      expect( find.textContaining( 'Line <b>one</b>' ), findsOneWidget, reason: 'HTML is shown literally' );
      expect( find.textContaining( '**not bold**' ), findsOneWidget, reason: 'markdown is not rendered' );
      expect( posts(), isEmpty, reason: 'viewing never approves' );
    } );

    testWidgets( 'a view of a dropped row shows its status and does not approve it', ( tester ) async {
      await openCard( tester, _line( _a, 'Ship it' ), { 'GET /api/tasks/$_a': ( _ ) => jsonBody( _row( _a, 'dropped' ) ) } );
      await _tapHref( tester, '/app/tasks/view?row=$_a' );
      await tester.pumpAndSettle();
      expect( find.textContaining( 'Status: dropped' ), findsOneWidget );
      expect( posts(), isEmpty );
    } );

    testWidgets( 'a 404 on the view read says so in the dialog', ( tester ) async {
      await openCard( tester, _line( _a, 'Ship it' ), { 'GET /api/tasks/$_a': ( _ ) => _detail( 404, 'task $_a not found' ) } );
      await _tapHref( tester, '/app/tasks/view?row=$_a' );
      await tester.pumpAndSettle();
      expect( find.textContaining( 'Could not read this ticket.' ), findsOneWidget );
    } );
  } );

  group( 'redraw of the card', () {
    testWidgets( 'a row approved elsewhere (queued) shows approved ✅ with no tap and no POST', ( tester ) async {
      await openCard( tester, _line( _a, 'Ship it' ), { 'GET /api/tasks/$_a': ( _ ) => jsonBody( _row( _a, 'queued' ) ) } );
      expect( _approvedText(), findsOneWidget );
      expect( _approveLabel(), findsNothing );
      expect( posts(), isEmpty );
    } );

    for ( final live in [ 'in_progress', 'review', 'done' ] ) {
      testWidgets( 'a $live row shows approved ✅', ( tester ) async {
        await openCard( tester, _line( _a, 'Ship it' ), { 'GET /api/tasks/$_a': ( _ ) => jsonBody( _row( _a, live ) ) } );
        expect( _approvedText(), findsOneWidget );
      } );
    }

    for ( final closed in [ 'dropped', 'wont_fix' ] ) {
      testWidgets( 'a $closed row shows "$closed" in plain text, never approved', ( tester ) async {
        await openCard( tester, _line( _a, 'Ship it' ), { 'GET /api/tasks/$_a': ( _ ) => jsonBody( _row( _a, closed ) ) } );
        expect( _approvedText(), findsNothing );
        expect( find.textContaining( closed.replaceAll( '_', '_' ), findRichText: true ), findsWidgets );
        expect( _approveLabel(), findsNothing );
        expect( posts(), isEmpty );
      } );
    }

    testWidgets( 'a row named by two links is read once', ( tester ) async {
      await openCard( tester, '${_line( _a, 'One' )}\n${_line( _a, 'One again' )}', held( _a ) );
      expect( gets().where( ( o ) => o.path == '/api/tasks/$_a' ), hasLength( 1 ) );
    } );

    testWidgets( 'two different rows are each read once', ( tester ) async {
      await openCard( tester, '${_line( _a, 'One' )}\n${_line( _b, 'Two' )}', { ...held( _a ), ...held( _b ) } );
      expect( gets().where( ( o ) => o.path == '/api/tasks/$_a' ), hasLength( 1 ) );
      expect( gets().where( ( o ) => o.path == '/api/tasks/$_b' ), hasLength( 1 ) );
    } );

    for ( final failure in <String, ResponseBody Function( RequestOptions )>{
      '500' : ( _ ) => _detail( 500, 'boom' ),
      '404' : ( _ ) => _detail( 404, 'task $_a not found' ),
    }.entries ) {
      testWidgets( 'a failed read (${failure.key}) leaves the live link, which still approves', ( tester ) async {
        await openCard( tester, _line( _a, 'Ship it' ), {
          'GET /api/tasks/$_a'             : failure.value,
          'POST /api/tasks/$_a/transition' : ( _ ) => _transitionOk( _a ),
        } );
        expect( _approveLabel(), findsOneWidget );
        expect( _approvedText(), findsNothing );

        await _tapHref( tester, '/app/tasks/approve?row=$_a' );
        await tester.pumpAndSettle();
        expect( _approvedText(), findsOneWidget );
      } );
    }
  } );

  group( 'ids and other links', () {
    testWidgets( 'a short or non-uuid row id is not a task link and sends nothing', ( tester ) async {
      await openCard( tester, '- Bad [approve ☐](/app/tasks/approve?row=a25f51b3)', {} );
      await _tapHref( tester, '/app/tasks/approve?row=a25f51b3' );
      await tester.pumpAndSettle();
      expect( posts(), isEmpty );
      expect( gets(), isEmpty );
    } );

    test( 'the request path URL-encodes the id', () {
      expect( TaskWriteRepository.encodeId( 'a/b?c#d' ), 'a%2Fb%3Fc%23d' );
    } );
  } );
}
