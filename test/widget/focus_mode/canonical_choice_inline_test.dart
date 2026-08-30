/// AC-S4.10b delta 1 — a canonical `ask_multiple_choice` payload renders
/// INLINE chips in the focus pane instead of routing to the "Answer in full
/// view…" fallback.
///
/// Delta 2 of the closed list (`state == 'expired'` counts as answered) is
/// pinned in `ask_lifecycle_test.dart`; delta 3 (the same repair one layer
/// down, in the sheet) in `prompt_payload_test.dart`.
library;

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_bloc.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_event.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_state.dart';
import 'package:lupin_mobile/features/focus_mode/presentation/focus_chat_pane.dart';
import 'package:lupin_mobile/features/notifications/data/notification_models.dart';
import 'package:lupin_mobile/services/notification_filter/notification_stop_list.dart';

class _MockFocusBloc extends MockBloc<FocusChatEvent, FocusChatState>
    implements FocusChatBloc {}

/// The canonical shape: questions NESTED under `response_options.questions[]`.
const _canonical = {
  'questions': [
    {
      'question'     : 'Which database?',
      'header'       : 'Database',
      'multi_select' : false,
      'options'      : [ { 'label': 'Postgres' }, { 'label': 'SQLite' } ],
    },
  ],
};

/// The LEGACY shape mobile used to read: options at the TOP level.
const _legacy = {
  'options'      : [ { 'label': 'Postgres' }, { 'label': 'SQLite' } ],
  'multi_select' : false,
};

NotificationItem _ask( String id, Map<String, dynamic>? options ) => NotificationItem(
  id                     : id,
  message                : 'Pick one',
  type                   : 'task',
  priority               : 'medium',
  senderId               : 'S',
  timestamp              : DateTime( 2026, 8, 29, 20 ),
  played                 : false,
  playCount              : 0,
  responseRequested      : true,
  responseType           : 'multiple_choice',
  responseOptions        : options,
  suppressDing           : false,
  displayQualifierWidget : false,
);

void main() {
  late _MockFocusBloc bloc;
  late NotificationStopList sl;

  Future<void> arrange( NotificationItem item ) async {
    SharedPreferences.setMockInitialValues( {} );
    sl   = NotificationStopList( await SharedPreferences.getInstance() );
    bloc = _MockFocusBloc();
    final st = const FocusChatState.initial().copyWith(
      senderOrder   : const [ 'S' ],
      focusedSender : 'S',
      hydration     : FocusHydration.ready,
      windows       : { 'S': [ FocusMessage( item: item ) ] },
    );
    whenListen( bloc, Stream<FocusChatState>.fromIterable( [ st ] ), initialState: st );
  }

  Widget host() => MaterialApp( home: Scaffold( body: BlocProvider<FocusChatBloc>.value(
    value : bloc,
    child : FocusChatPane( userEmail: 'rick@test.com', stopList: sl ),
  ) ) );

  testWidgets( 'AC-S4.10b delta 1 — a CANONICAL payload renders inline '
               'options, NOT the full-view fallback', ( tester ) async {
    await arrange( _ask( 'a1', _canonical ) );
    await tester.pumpWidget( host() );
    await tester.pump();

    expect( find.text( 'Postgres' ), findsOneWidget );
    expect( find.text( 'SQLite'   ), findsOneWidget );
    expect( find.byKey( const Key( '${TestKeys.focusBatchFallbackPrefix}a1' ) ),
            findsNothing,
            reason: 'today optionsRenderable is false for a nested payload, '
                    'so every canonical ask took the fallback' );
  } );

  testWidgets( 'the LEGACY top-level shape still renders inline, unchanged',
               ( tester ) async {
    await arrange( _ask( 'a2', _legacy ) );
    await tester.pumpWidget( host() );
    await tester.pump();

    expect( find.text( 'Postgres' ), findsOneWidget );
    expect( find.byKey( const Key( '${TestKeys.focusBatchFallbackPrefix}a2' ) ),
            findsNothing );
  } );

  testWidgets( 'an ask with NO options at all still takes the fallback — the '
               'backfilled case is untouched', ( tester ) async {
    await arrange( _ask( 'a3', null ) );
    await tester.pumpWidget( host() );
    await tester.pump();

    expect( find.byKey( const Key( '${TestKeys.focusBatchFallbackPrefix}a3' ) ),
            findsOneWidget,
            reason: 'the 19-field conversation wire carries no '
                    'response_options; chips cannot render from nothing' );
  } );
}
