/// Rick 2026-09-26: an inline multiple-choice ask in Focus mode showed its
/// options but not the Submit button, so he could not tell whether he had
/// sent anything. The payload below is the one that failed on his phone.
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

const _staffing = {
  'questions': [
    {
      'question'     : 'I see five tickets, not four. Should I do them solo?',
      'header'       : 'Staffing',
      'multi_select' : false,
      'options'      : [
        { 'label': 'Solo, all five (Recommended)',
          'description': 'Pro: three of them change the same Focus mode screen, so '
                         'there are no merge collisions. Con: one ticket at a time.' },
        { 'label': 'Spin up an SWE team',
          'description': 'Pro: the tickets happen in parallel. Con: the Focus mode '
                         'edits collide, and there is spawn overhead.' },
        { 'label': 'Solo, skip file-viewer',
          'description': 'Only the four tickets you meant; the file-viewer row stays queued.' },
      ],
    },
  ],
};

NotificationItem _ask( String id ) => NotificationItem(
  id                     : id,
  message                : 'I see five tickets, not four. Should I do them solo?',
  type                   : 'task',
  priority               : 'high',
  senderId               : 'S',
  timestamp              : DateTime( 2026, 9, 26, 21 ),
  played                 : false,
  playCount              : 0,
  responseRequested      : true,
  responseType           : 'multiple_choice',
  responseOptions        : _staffing,
  suppressDing           : false,
  displayQualifierWidget : false,
);

void main() {
  late _MockFocusBloc bloc;
  late NotificationStopList sl;

  Future<void> arrange() async {
    SharedPreferences.setMockInitialValues( {} );
    sl   = NotificationStopList( await SharedPreferences.getInstance() );
    bloc = _MockFocusBloc();
    final item = _ask( 'q1' );
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

  // Folded (360 dp, less the session rail) and unfolded widths.
  for ( final width in [ 300.0, 360.0, 700.0 ] ) {
    testWidgets( 'the Submit button sits inside its bubble at $width dp', ( tester ) async {
      tester.view.physicalSize     = Size( width, 2000 );
      tester.view.devicePixelRatio = 1.0;
      addTearDown( tester.view.reset );

      await arrange();
      await tester.pumpWidget( host() );
      await tester.pump();

      final submit = find.byKey( const Key( TestKeys.promptMultiQuestionSubmit ) );
      final bubble = find.byKey( const Key( '${TestKeys.focusBubblePrefix}q1' ) );
      expect( submit, findsOneWidget );
      expect( find.textContaining( 'there are no merge collisions' ), findsOneWidget,
          reason: 'each option shows its description, where the pros and cons live' );

      final s = tester.getRect( submit );
      final b = tester.getRect( bubble );
      expect( s.bottom <= b.bottom, isTrue,
          reason: 'Submit ends at ${s.bottom}, but the bubble clips at ${b.bottom}' );

      // Hit-testable, not just painted: a tap reaches the button.
      await tester.tap( find.text( 'Solo, all five (Recommended)' ) );
      await tester.pump();
      await tester.tap( submit, warnIfMissed: true );
      await tester.pump();
    } );
  }
}
