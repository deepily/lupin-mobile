/// Row b00e076c: what the card SHOWS when an answer never left the phone.
/// The bloc keeps the answer (focus_unsent_answer_test.dart); this pins that
/// the user can see it, resend it, and learn when it can no longer be sent.
library;

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_bloc.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_event.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_state.dart';
import 'package:lupin_mobile/features/focus_mode/presentation/focus_chat_pane.dart';
import 'package:lupin_mobile/features/notifications/data/ask_resolution.dart';
import 'package:lupin_mobile/features/notifications/data/notification_models.dart';
import 'package:lupin_mobile/services/notification_filter/notification_stop_list.dart';

class _MockFocusBloc extends MockBloc<FocusChatEvent, FocusChatState> implements FocusChatBloc {}

const String _sender = 'claude.code@lupin-mobile.deepily.ai#fe56dccd';

NotificationItem _ask() => NotificationItem(
  id: 'a1', message: 'Proceed?', type: 'task', priority: 'high', senderId: _sender,
  timestamp: DateTime( 2026, 9, 18, 22, 34 ), played: true, playCount: 0,
  responseRequested: true, responseType: 'yes_no', suppressDing: true, displayQualifierWidget: false,
);

void main() {
  late _MockFocusBloc       bloc;
  late NotificationStopList sl;

  setUpAll( () => registerFallbackValue( const FocusSenderSelected( 'f' ) ) );

  setUp( () async {
    SharedPreferences.setMockInitialValues( {} );
    sl   = NotificationStopList( await SharedPreferences.getInstance() );
    bloc = _MockFocusBloc();
  } );

  Future<void> pumpWith( WidgetTester tester, FocusMessage msg ) async {
    final st = const FocusChatState.initial().copyWith(
      senderOrder: const [ _sender ], focusedSender: _sender, hydration: FocusHydration.ready,
      windows: { _sender: [ msg ] } );
    whenListen( bloc, Stream<FocusChatState>.fromIterable( [ st ] ), initialState: st );
    await tester.pumpWidget( MaterialApp( home: Scaffold( body: BlocProvider<FocusChatBloc>.value(
      value: bloc, child: FocusChatPane( userEmail: 'rick@test.com', stopList: sl ) ) ) ) );
    await tester.pump();
  }

  testWidgets( 'an unsent answer is shown on the card, and one tap resends exactly it', ( tester ) async {
    await pumpWith( tester, FocusMessage( item: _ask(), unsentAnswer: 'yes' ) );

    final resend = find.byKey( const Key( TestKeys.focusUnsentResend ) );
    expect( resend, findsOneWidget );
    expect( find.textContaining( 'Not sent: "yes"' ), findsOneWidget );

    await tester.tap( resend );
    await tester.pump();

    final sent = verify( () => bloc.add( captureAny() ) ).captured.whereType<FocusRespondRequested>().single;
    expect( sent.text,                          'yes' );
    expect( sent.senderId,                      _sender );
    expect( sent.promptContext!.notificationId, 'a1' );
  } );

  testWidgets( 'the ask stays answerable: a different choice is still offered under the notice', ( tester ) async {
    await pumpWith( tester, FocusMessage( item: _ask(), unsentAnswer: 'yes' ) );

    expect( find.byKey( const Key( TestKeys.focusUnsentResend ) ), findsOneWidget );
    expect( find.text( 'No' ), findsWidgets, reason: 'the yes/no controls are still there' );
  } );

  testWidgets( 'an ask that expired first says the answer was NOT sent — never a plain "answered"', ( tester ) async {
    await pumpWith( tester, FocusMessage(
      item: _ask(), unsentAnswer: 'yes', answered: true, resolution: AskResolution.expired ) );

    expect( find.byKey( const Key( TestKeys.focusUnsentClosed ) ), findsOneWidget );
    expect( find.text( 'Expired — your answer "yes" was not sent' ), findsOneWidget );
    expect( find.byKey( const Key( TestKeys.focusUnsentResend ) ), findsNothing );
    expect( find.text( 'answered' ), findsNothing, reason: 'it was not answered by him' );
  } );

  testWidgets( 'a normal answered card is unchanged', ( tester ) async {
    await pumpWith( tester, FocusMessage( item: _ask(), answered: true ) );

    expect( find.text( 'answered' ), findsOneWidget );
    expect( find.byKey( const Key( TestKeys.focusUnsentClosed ) ), findsNothing );
  } );
}
