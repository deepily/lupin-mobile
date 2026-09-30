import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/notifications/data/notification_models.dart';
import 'package:lupin_mobile/features/notifications/domain/notification_bloc.dart';
import 'package:lupin_mobile/features/notifications/domain/notification_event.dart';
import 'package:lupin_mobile/features/notifications/domain/notification_state.dart';
import 'package:lupin_mobile/features/notifications/presentation/conversation_by_date_screen.dart';

import '../../_harness/test_app.dart';

void main() {
  setUpAll( registerHarnessFallbacks );

  group( "ConversationByDateScreen", () {
    late MockNotificationBloc bloc;

    NotificationItem ni( {
      required String id,
      String message = "hello",
      String? title,
      String priority = "medium",
      bool played = false,
      bool responseRequested = false,
      String? responseType,
    } ) => NotificationItem(
      id                     : id,
      message                : message,
      title                  : title,
      type                   : "task",
      priority               : priority,
      timestamp              : DateTime( 2026, 4, 22, 10 ),
      played                 : played,
      playCount              : played ? 1 : 0,
      responseRequested      : responseRequested,
      responseType           : responseType,
      suppressDing           : false,
      displayQualifierWidget : false,
    );

    setUp(() {
      bloc = MockNotificationBloc();
    });

    Widget underTest() {
      return testApp(
        authBloc: MockAuthBloc(),
        extraProviders: [
          BlocProvider<NotificationBloc>.value( value: bloc ),
        ],
        child: const ConversationByDateScreen(
          senderId  : "s-1",
          userEmail : "u@x.y",
        ),
      );
    }

    testWidgets( "dispatches LoadConversationByDate on mount and renders sections", ( tester ) async {
      whenListen(
        bloc,
        Stream<NotificationState>.fromIterable( [
          NotificationsConversationByDateLoaded(
            senderId  : "s-1",
            userEmail : "u@x.y",
            byDate    : {
              "2026-04-22": [ ni( id: "n-1" ), ni( id: "n-2" ) ],
              "2026-04-21": [ ni( id: "n-3" ), ni( id: "n-4" ) ],
            },
          ),
        ] ),
        initialState: const NotificationsInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pump();

      verify( () => bloc.add( any(
        that: isA<NotificationsLoadConversationByDate>()
          .having( ( e ) => e.senderId,  "senderId",  "s-1" )
          .having( ( e ) => e.userEmail, "userEmail", "u@x.y" ),
      ) ) ).called( 1 );

      expect( find.byKey( Key( '${TestKeys.convByDateSectionHeaderPrefix}2026-04-22' ) ), findsOneWidget );
      expect( find.byKey( Key( '${TestKeys.convByDateSectionHeaderPrefix}2026-04-21' ) ), findsOneWidget );
      expect( find.byKey( Key( '${TestKeys.convByDateItemPrefix}n-1' ) ), findsOneWidget );
      expect( find.byKey( Key( '${TestKeys.convByDateItemPrefix}n-2' ) ), findsOneWidget );
      expect( find.byKey( Key( '${TestKeys.convByDateItemPrefix}n-3' ) ), findsOneWidget );
      expect( find.byKey( Key( '${TestKeys.convByDateItemPrefix}n-4' ) ), findsOneWidget );
    });

    testWidgets( "renders empty-state when byDate is empty", ( tester ) async {
      whenListen(
        bloc,
        Stream<NotificationState>.fromIterable( [
          const NotificationsConversationByDateLoaded(
            senderId  : "s-1",
            userEmail : "u@x.y",
            byDate    : {},
          ),
        ] ),
        initialState: const NotificationsInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pump();

      expect( find.text( "No messages" ), findsOneWidget );
    });

    testWidgets( "renders error state", ( tester ) async {
      whenListen(
        bloc,
        Stream<NotificationState>.fromIterable( [
          const NotificationsError( "conv-by-date down" ),
        ] ),
        initialState: const NotificationsInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pump();

      expect( find.text( "conv-by-date down" ), findsOneWidget );
    });

    testWidgets( "renders priority chip and played indicator correctly", ( tester ) async {
      whenListen(
        bloc,
        Stream<NotificationState>.fromIterable( [
          NotificationsConversationByDateLoaded(
            senderId  : "s-1",
            userEmail : "u@x.y",
            byDate    : {
              "2026-04-22": [
                ni( id: "n-1", priority: "high",   played: true,  title: "Read item" ),
                ni( id: "n-2", priority: "urgent", played: false, title: "Unread item" ),
              ],
            },
          ),
        ] ),
        initialState: const NotificationsInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pump();

      // Priority chip text appears once per item.
      expect( find.text( "high" ),   findsOneWidget );
      expect( find.text( "urgent" ), findsOneWidget );
      // played: true → done_all icon appears for the n-1 row only.
      expect( find.byIcon( Icons.done_all ), findsOneWidget );
    });

    testWidgets( "Respond button appears only for responseRequested + responseType items", ( tester ) async {
      whenListen(
        bloc,
        Stream<NotificationState>.fromIterable( [
          NotificationsConversationByDateLoaded(
            senderId  : "s-1",
            userEmail : "u@x.y",
            byDate    : {
              "2026-04-22": [
                ni( id: "n-1" ),  // no response requested
                ni( id: "n-2", responseRequested: true, responseType: "yes_no" ),
              ],
            },
          ),
        ] ),
        initialState: const NotificationsInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pump();

      expect( find.byKey( Key( '${TestKeys.convByDateRespondPrefix}n-2' ) ), findsOneWidget );
      expect( find.byKey( Key( '${TestKeys.convByDateRespondPrefix}n-1' ) ), findsNothing );
    });

    testWidgets( "tapping Respond opens InteractivePromptSheet", ( tester ) async {
      whenListen(
        bloc,
        Stream<NotificationState>.fromIterable( [
          NotificationsConversationByDateLoaded(
            senderId  : "s-1",
            userEmail : "u@x.y",
            byDate    : {
              "2026-04-22": [
                ni( id: "n-2", message: "Approve?", responseRequested: true, responseType: "yes_no" ),
              ],
            },
          ),
        ] ),
        initialState: const NotificationsInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pump();

      await tester.tap( find.byKey( Key( '${TestKeys.convByDateRespondPrefix}n-2' ) ) );
      await tester.pumpAndSettle();

      // Prompt sheet renders Yes + No buttons (FilledButton + OutlinedButton).
      expect( find.widgetWithText( FilledButton, "Yes" ), findsOneWidget );
    });
  });
}
