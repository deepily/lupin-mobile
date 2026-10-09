import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/notifications/data/notification_models.dart';
import 'package:lupin_mobile/features/notifications/domain/notification_bloc.dart';
import 'package:lupin_mobile/features/notifications/domain/notification_state.dart';
import 'package:lupin_mobile/features/notifications/presentation/conversation_by_date_screen.dart';
import 'package:lupin_mobile/features/notifications/presentation/conversation_screen.dart';
import 'package:lupin_mobile/features/notifications/presentation/inbox_screen.dart';

import '../../_harness/test_app.dart';

/// Pins the colours the notification screens paint for their translucent chips and
/// swipe background, as ARGB bytes. Measured before and after the move from
/// `Color.withOpacity` to `.withValues( alpha: )`: every channel was identical.
void main() {
  setUpAll( registerHarnessFallbacks );

  late MockNotificationBloc bloc;

  setUp(() {
    bloc = MockNotificationBloc();
  });

  Widget wrap( Widget child ) => testApp(
    authBloc       : MockAuthBloc(),
    extraProviders : [ BlocProvider<NotificationBloc>.value( value: bloc ) ],
    child          : child,
  );

  int argb( Color c ) => c.toARGB32();

  group( "chip and swipe colours", () {
    testWidgets( "inbox swipe background is red at alpha 204 (A204 R244 G67 B54)", ( tester ) async {
      whenListen(
        bloc,
        Stream<NotificationState>.fromIterable( [
          NotificationsInboxLoaded(
            senders   : [ SenderSummary( senderId: "s-1", lastActivity: DateTime( 2026, 4, 17, 10 ), count: 1 ) ],
            userEmail : "u@x.y",
          ),
        ] ),
        initialState: const NotificationsInitial(),
      );
      await tester.pumpWidget( wrap( const InboxScreen( userEmail: "u@x.y" ) ) );
      await tester.pump();

      await tester.drag( find.byKey( const Key( '${TestKeys.inboxSenderTilePrefix}s-1' ) ), const Offset( -120, 0 ) );
      await tester.pump();

      final swipe = tester.widgetList<Container>( find.byType( Container ) )
          .where( ( c ) => c.color != null && ( c.color!.a * 255 ).round() == 204 );
      expect( swipe.length, 1 );
      expect( argb( swipe.single.color! ), 0xCCF44336 );
    });

    for ( final c in <String, int>{
      "delivered" : 0x262196F3,   // blue,   A38 R33 G150 B243
      "responded" : 0x264CAF50,   // green,  A38 R76 G175 B80
      "expired"   : 0x269E9E9E,   // grey,   A38 R158 G158 B158
      "pending"   : 0x26FF9800,   // orange, A38 R255 G152 B0
    }.entries ) {
      testWidgets( "conversation state chip '${c.key}' paints ${c.value.toRadixString( 16 )}", ( tester ) async {
        whenListen(
          bloc,
          Stream<NotificationState>.fromIterable( [
            NotificationsConversationLoaded(
              senderId  : "s-1",
              userEmail : "u@x.y",
              messages  : [
                ConversationMessage(
                  id: "m-1", message: "hi", type: "task", priority: "low", state: c.key, responseRequested: false,
                  isHidden: false, timestamp: DateTime( 2026, 4, 17, 10 ),
                ),
              ],
            ),
          ] ),
          initialState: const NotificationsInitial(),
        );
        await tester.pumpWidget( wrap( const ConversationScreen( senderId: "s-1", userEmail: "u@x.y" ) ) );
        await tester.pump();

        final chip = tester.widget<Chip>( find.widgetWithText( Chip, c.key ) );
        expect( argb( chip.backgroundColor! ), c.value );
      });
    }

    for ( final c in <String, int>{
      "urgent" : 0x26F44336,   // red,    A38 R244 G67 B54
      "high"   : 0x26FF9800,   // orange, A38 R255 G152 B0
      "medium" : 0x262196F3,   // blue,   A38 R33 G150 B243
      "low"    : 0x269E9E9E,   // grey,   A38 R158 G158 B158
    }.entries ) {
      testWidgets( "by-date priority chip '${c.key}' paints ${c.value.toRadixString( 16 )}", ( tester ) async {
        whenListen(
          bloc,
          Stream<NotificationState>.fromIterable( [
            NotificationsConversationByDateLoaded(
              senderId  : "s-1",
              userEmail : "u@x.y",
              byDate    : {
                "2026-04-22": [
                  NotificationItem(
                    id: "n-1", message: "hello", type: "task", priority: c.key,
                    timestamp: DateTime( 2026, 4, 22, 10 ), played: false, playCount: 0,
                    responseRequested: false, suppressDing: false, displayQualifierWidget: false,
                  ),
                ],
              },
            ),
          ] ),
          initialState: const NotificationsInitial(),
        );
        await tester.pumpWidget( wrap( const ConversationByDateScreen( senderId: "s-1", userEmail: "u@x.y" ) ) );
        await tester.pump();

        final chip = tester.widget<Chip>( find.widgetWithText( Chip, c.key ) );
        expect( argb( chip.backgroundColor! ), c.value );
      });
    }
  });
}
