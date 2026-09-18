import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/docs/data/doc_link.dart';
import 'package:lupin_mobile/features/docs/data/doc_models.dart';
import 'package:lupin_mobile/features/docs/data/doc_repository.dart';
import 'package:lupin_mobile/features/docs/presentation/doc_panel.dart';
import 'package:lupin_mobile/features/docs/presentation/doc_viewer_screen.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_bloc.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_event.dart';
import 'package:lupin_mobile/features/focus_mode/domain/focus_chat_state.dart';
import 'package:lupin_mobile/features/focus_mode/presentation/focus_chat_pane.dart';
import 'package:lupin_mobile/features/notifications/data/notification_models.dart';
import 'package:lupin_mobile/services/notification_filter/notification_stop_list.dart';

class _MockFocusBloc extends MockBloc<FocusChatEvent, FocusChatState> implements FocusChatBloc {}

class _FakeDocRepository implements DocRepository {
  DocLink? lastRequested;

  @override
  Future<DocContent> fetch( DocLink link ) async {
    lastRequested = link;
    return const DocContent( kind: DocContentKind.markdown, mediaType: 'text/markdown', text: '# How to' );
  }

  @override
  dynamic noSuchMethod( Invocation invocation ) => super.noSuchMethod( invocation );
}

const _link = '[Open: how-to](/app/docs?path=lupin-mobile/src/rnd/2026.09.16-phone-install-and-record-how-to.md)';

NotificationItem _item( { String? abstractText } ) => NotificationItem(
  id: 'n1', message: 'The how-to is ready', type: 'custom', priority: 'high', senderId: 'S',
  timestamp: DateTime( 2026, 9, 16, 18 ), played: true, playCount: 0,
  responseRequested: false, suppressDing: true, displayQualifierWidget: false,
  abstractText: abstractText,
);

/// Row d7f56574 — doc links in focus-mode bubbles are tappable, and a document
/// opens over half the screen: the right half on an unfolded Fold, the bottom
/// half on a phone-shaped screen.
void main() {
  late _MockFocusBloc       bloc;
  late NotificationStopList sl;
  late _FakeDocRepository   repo;

  setUp( () async {
    SharedPreferences.setMockInitialValues( {} );
    sl   = NotificationStopList( await SharedPreferences.getInstance() );
    repo = _FakeDocRepository();
    GetIt.instance.registerSingleton<DocRepository>( repo );
    bloc = _MockFocusBloc();
  } );

  tearDown( () async => GetIt.instance.reset() );

  void stateWith( NotificationItem item ) {
    final st = const FocusChatState.initial().copyWith(
      senderOrder: const [ 'S' ], focusedSender: 'S', hydration: FocusHydration.ready,
      windows: { 'S': [ FocusMessage( item: item ) ] } );
    whenListen( bloc, Stream<FocusChatState>.fromIterable( [ st ] ), initialState: st );
  }

  Future<void> pumpAt( WidgetTester tester, Size screen ) async {
    tester.view.physicalSize     = screen;
    tester.view.devicePixelRatio = 1.0;
    addTearDown( tester.view.reset );
    await tester.pumpWidget( MaterialApp( home: Scaffold( body: BlocProvider<FocusChatBloc>.value(
      value: bloc, child: FocusChatPane( userEmail: 'rick@test.com', stopList: sl ) ) ) ) );
    await tester.pump();
  }

  group( 'placement rule', () {
    test( 'an open Fold (wide) gets the right half', () {
      expect( docPanelPlacementFor( const Size( 850, 900 ) ), DocPanelPlacement.rightHalf,
          reason: 'an unfolded inner screen can be slightly taller than wide; width decides' );
    } );
    test( 'a folded or ordinary phone (narrow) gets the bottom half', () {
      expect( docPanelPlacementFor( const Size( 412, 915 ) ), DocPanelPlacement.bottomHalf );
    } );
    test( 'the boundary is Material\'s compact/medium line, 600', () {
      expect( docPanelPlacementFor( const Size( 599, 900 ) ), DocPanelPlacement.bottomHalf );
      expect( docPanelPlacementFor( const Size( 600, 900 ) ), DocPanelPlacement.rightHalf );
    } );
  } );

  /// Since 2026-09-18 the bubble shows only the abstract's row; its links
  /// live in the viewer the row opens (a page here — this pane has no split
  /// host), and a doc link tapped there opens in the half-screen panel.
  Future<void> openLink( WidgetTester tester ) async {
    await tester.tap( find.byKey( const Key( TestKeys.abstractOpenButton ) ) );
    await tester.pumpAndSettle();
    await tester.tap( find.textContaining( 'Open: how-to' ) );
    await tester.pumpAndSettle();
  }

  group( 'focus-mode bubble', () {
    testWidgets( 'shows the abstract row, and the doc link inside it is tappable', ( tester ) async {
      stateWith( _item( abstractText: _link ) );
      await pumpAt( tester, const Size( 412, 915 ) );

      expect( find.byKey( const Key( TestKeys.abstractBody ) ), findsOneWidget );
      await openLink( tester );

      expect( find.byKey( const Key( TestKeys.docPanel ) ), findsOneWidget );
      expect( repo.lastRequested!.project, 'lupin-mobile' );
      expect( repo.lastRequested!.relPath, 'src/rnd/2026.09.16-phone-install-and-record-how-to.md' );
    } );

    testWidgets( 'no abstract: no card, and no repository lookup needed', ( tester ) async {
      await GetIt.instance.reset();
      stateWith( _item() );
      await pumpAt( tester, const Size( 412, 915 ) );

      expect( find.text( 'The how-to is ready' ), findsOneWidget );
      expect( find.byKey( const Key( TestKeys.abstractBody ) ), findsNothing );
    } );

    testWidgets( 'unfolded (wide): the document takes the right half, full height', ( tester ) async {
      stateWith( _item( abstractText: _link ) );
      await pumpAt( tester, const Size( 1000, 900 ) );
      await openLink( tester );

      final panel = find.byKey( const Key( TestKeys.docPanel ) );
      expect( tester.getSize( panel ), const Size( 500, 900 ) );
      expect( tester.getTopLeft( panel ), const Offset( 500, 0 ) );
    } );

    testWidgets( 'folded (narrow): the document takes the bottom half, full width', ( tester ) async {
      stateWith( _item( abstractText: _link ) );
      await pumpAt( tester, const Size( 400, 900 ) );
      await openLink( tester );

      final panel = find.byKey( const Key( TestKeys.docPanel ) );
      expect( tester.getSize( panel ), const Size( 400, 450 ) );
      expect( tester.getTopLeft( panel ), const Offset( 0, 450 ) );
    } );

    testWidgets( 'tapping the uncovered half closes the document', ( tester ) async {
      stateWith( _item( abstractText: _link ) );
      await pumpAt( tester, const Size( 1000, 900 ) );
      await openLink( tester );
      expect( find.byKey( const Key( TestKeys.docPanel ) ), findsOneWidget );

      await tester.tapAt( const Offset( 100, 450 ) );
      await tester.pumpAndSettle();
      expect( find.byKey( const Key( TestKeys.docPanel ) ), findsNothing );
      expect( find.byType( DocViewerScreen ), findsOneWidget, reason: 'back on the abstract' );
    } );
  } );
}
