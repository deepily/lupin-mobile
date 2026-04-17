import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/notifications/domain/notification_bloc.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/notifications/data/notification_models.dart';
import 'package:lupin_mobile/features/notifications/domain/notification_event.dart';
import 'package:lupin_mobile/features/notifications/domain/notification_state.dart';
import 'package:lupin_mobile/features/notifications/presentation/inbox_screen.dart';

import '../../_harness/test_app.dart';

/// Widget-level coverage for Smoke B1 (Inbox) — replaces on-device clicking
/// for the "Inbox renders senders" and "WS external update triggers refresh"
/// scenarios. On-device work is reduced to a final sanity pass, not primary
/// verification.
void main() {
  setUpAll( registerHarnessFallbacks );

  group( "InboxScreen", () {
    late MockNotificationBloc bloc;

    SenderSummary s( String id, { int count = 1, int? newCount } ) =>
      SenderSummary(
        senderId     : id,
        lastActivity : DateTime( 2026, 4, 17, 10 ),
        count        : count,
        newCount     : newCount,
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
        child: const InboxScreen( userEmail: "u@x.y" ),
      );
    }

    testWidgets( "dispatches LoadInbox on mount and renders senders", ( tester ) async {
      whenListen(
        bloc,
        Stream.fromIterable( <NotificationState>[
          const NotificationsLoading(),
          NotificationsInboxLoaded(
            senders: [ s( "s-1", count: 3, newCount: 2 ), s( "s-2", count: 5 ) ],
            userEmail: "u@x.y",
          ),
        ] ),
        initialState: const NotificationsInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pump(); // drain first emission
      await tester.pump(); // drain second

      verify( () => bloc.add( any(
        that: isA<NotificationsLoadInbox>().having(
          ( e ) => e.userEmail, "userEmail", "u@x.y",
        ),
      ) ) ).called( 1 );

      expect( find.byKey( Key( '${TestKeys.inboxSenderTilePrefix}s-1' ) ), findsOneWidget );
      expect( find.byKey( Key( '${TestKeys.inboxSenderTilePrefix}s-2' ) ), findsOneWidget );
      expect( find.text( "s-1" ), findsOneWidget );
      expect( find.text( "s-2" ), findsOneWidget );
      expect( find.text( "2" ), findsOneWidget ); // newCount badge
    });

    testWidgets( "external update emits a second InboxLoaded and list updates", ( tester ) async {
      // Simulates what happens when Track C dispatches NotificationsExternalUpdate
      // after a `notification_queue_update` WS event: the bloc's _refreshCurrent
      // re-emits InboxLoaded with fresh data.
      whenListen(
        bloc,
        Stream.fromIterable( <NotificationState>[
          NotificationsInboxLoaded(
            senders: [ s( "s-1", count: 1, newCount: 1 ) ],
            userEmail: "u@x.y",
          ),
          NotificationsInboxLoaded(
            senders: [ s( "s-1", count: 2, newCount: 2 ) ],
            userEmail: "u@x.y",
          ),
        ] ),
        initialState: const NotificationsInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pump();
      await tester.pump();

      // Post-refresh: second badge value present.
      expect( find.text( "2" ), findsOneWidget );
    });

    testWidgets( "renders empty state when no senders", ( tester ) async {
      whenListen(
        bloc,
        Stream<NotificationState>.fromIterable( [
          const NotificationsInboxLoaded( senders: [], userEmail: "u@x.y" ),
        ] ),
        initialState: const NotificationsInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pump();

      expect( find.text( "No notifications" ), findsOneWidget );
    });

    testWidgets( "renders error view with retry", ( tester ) async {
      whenListen(
        bloc,
        Stream<NotificationState>.fromIterable( [
          const NotificationsError( "boom" ),
        ] ),
        initialState: const NotificationsInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pump();

      expect( find.text( "boom" ),  findsOneWidget );
      expect( find.text( "Retry" ), findsOneWidget );
    });
  });
}
