/// AC-S4.5, AC-S4.11, AC-S4.16 — the canonical nested prompt payload, the
/// promoted multi-question body, and the status-blindness of the bodies.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/notifications/domain/notification_bloc.dart';
import 'package:lupin_mobile/features/notifications/domain/notification_event.dart';
import 'package:lupin_mobile/features/notifications/presentation/interactive_prompt_sheet.dart';
import 'package:lupin_mobile/shared/widgets/prompt_bodies.dart';

import '../../_harness/test_app.dart';

/// A canonical `ask_multiple_choice` payload as the server actually emits
/// it: questions NESTED under `response_options.questions[]`, each with its
/// own `question` / `header` / `options`. Mobile used to read
/// `response_options["options"]` at the TOP level, so this rendered an
/// empty list and submitted a bare label.
const canonical = {
  'questions': [
    {
      'question'     : 'Which database?',
      'header'       : 'Database',
      'multi_select' : false,
      'options'      : [
        { 'label': 'Postgres' },
        { 'label': 'SQLite'   },
      ],
    },
    {
      'question'     : 'Which regions?',
      'header'       : 'Regions',
      'multi_select' : true,
      'options'      : [
        { 'label': 'us-east' },
        { 'label': 'eu-west' },
      ],
    },
  ],
};

void main() {
  setUpAll( registerHarnessFallbacks );

  group( 'AC-S4.5 — the canonical nested payload renders and submits right', () {
    testWidgets( 'a non-empty option list renders for EVERY nested question',
                 ( tester ) async {
      await tester.pumpWidget( MaterialApp( home: Scaffold(
        body: MultiQuestionPromptBody(
          questions : canonical[ 'questions' ]! ,
          onRespond : ( _ ) {},
        ),
      ) ) );

      expect( find.text( 'Which database?' ), findsOneWidget );
      expect( find.text( 'Postgres' ), findsOneWidget );
      expect( find.text( 'SQLite'   ), findsOneWidget );
      expect( find.text( 'us-east'  ), findsOneWidget );
      expect( find.byType( RadioListTile<String> ), findsNWidgets( 2 ) );
      expect( find.byType( CheckboxListTile ),      findsNWidgets( 2 ) );
    } );

    testWidgets( 'answers are keyed by HEADER, not by label or position',
                 ( tester ) async {
      Map<String, dynamic>? submitted;
      await tester.pumpWidget( MaterialApp( home: Scaffold(
        body: MultiQuestionPromptBody(
          questions : canonical[ 'questions' ]!,
          onRespond : ( v ) => submitted = v,
        ),
      ) ) );

      await tester.tap( find.text( 'Postgres' ) );
      await tester.pump();
      await tester.tap( find.text( 'eu-west' ) );
      await tester.pump();
      await tester.tap( find.byKey( const Key( TestKeys.promptMultiQuestionSubmit ) ) );
      await tester.pump();

      expect( submitted, { 'Database': 'Postgres', 'Regions': [ 'eu-west' ] } );
    } );

    testWidgets( 'the SHEET wraps it as {"answers": {header: value}} — the '
                 'shape the server parser expects, not a bare label',
                 ( tester ) async {
      final bloc = MockNotificationBloc();
      await tester.pumpWidget( MaterialApp( home: BlocProvider<NotificationBloc>.value(
        value : bloc,
        child : const Scaffold( body: InteractivePromptSheet(
          notificationId : 'msg-1',
          responseType   : 'multiple_choice',
          options        : canonical,
        ) ),
      ) ) );

      await tester.tap( find.text( 'SQLite' ) );
      await tester.pump();
      await tester.tap( find.byKey( const Key( TestKeys.promptMultiQuestionSubmit ) ) );
      await tester.pump();

      final captured = verify( () => bloc.add( captureAny(
        that: isA<NotificationsRespond>() ) ) ).captured;
      final event = captured.single as NotificationsRespond;
      expect( event.responseValue, {
        'answers': { 'Database': 'SQLite', 'Regions': <String>[] },
      } );
    } );

    testWidgets( 'AC-S4.10b delta 3 — the SHEET is where the pane\'s "Answer '
                 'in full view" fallback lands, so it must not hit the same '
                 'wall: options are non-empty there too', ( tester ) async {
      final bloc = MockNotificationBloc();
      await tester.pumpWidget( MaterialApp( home: BlocProvider<NotificationBloc>.value(
        value : bloc,
        child : const Scaffold( body: InteractivePromptSheet(
          notificationId : 'msg-2',
          responseType   : 'multiple_choice',
          options        : canonical,
        ) ),
      ) ) );

      expect( find.text( 'Postgres' ), findsOneWidget,
              reason: 'reading options["options"] at the top level renders '
                      'NOTHING for a canonical payload' );
    } );

    testWidgets( 'a question with NO options is still a text field — the '
                 'open_ended_batch shape is unchanged', ( tester ) async {
      Map<String, dynamic>? submitted;
      await tester.pumpWidget( MaterialApp( home: Scaffold(
        body: MultiQuestionPromptBody(
          questions : const [
            { 'question': 'Why?', 'header': 'Reason' },
            'bare string question',
          ],
          onRespond : ( v ) => submitted = v,
        ),
      ) ) );

      expect( find.byType( TextField ), findsNWidgets( 2 ) );
      await tester.enterText( find.byType( TextField ).first, 'because' );
      await tester.tap( find.byKey( const Key( TestKeys.promptMultiQuestionSubmit ) ) );
      await tester.pump();

      expect( submitted![ 'Reason' ], 'because' );
      expect( submitted!.containsKey( 'q_1' ), isTrue,
              reason: 'positional fallback for a question with no header' );
    } );
  } );

  group( 'AC-S4.16 — the body was MOVED, not duplicated', () {
    final sheet  = File( 'lib/features/notifications/presentation/interactive_prompt_sheet.dart' )
        .readAsStringSync();
    final bodies = File( 'lib/shared/widgets/prompt_bodies.dart' ).readAsStringSync();

    test( 'the private copy is GONE from the sheet', () {
      expect( sheet.contains( '_OpenEndedBatchBody' ), isFalse,
              reason: 'an extraction that leaves the private original in '
                      'place is two widgets for one payload shape' );
      expect( sheet.contains( 'UNEXTRACTED' ), isFalse );
    } );

    test( 'the promoted body is the ONE that renders nested questions', () {
      expect( bodies.contains( 'class MultiQuestionPromptBody' ), isTrue );
      // Both hosts compose it rather than re-implementing.
      expect( sheet.contains( 'MultiQuestionPromptBody' ), isTrue );
      expect(
        File( 'lib/features/focus_mode/presentation/focus_chat_pane.dart' )
            .readAsStringSync().contains( 'MultiQuestionPromptBody' ),
        isTrue,
      );
    } );

    test( 'the comment that argued AGAINST extracting it no longer stands', () {
      // It cited the Map<String,String> submission as the reason to leave
      // the widget stranded — which is exactly what AC-S4.5 needs. A reader
      // who trusts a stale comment over the plan has a citation for doing
      // the wrong thing.
      expect( bodies.contains( 'deliberately NOT extracted' ), isFalse );
      expect( bodies.contains( 'AC-S4.16' ), isTrue,
              reason: 'the reversal is named where the old claim lived' );
    } );
  } );

  group( 'AC-S4.11 — bodies stay status-blind and door-agnostic', () {
    // 🔴 FALSIFIED 2026-08-29. These two are SOURCE checks — they read a file
    // and look for strings — so they are the easiest kind of test to write
    // wrong and never notice: a typo'd needle passes forever against every
    // possible source. Each was cut and each went red, in a private worktree:
    //
    //   a body imports the notification repository        +11 -1
    //   a body names "/api/v2/resume"                     +11 -1
    //   a body takes a `String status` (OPTIONAL, so the
    //     tree still compiles and the CHECK is what fires) +11 -1
    //   a body takes a `pendingId` — it knows the door     +11 -1
    //
    // ⚠️ The status mutant was cut TWICE. The first version made the parameter
    // `required`, which broke every call site: red, but red from the COMPILER,
    // which proves only that the mutant cannot exist. A source check is
    // falsified by a mutant the compiler accepts.
    final src = File( 'lib/shared/widgets/prompt_bodies.dart' ).readAsStringSync();

    test( 'no repository import, and neither endpoint is named', () {
      expect( src.contains( 'repository' ), isFalse );
      expect( src.contains( '/api/notify/response' ), isFalse );
      expect( src.contains( '/api/v2/resume' ), isFalse );
    } );

    test( 'no body takes a status or an endpoint parameter', () {
      // The host branches on `status` and picks the door; a body that
      // learned either would render correctly and still be the shape
      // fracturing.
      for ( final banned in [ 'String status', 'required this.status',
                              'String endpoint', 'pendingId', 'pending_id' ] ) {
        expect( src.contains( banned ), isFalse, reason: 'found "$banned"' );
      }
    } );

    testWidgets( 'each body produces its value with NOTHING but its data and '
                 'a stub callback in scope', ( tester ) async {
      // Mounted one at a time, deliberately: a body that needed a sibling,
      // a provider or a repository in scope would fail here and pass in a
      // fuller tree.
      String? yesNo;
      await tester.pumpWidget( MaterialApp( home: Scaffold(
        body: YesNoPromptBody( onRespond: ( v ) => yesNo = v ) ) ) );
      await tester.tap( find.byKey( const Key( TestKeys.promptYesButton ) ) );
      await tester.pump();
      expect( yesNo, 'yes' );

      dynamic choice;
      await tester.pumpWidget( MaterialApp( home: Scaffold(
        body: MultipleChoicePromptBody(
          options   : const [ { 'label': 'A' } ],
          multi     : false,
          onRespond : ( v ) => choice = v,
        ) ) ) );
      await tester.tap( find.text( 'A' ) );
      await tester.pump();
      await tester.tap( find.widgetWithText( FilledButton, 'Submit' ) );
      await tester.pump();
      expect( choice, 'A' );

      String? open;
      await tester.pumpWidget( MaterialApp( home: Scaffold(
        body: OpenEndedPromptBody( onRespond: ( v ) => open = v ) ) ) );
      await tester.enterText( find.byType( TextField ), 'typed' );
      await tester.tap( find.widgetWithText( FilledButton, 'Submit' ) );
      await tester.pump();
      expect( open, 'typed' );

      Map<String, dynamic>? multi;
      await tester.pumpWidget( MaterialApp( home: Scaffold(
        body: MultiQuestionPromptBody(
          questions : const [ { 'question': 'Q', 'header': 'H' } ],
          onRespond : ( v ) => multi = v,
        ) ) ) );
      await tester.tap( find.byKey( const Key( TestKeys.promptMultiQuestionSubmit ) ) );
      await tester.pump();
      expect( multi!.keys.single, 'H' );
    } );
  } );

  group( 'the wrapping lives in the HOST, not the body', () {
    test( 'the body hands back a bare {header: value} map', () {
      // Proven by the two submission tests above: the body produced
      // {'Database': …} while the sheet emitted {'answers': {…}}. Recorded
      // as a named claim so the next reader sees the seam deliberately.
      expect( jsonEncode( { 'answers': { 'H': 'v' } } ),
              '{"answers":{"H":"v"}}' );
    } );
  } );
}
