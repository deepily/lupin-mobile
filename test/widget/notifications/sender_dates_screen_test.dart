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
import 'package:lupin_mobile/features/notifications/presentation/sender_dates_screen.dart';

import '../../_harness/test_app.dart';

void main() {
  setUpAll( registerHarnessFallbacks );

  group( "SenderDatesScreen", () {
    late MockNotificationBloc bloc;

    DateSummary ds( String date, { int count = 3, int newCount = 0 } ) =>
        DateSummary( date: date, count: count, newCount: newCount );

    setUp(() {
      bloc = MockNotificationBloc();
    });

    Widget underTest() {
      return testApp(
        authBloc: MockAuthBloc(),
        extraProviders: [
          BlocProvider<NotificationBloc>.value( value: bloc ),
        ],
        child: const SenderDatesScreen(
          senderId  : "s-1",
          userEmail : "u@x.y",
        ),
      );
    }

    testWidgets( "dispatches LoadSenderDates on mount and renders date tiles", ( tester ) async {
      whenListen(
        bloc,
        Stream<NotificationState>.fromIterable( [
          NotificationsSenderDatesLoaded(
            senderId  : "s-1",
            userEmail : "u@x.y",
            dates     : [ ds( "2026-04-22" ), ds( "2026-04-21" ), ds( "2026-04-20" ) ],
          ),
        ] ),
        initialState: const NotificationsInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pump();

      verify( () => bloc.add( any(
        that: isA<NotificationsLoadSenderDates>()
          .having( ( e ) => e.senderId,  "senderId",  "s-1" )
          .having( ( e ) => e.userEmail, "userEmail", "u@x.y" ),
      ) ) ).called( 1 );

      expect( find.byKey( Key( '${TestKeys.senderDatesTilePrefix}2026-04-22' ) ), findsOneWidget );
      expect( find.byKey( Key( '${TestKeys.senderDatesTilePrefix}2026-04-21' ) ), findsOneWidget );
      expect( find.byKey( Key( '${TestKeys.senderDatesTilePrefix}2026-04-20' ) ), findsOneWidget );
    });

    testWidgets( "renders empty-state when dates list is empty", ( tester ) async {
      whenListen(
        bloc,
        Stream<NotificationState>.fromIterable( [
          const NotificationsSenderDatesLoaded(
            senderId  : "s-1",
            userEmail : "u@x.y",
            dates     : [],
          ),
        ] ),
        initialState: const NotificationsInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pump();

      expect( find.text( "No dates" ), findsOneWidget );
    });

    testWidgets( "renders error state from NotificationsError", ( tester ) async {
      whenListen(
        bloc,
        Stream<NotificationState>.fromIterable( [
          const NotificationsError( "dates fetch failed" ),
        ] ),
        initialState: const NotificationsInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pump();

      expect( find.text( "dates fetch failed" ), findsOneWidget );
    });

    testWidgets( "newCount badge appears only when newCount > 0", ( tester ) async {
      whenListen(
        bloc,
        Stream<NotificationState>.fromIterable( [
          NotificationsSenderDatesLoaded(
            senderId  : "s-1",
            userEmail : "u@x.y",
            dates     : [
              ds( "2026-04-22", count: 5, newCount: 3 ),
              ds( "2026-04-21", count: 4, newCount: 0 ),
            ],
          ),
        ] ),
        initialState: const NotificationsInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pump();

      // Badge "3" should appear exactly once (for the 2026-04-22 row only).
      expect( find.text( "3" ), findsOneWidget );
    });

    testWidgets( "tapping a date tile pushes ConversationByDateScreen", ( tester ) async {
      whenListen(
        bloc,
        Stream<NotificationState>.fromIterable( [
          NotificationsSenderDatesLoaded(
            senderId  : "s-1",
            userEmail : "u@x.y",
            dates     : [ ds( "2026-04-22" ) ],
          ),
        ] ),
        initialState: const NotificationsInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pump();

      await tester.tap( find.byKey( Key( '${TestKeys.senderDatesTilePrefix}2026-04-22' ) ) );
      await tester.pumpAndSettle();

      expect( find.byType( ConversationByDateScreen ), findsOneWidget );
    });
  });
}
