import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/broadcast/data/broadcast_models.dart';
import 'package:lupin_mobile/features/broadcast/data/broadcast_repository.dart';
import 'package:lupin_mobile/features/broadcast/domain/broadcast_bloc.dart';
import 'package:lupin_mobile/features/broadcast/presentation/broadcast_pane.dart';

import '../../unit/_helpers/stub_dio.dart';

/// The Broadcast pane, driven through the real widget tree.
///
/// 🔴 THE SEAM TEST BELOW IS THE ONE THAT MATTERS. Unit tests either side of a seam are
/// structurally incapable of failing on the seam — Chloé's arm C killed four tests while
/// twenty-two stayed green. So the send test taps the real button, answers the real
/// dialog, and asserts the request that ACTUALLY WENT OUT, rather than asserting that an
/// event was added to a bloc.
void main() {
  late StubAdapter adapter;

  dynamic fixture( String name ) =>
      jsonDecode( File( 'test/fixtures/commons/$name' ).readAsStringSync() );

  setUp( () {
    adapter = StubAdapter();
    adapter.handlers[ 'GET ${BroadcastRepository.activeSessionsPath}' ] =
        ( _ ) => jsonBody( fixture( 'active_sessions.json' ) );
    adapter.handlers[ 'GET ${BroadcastRepository.historyPath}' ] =
        ( _ ) => jsonBody( fixture( 'broadcast_history.json' ) );
    adapter.handlers[ 'POST ${BroadcastRepository.broadcastPath}' ] =
        ( _ ) => jsonBody( fixture( 'broadcast_send_queued.json' ) );
  } );

  /// 360×800 — ordinary Android portrait, never the 800×600 harness default. A layout
  /// test at the default proves the layout works on a device nobody has.
  void sizePhone( WidgetTester tester ) {
    tester.view.physicalSize     = const Size( 360, 800 );
    tester.view.devicePixelRatio = 1.0;
    addTearDown( tester.view.resetPhysicalSize );
    addTearDown( tester.view.resetDevicePixelRatio );
  }

  /// The close is registered at construction and runs at teardown, outside the
  /// fake-async zone. `await bloc.close()` inside a `testWidgets` body never returns for
  /// any bloc carrying an `on<Event>` handler — see `pane_cell_parity_test.dart`.
  BroadcastBloc pump( WidgetTester tester, { BroadcastBloc? bloc } ) {
    final b = bloc ?? BroadcastBloc( BroadcastRepository( makeDio( adapter ) ) );
    addTearDown( b.close );
    return b;
  }

  /// 🔴 `runAsync` THEN `pumpAndSettle` — AND BOTH HALVES ARE LOAD-BEARING.
  ///
  /// Measured here the hard way. `runAsync` alone lets the stubbed HTTP response resolve
  /// on the REAL loop, which is why the Holding Area pane test needs it. But Dio also
  /// schedules a zero-duration `Timer` INSIDE the fake-async zone (`DioMixin.fetch`), and
  /// a single `tester.pump()` does not drain it. The test then ends with pending timers
  /// and flutter_test fails it — after which the runner hangs on cleanup and reports
  /// *"the Dart compiler exited unexpectedly"*, which points nowhere near the cause and
  /// cost a bisect to disbelieve.
  ///
  /// ⚠️ `pumpAndSettle` IS ONLY SAFE HERE BECAUSE THIS PANE HAS NO SPINNER. It waits for
  /// animations to finish, and a `CircularProgressIndicator` never finishes — that is the
  /// hang documented in `pane_cell_parity_test.dart`. The loading state here is the text
  /// "Sending to: …", deliberately.
  Future<void> settle( WidgetTester tester ) async {
    await tester.runAsync( () => Future<void>.delayed( const Duration( milliseconds: 60 ) ) );
    await tester.pumpAndSettle();
  }

  Future<BroadcastBloc> mount( WidgetTester tester ) async {
    sizePhone( tester );
    final bloc = pump( tester );

    await tester.pumpWidget( MaterialApp(
      home : Scaffold(
        body : BlocProvider<BroadcastBloc>.value( value: bloc, child: const BroadcastPane() ),
      ),
    ) );
    await settle( tester );
    return bloc;
  }

  testWidgets( 'renders at 360x800 without overflowing', ( tester ) async {
    await mount( tester );

    expect( find.byKey( const Key( TestKeys.broadcastView ) ), findsOneWidget );
    expect( tester.takeException(), isNull );
  } );

  testWidgets( '🔴 the reason Send is dead is ON SCREEN, not in a tooltip', ( tester ) async {
    adapter.handlers[ 'GET ${BroadcastRepository.activeSessionsPath}' ] =
        ( _ ) => jsonBody( const { 'sessions' : [] } );

    await mount( tester );
    await tester.enterText( find.byKey( const Key( TestKeys.broadcastBodyField ) ), 'all hands' );
    await tester.pump();

    // A phone cannot hover. If this text is absent, the operator is holding a typed
    // message and a grey button with no way to find out why.
    final reason = find.byKey( const Key( TestKeys.broadcastDisabledReason ) );
    expect( reason, findsOneWidget );
    expect( tester.widget<Text>( reason ).data, contains( 'Nobody is listening' ) );

    final send = tester.widget<FilledButton>(
      find.byKey( const Key( TestKeys.broadcastSendButton ) ),
    );
    expect( send.onPressed, isNull, reason: 'Send must be genuinely disabled, not just styled so' );
  } );

  testWidgets( 'with a body AND recipients, Send is live and the reason is gone', ( tester ) async {
    await mount( tester );
    await tester.enterText( find.byKey( const Key( TestKeys.broadcastBodyField ) ), 'all hands' );
    await tester.pump();

    expect( find.byKey( const Key( TestKeys.broadcastDisabledReason ) ), findsNothing );
    expect(
      tester.widget<FilledButton>(
        find.byKey( const Key( TestKeys.broadcastSendButton ) ),
      ).onPressed,
      isNotNull,
    );
  } );

  group( '🔴 THE SEAM — a real tap, and the request that actually went out', () {
    testWidgets( 'tap Send, confirm, and the POST carries the body and both flags',
        ( tester ) async {
      await mount( tester );

      await tester.enterText(
        find.byKey( const Key( TestKeys.broadcastBodyField ) ),
        'standup in five',
      );
      await tester.pump();

      await tester.tap( find.byKey( const Key( TestKeys.broadcastSendButton ) ) );
      await tester.pump();

      expect( find.byKey( const Key( TestKeys.broadcastSendConfirm ) ), findsOneWidget );

      await tester.tap( find.byKey( const Key( TestKeys.broadcastSendConfirmOk ) ) );
      await settle( tester );

      final posts = adapter.captured.where( ( r ) => r.method == 'POST' ).toList();
      expect( posts, hasLength( 1 ), reason: 'exactly one broadcast should have gone out' );

      final body = posts.single.data as Map<String, dynamic>;
      expect( body[ 'message' ],            'standup in five' );
      expect( body[ 'require_ack' ],        isTrue );
      expect( body[ 'include_originator' ], isTrue );
    } );

    testWidgets( '🔴 CANCEL sends NOTHING', ( tester ) async {
      await mount( tester );

      await tester.enterText( find.byKey( const Key( TestKeys.broadcastBodyField ) ), 'oops' );
      await tester.pump();
      await tester.tap( find.byKey( const Key( TestKeys.broadcastSendButton ) ) );
      await tester.pump();
      await tester.tap( find.byKey( const Key( TestKeys.broadcastSendConfirmNo ) ) );
      await settle( tester );

      // A confirm that does not actually gate is worse than no confirm: it teaches the
      // operator that the dialog is where the decision happens.
      expect( adapter.captured.where( ( r ) => r.method == 'POST' ), isEmpty );
    } );

    testWidgets( 'the confirm names the recipient count before anyone is interrupted',
        ( tester ) async {
      await mount( tester );
      await tester.enterText( find.byKey( const Key( TestKeys.broadcastBodyField ) ), 'x' );
      await tester.pump();
      await tester.tap( find.byKey( const Key( TestKeys.broadcastSendButton ) ) );
      await tester.pump();

      expect( find.text( 'Send to 3 sessions?' ), findsOneWidget );
      // The chips, so "3" is not the only thing standing between the operator and
      // interrupting three working seats.
      expect( find.byType( Chip ), findsNWidgets( 3 ) );
    } );
  } );

  group( '🔴 the tally never shows a denominator it cannot stand behind', () {
    testWidgets( 'observed acks read as an exact fraction', ( tester ) async {
      final bloc = await mount( tester );

      await tester.enterText( find.byKey( const Key( TestKeys.broadcastBodyField ) ), 'x' );
      await tester.pump();
      await tester.tap( find.byKey( const Key( TestKeys.broadcastSendButton ) ) );
      await tester.pump();
      await tester.tap( find.byKey( const Key( TestKeys.broadcastSendConfirmOk ) ) );
      await settle( tester );

      bloc.add( const BroadcastAckReceived( BroadcastAck(
        broadcastId : 'b-fixture-0001',
        sessionId   : 'sess-fixture-1',
        personaName : 'maria',
        bodySummary : 'on it',
      ) ) );
      await tester.pumpAndSettle();

      expect(
        tester.widget<Text>( find.byKey( const Key( TestKeys.broadcastAckSummary ) ) ).data,
        '1 of 3 acked',
      );
    } );

    testWidgets( '🔴 after the listening window breaks, NO denominator appears',
        ( tester ) async {
      final bloc = await mount( tester );

      await tester.enterText( find.byKey( const Key( TestKeys.broadcastBodyField ) ), 'x' );
      await tester.pump();
      await tester.tap( find.byKey( const Key( TestKeys.broadcastSendButton ) ) );
      await tester.pump();
      await tester.tap( find.byKey( const Key( TestKeys.broadcastSendConfirmOk ) ) );
      await settle( tester );

      bloc.add( const BroadcastAckReceived( BroadcastAck(
        broadcastId : 'b-fixture-0001', sessionId : 'sess-fixture-1',
      ) ) );
      bloc.add( const BroadcastListeningInterrupted() );
      await tester.pumpAndSettle();

      final summary = tester
          .widget<Text>( find.byKey( const Key( TestKeys.broadcastAckSummary ) ) ).data!;

      // "1 of 3 acked" here would read as two seats ignoring the operator. What actually
      // happened is that the phone stopped listening.
      expect( summary, isNot( contains( 'of 3' ) ) );
      expect( summary, contains( 'could not be confirmed' ) );
    } );
  } );

  group( '🔴 THE SANITIZATION ASYMMETRY — it is a safety property, not an inconsistency',
      () {
    testWidgets( 'the compose preview renders MARKDOWN', ( tester ) async {
      await mount( tester );
      await tester.enterText(
        find.byKey( const Key( TestKeys.broadcastBodyField ) ),
        '**bold**',
      );
      await tester.pump();

      final preview = find.byKey( const Key( TestKeys.broadcastPreview ) );
      expect( preview, findsOneWidget );
      expect(
        find.descendant( of: preview, matching: find.byType( MarkdownBody ) ),
        findsOneWidget,
      );
    } );

    testWidgets( '🔴 an ack summary is PLAIN TEXT — never a markdown widget',
        ( tester ) async {
      final bloc = await mount( tester );

      await tester.enterText( find.byKey( const Key( TestKeys.broadcastBodyField ) ), 'x' );
      await tester.pump();
      await tester.tap( find.byKey( const Key( TestKeys.broadcastSendButton ) ) );
      await tester.pump();
      await tester.tap( find.byKey( const Key( TestKeys.broadcastSendConfirmOk ) ) );
      await settle( tester );

      bloc.add( const BroadcastAckReceived( BroadcastAck(
        broadcastId : 'b-fixture-0001',
        sessionId   : 'sess-fixture-1',
        personaName : 'maria',
        bodySummary : '**not bold**',
      ) ) );
      await tester.pumpAndSettle();

      final row = find.byKey( const Key( '${TestKeys.broadcastAckRowPrefix}sess-fixture-1' ) );
      expect( row, findsOneWidget );

      // The compose preview is the operator's OWN text. An ack's body_summary is ANOTHER
      // SESSION'S text — the web sets it via textContent, never innerHTML, and letting
      // both become a markdown widget would look tidier and would be the bug.
      expect(
        find.descendant( of: row, matching: find.byType( MarkdownBody ) ),
        findsNothing,
      );
      expect( find.text( '**not bold**' ), findsOneWidget );
    } );
  } );

  testWidgets( 'the placeholder teaches the @PersonaName convention', ( tester ) async {
    await mount( tester );

    // It is the ONLY place a user learns this convention exists. Shortening it to
    // "Message" would delete the feature's discoverability.
    final field = tester.widget<TextField>(
      find.byKey( const Key( TestKeys.broadcastBodyField ) ),
    );
    expect( field.decoration!.hintText, contains( '@PersonaName:' ) );
    expect( field.decoration!.hintText, contains( 'Markdown' ) );
  } );

  testWidgets( 'the recipient surface is a count and a refresh, NOT a picker',
      ( tester ) async {
    await mount( tester );

    expect(
      tester.widget<Text>(
        find.byKey( const Key( TestKeys.broadcastRecipientCount ) ),
      ).data,
      'Sending to: 3 sessions',
    );
    expect( find.byKey( const Key( TestKeys.broadcastRecipientRefresh ) ), findsOneWidget );
    // No checkboxes, no per-session toggles: you address everyone or nobody, and a
    // picker would imply otherwise.
    expect( find.byType( Checkbox ), findsNothing );
  } );
}
