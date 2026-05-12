import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/notifications/data/notification_models.dart';
import 'package:lupin_mobile/features/notifications/data/voice_persona.dart';
import 'package:lupin_mobile/features/notifications/domain/notification_bloc.dart';
import 'package:lupin_mobile/features/notifications/domain/notification_event.dart';
import 'package:lupin_mobile/features/notifications/domain/notification_state.dart';
import 'package:lupin_mobile/features/notifications/presentation/conversation_screen.dart';
import 'package:lupin_mobile/features/notifications/presentation/sender_dates_screen.dart';

import '../../_harness/test_app.dart';

/// Widget-level coverage for Smoke B1 response flow — tapping Respond on
/// an ask_yes_no message opens the InteractivePromptSheet; choosing Yes
/// dispatches NotificationsRespond with the right notificationId + value.
/// Replaces the on-device tap sequence.
void main() {
  setUpAll( registerHarnessFallbacks );

  group( "ConversationScreen", () {
    late MockNotificationBloc bloc;

    ConversationMessage yesNoMsg( String id ) => ConversationMessage(
      id                : id,
      message           : "Proceed with the deploy?",
      type              : "task",
      priority          : "high",
      state             : "delivered",
      isHidden          : false,
      responseRequested : true,
      responseType      : "yes_no",
      timestamp         : DateTime( 2026, 4, 17, 10 ),
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
        child: const ConversationScreen(
          senderId  : "s-1",
          userEmail : "u@x.y",
        ),
      );
    }

    testWidgets( "dispatches LoadConversation on mount and renders a yes_no message", ( tester ) async {
      whenListen(
        bloc,
        Stream<NotificationState>.fromIterable( [
          NotificationsConversationLoaded(
            senderId  : "s-1",
            userEmail : "u@x.y",
            messages  : [ yesNoMsg( "c-1" ) ],
          ),
        ] ),
        initialState: const NotificationsInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pump();

      verify( () => bloc.add( any(
        that: isA<NotificationsLoadConversation>()
          .having( ( e ) => e.senderId,  "senderId",  "s-1" )
          .having( ( e ) => e.userEmail, "userEmail", "u@x.y" ),
      ) ) ).called( 1 );

      expect( find.text( "Proceed with the deploy?" ), findsOneWidget );
      expect( find.text( "Respond" ), findsOneWidget );
    });

    testWidgets( "tapping Respond → Yes dispatches NotificationsRespond with 'yes'", ( tester ) async {
      whenListen(
        bloc,
        Stream<NotificationState>.fromIterable( [
          NotificationsConversationLoaded(
            senderId  : "s-1",
            userEmail : "u@x.y",
            messages  : [ yesNoMsg( "c-1" ) ],
          ),
        ] ),
        initialState: const NotificationsInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pump();

      // Open the InteractivePromptSheet.
      await tester.tap( find.text( "Respond" ) );
      await tester.pumpAndSettle();

      // Two "Yes" buttons could exist under mat; the sheet's Yes button is the
      // FilledButton; the other is from "Yes, no". Filter by FilledButton.
      final yesBtn = find.widgetWithText( FilledButton, "Yes" );
      expect( yesBtn, findsOneWidget );
      await tester.tap( yesBtn );
      await tester.pumpAndSettle();

      final captured = verify( () => bloc.add( captureAny(
        that: isA<NotificationsRespond>(),
      ) ) ).captured;
      expect( captured.length, 1 );
      final event = captured.first as NotificationsRespond;
      expect( event.notificationId, "c-1" );
      expect( event.responseValue,  "yes" );
    });

    testWidgets( "tapping Respond → Neither dispatches NotificationsRespond with 'neither'", ( tester ) async {
      whenListen(
        bloc,
        Stream<NotificationState>.fromIterable( [
          NotificationsConversationLoaded(
            senderId  : "s-1",
            userEmail : "u@x.y",
            messages  : [ yesNoMsg( "c-1" ) ],
          ),
        ] ),
        initialState: const NotificationsInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pump();

      // Open the InteractivePromptSheet.
      await tester.tap( find.text( "Respond" ) );
      await tester.pumpAndSettle();

      await tester.tap( find.byKey( const Key( TestKeys.promptNeitherButton ) ) );
      await tester.pumpAndSettle();

      final captured = verify( () => bloc.add( captureAny(
        that: isA<NotificationsRespond>(),
      ) ) ).captured;
      expect( captured.length, 1 );
      final event = captured.first as NotificationsRespond;
      expect( event.notificationId, "c-1" );
      expect( event.responseValue,  "neither" );
    });

    testWidgets( "renders empty state when no messages", ( tester ) async {
      whenListen(
        bloc,
        Stream<NotificationState>.fromIterable( [
          const NotificationsConversationLoaded(
            senderId  : "s-1",
            userEmail : "u@x.y",
            messages  : [],
          ),
        ] ),
        initialState: const NotificationsInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pump();

      expect( find.text( "No messages" ), findsOneWidget );
    });

    testWidgets( "AppBar Summarize renders the icon button", ( tester ) async {
      whenListen(
        bloc,
        Stream<NotificationState>.fromIterable( [
          NotificationsConversationLoaded(
            senderId  : "s-1",
            userEmail : "u@x.y",
            messages  : [ yesNoMsg( "c-1" ) ],
          ),
        ] ),
        initialState: const NotificationsInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pump();

      expect( find.byKey( const Key( TestKeys.convSummarizeButton ) ), findsOneWidget );
    });

    testWidgets( "tapping Summarize dispatches NotificationsGenerateGistRequested", ( tester ) async {
      whenListen(
        bloc,
        Stream<NotificationState>.fromIterable( [
          NotificationsConversationLoaded(
            senderId  : "s-1",
            userEmail : "u@x.y",
            messages  : [ yesNoMsg( "c-1" ) ],
          ),
        ] ),
        initialState: const NotificationsInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pump();

      await tester.tap( find.byKey( const Key( TestKeys.convSummarizeButton ) ) );
      await tester.pump();

      verify( () => bloc.add( any(
        that: isA<NotificationsGenerateGistRequested>(),
      ) ) ).called( 1 );
    });

    testWidgets( "tapping calendar AppBar action pushes SenderDatesScreen", ( tester ) async {
      whenListen(
        bloc,
        Stream<NotificationState>.fromIterable( [
          NotificationsConversationLoaded(
            senderId  : "s-1",
            userEmail : "u@x.y",
            messages  : [ yesNoMsg( "c-1" ) ],
          ),
        ] ),
        initialState: const NotificationsInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pump();

      await tester.tap( find.byKey( const Key( TestKeys.convDatesButton ) ) );
      await tester.pumpAndSettle();

      expect( find.byType( SenderDatesScreen ), findsOneWidget );
    });

    testWidgets( "3.5 — AppBar header reads bloc-cached persona keyed on senderId", ( tester ) async {
      const adam = VoicePersona(
        name        : "Adam",
        voiceId     : "pNInz6obpgDQGcFmaJgB",
        icon        : "🌑",
        color       : "#212121",
        borrowed    : false,
        displayName : "Adam (deep)",
      );

      whenListen(
        bloc,
        Stream<NotificationState>.fromIterable( [
          NotificationsConversationLoaded(
            senderId         : "s-1",
            userEmail        : "u@x.y",
            messages         : [ yesNoMsg( "c-1" ) ],
            personasBySender : const { "s-1": adam },
          ),
        ] ),
        initialState: const NotificationsInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pump();

      expect(
        find.byKey( const Key( "${TestKeys.personaBadgePrefix}s-1" ) ),
        findsOneWidget,
      );
    } );

    testWidgets( "AppBar header omits persona badge when personasBySender is empty", ( tester ) async {
      whenListen(
        bloc,
        Stream<NotificationState>.fromIterable( [
          NotificationsConversationLoaded(
            senderId  : "s-1",
            userEmail : "u@x.y",
            messages  : [ yesNoMsg( "c-1" ) ],
          ),
        ] ),
        initialState: const NotificationsInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pump();

      expect(
        find.byKey( const Key( "${TestKeys.personaBadgePrefix}s-1" ) ),
        findsNothing,
      );
    } );

    testWidgets( "NotificationsGistReady state shows the gist bottom sheet", ( tester ) async {
      whenListen(
        bloc,
        Stream<NotificationState>.fromIterable( [
          NotificationsConversationLoaded(
            senderId  : "s-1",
            userEmail : "u@x.y",
            messages  : [ yesNoMsg( "c-1" ) ],
          ),
          const NotificationsGistReady( "Summary of the thread." ),
        ] ),
        initialState: const NotificationsInitial(),
      );

      await tester.pumpWidget( underTest() );
      await tester.pumpAndSettle();

      expect( find.byKey( const Key( TestKeys.convGistSheet ) ), findsOneWidget );
      expect( find.text( "Summary of the thread." ), findsOneWidget );
    });
  });
}
