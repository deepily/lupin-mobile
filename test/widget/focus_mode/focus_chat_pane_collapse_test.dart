import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_bloc.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_event.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_state.dart';
import 'package:lupin_mobile/features/focus_mode/presentation/focus_chat_pane.dart';
import 'package:lupin_mobile/features/notifications/data/notification_models.dart';
import 'package:lupin_mobile/services/notification_filter/notification_stop_list.dart';

class _MockFocusBloc extends MockBloc<FocusChatEvent, FocusChatState> implements FocusChatBloc {}

NotificationItem _item( String id, String text, { String? group, bool ask = false } ) => NotificationItem(
  id: id, message: text, type: 'progress', priority: 'low', senderId: 'S',
  timestamp: DateTime( 2026, 8, 21, 12 ), played: false, playCount: 0,
  responseRequested: ask, responseType: ask ? 'yes_no' : null,
  suppressDing: false, displayQualifierWidget: false, progressGroupId: group,
);

void main() {
  group( 'FocusChatPane — progress-group collapse (plan §4)', () {
    late _MockFocusBloc bloc;
    late NotificationStopList sl;

    final window = [
      FocusMessage( item: _item( '1', 'Done: Bash a', group: 'pg-1' ) ),
      FocusMessage( item: _item( '2', 'Done: Bash b', group: 'pg-1' ) ),
      FocusMessage( item: _item( '3', 'Done: Bash c', group: 'pg-1' ) ),
      FocusMessage( item: _item( '4', 'A real message' ) ),
      FocusMessage( item: _item( '5', 'Proceed?', group: 'pg-1', ask: true ) ),
    ];

    setUp( () async {
      SharedPreferences.setMockInitialValues( {} );
      sl   = NotificationStopList( await SharedPreferences.getInstance() );
      bloc = _MockFocusBloc();
      final st = const FocusChatState.initial().copyWith(
        senderOrder: const [ 'S' ], focusedSender: 'S', hydration: FocusHydration.ready,
        windows: { 'S': window } );
      whenListen( bloc, Stream<FocusChatState>.fromIterable( [ st ] ), initialState: st );
    } );

    Widget host() => MaterialApp( home: Scaffold( body: BlocProvider<FocusChatBloc>.value(
      value: bloc, child: FocusChatPane( userEmail: 'rick@test.com', stopList: sl ) ) ) );

    testWidgets( 'three same-group bubbles render as ONE row with ×3 showing the latest; tap expands to all; the ask is never buried', ( tester ) async {
      await tester.pumpWidget( host() );
      await tester.pump();
      expect( find.text( 'Done: Bash c' ), findsOneWidget );
      expect( find.text( 'Done: Bash a' ), findsNothing );
      expect( find.text( '×3' ), findsOneWidget );
      expect( find.text( 'A real message' ), findsOneWidget );
      expect( find.text( 'Proceed?' ), findsOneWidget, reason: 'responseRequested ⇒ own row even with a group id' );

      await tester.tap( find.text( '×3' ) );
      await tester.pump();
      expect( find.text( 'Done: Bash a' ), findsOneWidget );
      expect( find.text( 'Done: Bash b' ), findsOneWidget );
      expect( find.text( 'Done: Bash c' ), findsOneWidget );

      await tester.tap( find.text( '×3' ) );
      await tester.pump();
      expect( find.text( 'Done: Bash a' ), findsNothing );
    } );

    testWidgets( 'collapse OFF ⇒ every bubble renders; flipping the pref live re-renders', ( tester ) async {
      await sl.setCollapseGroups( false );
      await tester.pumpWidget( host() );
      await tester.pump();
      expect( find.text( 'Done: Bash a' ), findsOneWidget );
      expect( find.text( '×3' ), findsNothing );

      await sl.setCollapseGroups( true );
      await tester.pump();
      expect( find.text( '×3' ), findsOneWidget );
      expect( find.text( 'Done: Bash a' ), findsNothing );
    } );
  } );
}
