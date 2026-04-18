import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/notifications/domain/notification_bloc.dart';
import 'package:lupin_mobile/features/notifications/domain/notification_event.dart';
import 'package:lupin_mobile/features/notifications/presentation/interactive_prompt_sheet.dart';

import '../../_harness/test_app.dart';

/// Isolated widget coverage for the yes_no variant of InteractivePromptSheet.
/// ConversationScreen tests already exercise the integration; this file pins
/// the sheet's own behavior so regressions fail locally without mounting the
/// whole conversation stack.
void main() {
  setUpAll( registerHarnessFallbacks );

  group( "InteractivePromptSheet (yes_no)", () {
    late MockNotificationBloc bloc;

    setUp(() {
      bloc = MockNotificationBloc();
    });

    Widget underTest() {
      return MaterialApp(
        home: BlocProvider<NotificationBloc>.value(
          value: bloc,
          child: const Scaffold(
            body: InteractivePromptSheet(
              notificationId : "msg-1",
              responseType   : "yes_no",
            ),
          ),
        ),
      );
    }

    testWidgets( "renders yes + no + comment field by TestKeys", ( tester ) async {
      await tester.pumpWidget( underTest() );
      expect( find.byKey( const Key( TestKeys.promptYesButton    ) ), findsOneWidget );
      expect( find.byKey( const Key( TestKeys.promptNoButton     ) ), findsOneWidget );
      expect( find.byKey( const Key( TestKeys.promptCommentField ) ), findsOneWidget );
    });

    testWidgets( "tapping Yes dispatches NotificationsRespond with 'yes'", ( tester ) async {
      await tester.pumpWidget( underTest() );
      await tester.tap( find.byKey( const Key( TestKeys.promptYesButton ) ) );
      await tester.pump();

      final captured = verify( () => bloc.add( captureAny(
        that: isA<NotificationsRespond>(),
      ) ) ).captured;
      expect( captured.length, 1 );
      final event = captured.first as NotificationsRespond;
      expect( event.notificationId, "msg-1" );
      expect( event.responseValue,  "yes" );
    });

    testWidgets( "tapping No dispatches NotificationsRespond with 'no'", ( tester ) async {
      await tester.pumpWidget( underTest() );
      await tester.tap( find.byKey( const Key( TestKeys.promptNoButton ) ) );
      await tester.pump();

      final captured = verify( () => bloc.add( captureAny(
        that: isA<NotificationsRespond>(),
      ) ) ).captured;
      expect( captured.length, 1 );
      final event = captured.first as NotificationsRespond;
      expect( event.responseValue, "no" );
    });

    testWidgets( "comment appends to the submitted value", ( tester ) async {
      await tester.pumpWidget( underTest() );
      await tester.enterText(
        find.byKey( const Key( TestKeys.promptCommentField ) ),
        "only the March ones",
      );
      await tester.tap( find.byKey( const Key( TestKeys.promptYesButton ) ) );
      await tester.pump();

      final captured = verify( () => bloc.add( captureAny(
        that: isA<NotificationsRespond>(),
      ) ) ).captured;
      final event = captured.first as NotificationsRespond;
      expect( event.responseValue, "yes [comment: only the March ones]" );
    });
  });
}
