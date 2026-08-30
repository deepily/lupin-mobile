/// AC-S4.14 — a suppressed QUESTION's notice renders in the PROMPT WIDGET,
/// with its answer affordance INTACT.
///
/// 🔴 The falsifier is a placement error, not a missing feature: rendering the
/// notice in the answer card instead tells the user something was muted and
/// gives them no way to act on it — while the server stays blocked waiting for
/// the reply. So the load-bearing assertion here is that the normal answer
/// controls are STILL PRESENT on the suppressed question.
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
import 'package:lupin_mobile/services/tts/tts_orchestrator.dart';

class _MockFocusBloc extends MockBloc<FocusChatEvent, FocusChatState>
    implements FocusChatBloc {}

NotificationItem question( {
  String  id           = 'n-1',
  String  message      = 'Is that the same as: what is the weather?',
  String  responseType = 'yes_no',
} ) => NotificationItem(
  id                     : id,
  message                : message,
  type                   : 'custom',
  priority               : 'high',
  timestamp              : DateTime( 2026, 8, 29 ),
  played                 : false,
  playCount              : 0,
  responseRequested      : true,
  responseType           : responseType,
  suppressDing           : false,
  senderId               : 'ask.flow@lupin.deepily.ai',
  displayQualifierWidget : false,
);


void main() {
  late _MockFocusBloc bloc;
  late NotificationStopList sl;

  /// Arrange the REAL pane around one message. `suppressedRule` non-null is
  /// the state the bloc produces for an ACTIONABLE suppressed question — it is
  /// stored rather than dropped precisely so there is something to render.
  Future<void> arrange( { String? rule, String responseType = 'yes_no' } ) async {
    final sup = rule == null ? null : TtsSuppression(
      priority : 'high',
      message  : 'Is that the same as: what is the weather?',
      rule     : rule,
    );
    SharedPreferences.setMockInitialValues( {} );
    sl   = NotificationStopList( await SharedPreferences.getInstance() );
    bloc = _MockFocusBloc();
    final st = const FocusChatState.initial().copyWith(
      senderOrder   : const [ 'S' ],
      focusedSender : 'S',
      hydration     : FocusHydration.ready,
      windows       : { 'S': [ FocusMessage(
        item        : question( responseType: responseType ),
        suppression : sup,
      ) ] },
    );
    whenListen( bloc, Stream<FocusChatState>.fromIterable( [ st ] ), initialState: st );
  }

  Widget host() => MaterialApp( home: Scaffold( body: BlocProvider<FocusChatBloc>.value(
    value : bloc,
    child : FocusChatPane( userEmail: 'rick@test.com', stopList: sl ),
  ) ) );

  group( 'AC-S4.14 — the suppressed question is SHOWN, MARKED, and still ANSWERABLE', () {

    testWidgets( 'the notice renders IN THE PANE and NAMES the rule', ( tester ) async {
      await arrange( rule: 'Done: Bash' );
      await tester.pumpWidget( host() );
      await tester.pump();

      expect( find.byKey( const Key( TestKeys.promptSuppressedNotice ) ), findsOneWidget );
      expect( find.textContaining( 'Not spoken' ), findsOneWidget );
      expect( find.textContaining( 'Done: Bash' ), findsOneWidget,
          reason: 'the rule must be NAMED — "something was muted" is not actionable' );
    } );

    testWidgets( '🔴 the ANSWER AFFORDANCE survives the suppression', ( tester ) async {
      // The falsifier: rendering the notice in the answer card instead. The
      // user is told something was muted, has no way to act on it, and the
      // server stays blocked waiting for a reply that can never be sent.
      await arrange( rule: 'Done: Bash' );
      await tester.pumpWidget( host() );
      await tester.pump();

      expect( find.text( 'Yes' ), findsOneWidget,
          reason: 'a suppressed question must remain answerable' );
      expect( find.text( 'No' ),  findsOneWidget );
    } );

    testWidgets( 'the question TEXT is rendered regardless of suppression', ( tester ) async {
      await arrange( rule: 'Done: Bash' );
      await tester.pumpWidget( host() );
      await tester.pump();
      expect( find.text( 'Is that the same as: what is the weather?' ), findsOneWidget );
    } );

    testWidgets( 'an UNSUPPRESSED question renders no notice — the pane is unchanged', ( tester ) async {
      // The regression pin: this path is the overwhelmingly common one, and
      // Rick expects the suppression notice to fire approximately never.
      await arrange( rule: null );
      await tester.pumpWidget( host() );
      await tester.pump();

      expect( find.byKey( const Key( TestKeys.promptSuppressedNotice ) ), findsNothing );
      expect( find.text( 'Yes' ), findsOneWidget, reason: 'still answerable, as before' );
    } );

    testWidgets( 'speak-anyway is OFFERED, because the original suppression was retained', ( tester ) async {
      // It hands back the object gate 1 produced — not a reconstruction — so
      // what plays is exactly what was refused, with its own `verbatim` and
      // `sender` rather than guessed ones.
      await arrange( rule: 'Done: Bash' );
      await tester.pumpWidget( host() );
      await tester.pump();
      expect( find.byKey( const Key( TestKeys.promptSpeakAnyway ) ), findsOneWidget );
    } );

    testWidgets( 'NO dead button: with no retained suppression there is no speak-anyway', ( tester ) async {
      await arrange( rule: null );
      await tester.pumpWidget( host() );
      await tester.pump();
      expect( find.byKey( const Key( TestKeys.promptSpeakAnyway ) ), findsNothing );
    } );
  } );
}
