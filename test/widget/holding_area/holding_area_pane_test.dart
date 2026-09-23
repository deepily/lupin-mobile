import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/fleet/data/task_write_repository.dart';
import 'package:lupin_mobile/features/fleet/presentation/task_row.dart';
import 'package:lupin_mobile/features/holding_area/data/holding_area_repository.dart';
import 'package:lupin_mobile/features/holding_area/domain/holding_area_bloc.dart';
import 'package:lupin_mobile/features/holding_area/presentation/filer_group_header.dart';
import 'package:lupin_mobile/features/holding_area/presentation/holding_area_pane.dart';

import '../../unit/_helpers/stub_dio.dart';

/// The whole pane, at 360×800.
///
/// 🔴 THE POINT OF TESTING THE PANE RATHER THAN ONLY ITS PARTS IS THE WIRING. A header
/// whose approve-all fires correctly and a bloc that batches correctly still add up to
/// nothing if the pane hands the wrong filer down, and both component suites pass while
/// it does.

Map<String, dynamic> _page( List<Map<String, dynamic>> rows, { bool hasMore = false } ) => {
      'tasks'     : rows,
      'truncated' : false,
      'has_more'  : hasMore,
      'total'     : rows.length,
      'warnings'  : <String>[],
    };

Map<String, dynamic> _row( String id, String filer ) => {
      'id'         : id,
      'title'      : '[LUPIN-MOBILE] Phase 4: held row $id with a long fleet-style title',
      'status'     : 'not_approved',
      'priority'   : 'P2',
      'created_by' : filer,
    };

Map<String, dynamic> _fixture( String name ) =>
    jsonDecode( File( 'test/fixtures/tasks/$name' ).readAsStringSync() )
        as Map<String, dynamic>;

List<String> _transitionIds( StubAdapter a ) => a.captured
    .where( ( o ) => o.method == 'POST' && o.path.contains( '/transition' ) )
    .map( ( o ) => Uri.decodeComponent( o.path.split( '/' )[ 3 ] ) )
    .toList();

/// ⚠️ `pumpAndSettle` ALONE IS NOT ENOUGH HERE, AND IT FAILS QUIETLY. It drives the
/// test's fake clock, and the stubbed HTTP response resolves on the REAL one — so the
/// fetch is still in flight when the assertions run and every pane test sees an empty
/// pane. `runAsync` lets real async actually happen before the frames are pumped.
Future<void> settle( WidgetTester tester ) async {
  await tester.runAsync( () => Future<void>.delayed( const Duration( milliseconds: 60 ) ) );
  await tester.pumpAndSettle();
}


/// Unfold one persona's group. Everything arrives folded (Rick's N2), so any test that
/// wants to see or touch a ROW has to open the group first — which is itself the
/// clearest statement of what folded-by-default means.
///
/// ⚠️ IT SETTLES IN REAL TIME, NOT WITH `pumpAndSettle` ALONE. The tap adds a bloc
/// event, the handler runs on the real event loop, and `pumpAndSettle` drives only the
/// test's fake clock — so the rebuild carrying the unfolded rows has not happened when
/// the assertions run, and the test fails against a pane that works. Same trap the
/// `settle` helper above was written for.
Future<void> expandGroup( WidgetTester tester, String filer ) async {
  await tester.tap( find.byKey( Key( '${TestKeys.holdingGroupTogglePrefix}$filer' ) ) );
  await tester.runAsync( () => Future<void>.delayed( const Duration( milliseconds: 20 ) ) );
  await tester.pumpAndSettle();
}

void main() {
  late StubAdapter adapter;
  late HoldingAreaBloc bloc;

  setUp( () {
    adapter = StubAdapter();
    final dio = makeDio( adapter );
    bloc = HoldingAreaBloc( HoldingAreaRepository( dio ), TaskWriteRepository( dio ) );
    for ( final id in [ 'a', 'b', 'c' ] ) {
      adapter.handlers[ 'POST /api/tasks/$id/transition' ] = ( _ ) => jsonBody( {} );
    }
  } );

  tearDown( () async => bloc.close() );

  /// 360×800 — ordinary Android portrait, never the 800×600 harness default.
  Future<void> pumpPane( WidgetTester tester ) async {
    tester.view.physicalSize     = const Size( 360, 800 );
    tester.view.devicePixelRatio = 1.0;
    addTearDown( tester.view.resetPhysicalSize );
    addTearDown( tester.view.resetDevicePixelRatio );

    await tester.pumpWidget( MaterialApp(
      home : BlocProvider<HoldingAreaBloc>.value(
        value : bloc,
        child : const Scaffold( body: HoldingAreaPane() ),
      ),
    ) );
    await settle( tester );
  }

  void serve( List<Map<String, dynamic>> rows, { bool hasMore = false } ) {
    adapter.handlers[ 'GET ${HoldingAreaRepository.path}' ] =
        ( _ ) => jsonBody( _page( rows, hasMore: hasMore ) );
  }

  group( "the groups", () {
    testWidgets( "🔴 one header per PERSONA, not per session", ( tester ) async {
      // Rick's R1=B end to end: three sessions across two people is two headers, and the
      // pane must hand the bloc the same key it printed.
      serve( [
        _row( 'a', 'sam 11111111' ),
        _row( 'b', 'chloe 22222222' ),
        _row( 'c', 'sam 33333333' ),
      ] );
      await pumpPane( tester );

      expect( find.byType( FilerGroupHeader ), findsNWidgets( 2 ) );
      expect( find.text( 'Chloe · 1' ), findsOneWidget );
      expect( find.text( 'Sam · 2' ), findsOneWidget,
          reason: "Sam's two SESSIONS are one group of two rows" );
    } );

    testWidgets( "🔴 every group arrives FOLDED — no held row is on screen", ( tester ) async {
      // N2a. The default is the feature: *"displayed folded by default so that we can do
      // progressive disclosure."*
      serve( [ _row( 'a', 'sam' ), _row( 'b', 'chloe' ), _row( 'c', 'sam' ) ] );
      await pumpPane( tester );

      expect( find.byType( FilerGroupHeader ), findsNWidgets( 2 ) );
      expect( find.byType( TaskRow ), findsNothing );
    } );

    testWidgets( "unfolding ONE persona shows that persona's rows and no others",
        ( tester ) async {
      serve( [ _row( 'a', 'sam' ), _row( 'b', 'chloe' ), _row( 'c', 'sam' ) ] );
      await pumpPane( tester );

      await expandGroup( tester, 'Sam' );

      expect( find.byType( TaskRow ), findsNWidgets( 2 ),
          reason: "Chloe's row stays folded — toggling is per persona" );
    } );

    testWidgets( "🔴 two groups can be open at once — this is not a single-open "
        "accordion", ( tester ) async {
      // Opening one must not close the other, or comparing two personas' held work
      // means scrolling back and forth. *"toggle or collapse each individual persona's
      // items"* — each, independently.
      serve( [ _row( 'a', 'sam' ), _row( 'b', 'chloe' ), _row( 'c', 'sam' ) ] );
      await pumpPane( tester );

      await expandGroup( tester, 'Sam' );
      await expandGroup( tester, 'Chloe' );

      expect( find.byType( TaskRow ), findsNWidgets( 3 ) );
    } );

    testWidgets( "folding again puts the rows away", ( tester ) async {
      serve( [ _row( 'a', 'sam' ), _row( 'b', 'sam' ) ] );
      await pumpPane( tester );

      await expandGroup( tester, 'Sam' );
      expect( find.byType( TaskRow ), findsNWidgets( 2 ) );

      await expandGroup( tester, 'Sam' );
      expect( find.byType( TaskRow ), findsNothing );
    } );

    testWidgets( "🔴 a poll does NOT re-fold the group the operator opened",
        ( tester ) async {
      // ⚠️ THE DEFECT THIS PINS: the refresh handler replaces `groups`, and an expansion
      // set rebuilt from the new page would close every group every 60–180 seconds,
      // mid-read. The operator's choice is the operator's.
      serve( [ _row( 'a', 'sam' ), _row( 'b', 'sam' ) ] );
      await pumpPane( tester );
      await expandGroup( tester, 'Sam' );

      bloc.add( const HoldingAreaRefreshRequested() );
      await settle( tester );

      expect( find.byType( TaskRow ), findsNWidgets( 2 ) );
    } );

    testWidgets( "🔴 renders the SHARED TaskRow, not a bespoke Holding Area row", ( tester ) async {
      // §7's mechanism is that the row takes no pane discriminator. A pane that grew its
      // own row would pass every other test in this file.
      serve( [ _row( 'a', 'sam' ) ] );
      await pumpPane( tester );
      await expandGroup( tester, 'Sam' );

      expect( find.byType( TaskRow ), findsOneWidget );
    } );
  } );

  group( "empty, error, incomplete", () {
    testWidgets( "an empty held set says so", ( tester ) async {
      serve( const [] );
      await pumpPane( tester );

      expect( find.byKey( const Key( TestKeys.holdingEmptyState ) ), findsOneWidget );
    } );

    testWidgets( "an incomplete page raises the banner", ( tester ) async {
      serve( [ _row( 'a', 'sam' ) ], hasMore: true );
      await pumpPane( tester );

      expect( find.byKey( const Key( TestKeys.holdingIncompleteBanner ) ), findsOneWidget );
    } );

    testWidgets( "a fetch failure with no rows shows the error view and a retry", ( tester ) async {
      adapter.handlers[ 'GET ${HoldingAreaRepository.path}' ] =
          ( _ ) => jsonBody( { 'detail': 'boom' }, status: 500 );
      await pumpPane( tester );

      expect( find.byKey( const Key( TestKeys.holdingErrorView ) ), findsOneWidget );
      expect( find.text( 'Retry' ), findsOneWidget );
    } );
  } );

  group( "🔴 the batch, end to end through the pane", () {
    testWidgets( "approve-all confirms, then writes only that filer's rows", ( tester ) async {
      serve( [ _row( 'a', 'sam' ), _row( 'b', 'chloe' ), _row( 'c', 'sam' ) ] );
      await pumpPane( tester );

      await tester.tap( find.byKey( const Key( '${TestKeys.holdingApproveAllPrefix}Sam' ) ) );
      await tester.pumpAndSettle();
      await tester.tap( find.byKey( const Key( TestKeys.holdingApproveAllConfirmOk ) ) );
      await settle( tester );

      expect( _transitionIds( adapter ), [ 'a', 'c' ],
          reason: "Chloe's held row must not move" );
    } );

    testWidgets( "🔴 approve-all spans EVERY session, and the button and confirm both "
        "say so", ( tester ) async {
      // 🔴 THE ONE THING R1=B STILL OWED. Merging sessions widens what one press does,
      // so the count on the control and the count in the confirm have to be the WIDER
      // number — *"A batch control whose label undercounts what it does is a defect
      // under any grouping scheme."* Driven through the real widget tree from a folded
      // group, which is where the operator would actually press it.
      serve( [
        _row( 'a', 'sam 11111111' ),
        _row( 'b', 'sam 22222222' ),
        _row( 'c', 'sam 22222222' ),
      ] );
      await pumpPane( tester );

      expect( find.text( 'Approve (3)' ), findsOneWidget,
          reason: 'three rows across two sessions, one number' );

      await tester.tap( find.byKey( const Key( '${TestKeys.holdingApproveAllPrefix}Sam' ) ) );
      await tester.pumpAndSettle();

      expect( find.textContaining( '3 rows filed by Sam' ), findsOneWidget );
      await tester.tap( find.byKey( const Key( TestKeys.holdingApproveAllConfirmOk ) ) );
      await settle( tester );

      expect( _transitionIds( adapter ), [ 'a', 'b', 'c' ],
          reason: 'the send is the number the button printed' );
    } );

    testWidgets( "cancelling the confirm writes NOTHING", ( tester ) async {
      serve( [ _row( 'a', 'sam' ) ] );
      await pumpPane( tester );

      await tester.tap( find.byKey( const Key( '${TestKeys.holdingApproveAllPrefix}Sam' ) ) );
      await tester.pumpAndSettle();
      await tester.tap( find.byKey( const Key( TestKeys.holdingApproveAllConfirmNo ) ) );
      await tester.pumpAndSettle();

      expect( _transitionIds( adapter ), isEmpty );
    } );

    testWidgets( "🔴 won't-fix-all with an empty box writes NOTHING, UNFOLDS the group "
                 "and complains in the field", ( tester ) async {
      // 🔴 THE UNFOLD IS THE PART FOLDING MADE NECESSARY. The batch controls stay on
      // screen while folded but the reason box does not, so without this the press sets
      // a complaint about a field the operator cannot see, and the pane's only feedback
      // is that nothing happened. Pressed from the FOLDED state on purpose — that is the
      // state the operator meets first.
      serve( [ _row( 'a', 'sam' ), _row( 'c', 'sam' ) ] );
      await pumpPane( tester );

      expect( find.byKey( const Key( '${TestKeys.holdingReasonFieldPrefix}Sam' ) ),
          findsNothing, reason: 'folded: the box is not in the tree yet' );

      await tester.tap( find.byKey( const Key( '${TestKeys.holdingWontFixAllPrefix}Sam' ) ) );
      await settle( tester );

      expect( _transitionIds( adapter ), isEmpty );
      final field = tester.widget<TextField>(
        find.byKey( const Key( '${TestKeys.holdingReasonFieldPrefix}Sam' ) ) );
      expect( field.decoration!.errorText, isNotNull );
    } );

    testWidgets( "typed reason reaches the wire on every row of the group", ( tester ) async {
      serve( [ _row( 'a', 'sam' ), _row( 'c', 'sam' ) ] );
      await pumpPane( tester );
      // The box lives with the rows it justifies closing, so the group has to be open.
      await expandGroup( tester, 'Sam' );

      await tester.enterText(
        find.byKey( const Key( '${TestKeys.holdingReasonFieldPrefix}Sam' ) ),
        'superseded by the rewrite',
      );
      // ⚠️ A REAL-TIME SETTLE AFTER THE TYPING TOO, NOT ONLY AFTER THE PRESS. The
      // keystroke reaches the bloc, but the pane's rebuild — and with it the fresh
      // callback that carries the typed reason — lands after `pumpAndSettle` has already
      // decided nothing more is scheduled. Without this the press fires the PREVIOUS
      // build's closure, sends an empty reason, and the test fails against a pane that
      // works.
      await settle( tester );
      await tester.tap( find.byKey( const Key( '${TestKeys.holdingWontFixAllPrefix}Sam' ) ) );
      await settle( tester );

      final bodies = adapter.captured
          .where( ( o ) => o.path.contains( '/transition' ) )
          .map( ( o ) => ( o.data as Map ).cast<String, dynamic>() )
          .toList();

      expect( bodies.length, 2 );
      expect( bodies.every( ( b ) => b[ 'reason' ] == 'superseded by the rewrite' ), isTrue );
      expect( bodies.every( ( b ) => b[ 'to_status' ] == 'wont_fix' ), isTrue );
    } );

    testWidgets( "🔴 a partial batch leaves a notice ON SCREEN, not in a snackbar",
        ( tester ) async {
      // A snackbar takes it away on a timer while the rows it describes are still there,
      // and this is the one message this pane produces that the operator must act on.
      serve( [ _row( 'a', 'sam' ), _row( 'c', 'sam' ) ] );
      adapter.handlers[ 'POST /api/tasks/c/transition' ] =
          ( _ ) => jsonBody( { 'detail': 'nope' }, status: 500 );
      await pumpPane( tester );

      await tester.tap( find.byKey( const Key( '${TestKeys.holdingApproveAllPrefix}Sam' ) ) );
      await tester.pumpAndSettle();
      await tester.tap( find.byKey( const Key( TestKeys.holdingApproveAllConfirmOk ) ) );
      await settle( tester );

      expect( find.byKey( const Key( TestKeys.holdingNotice ) ), findsOneWidget );
      expect( find.textContaining( '1 of 2' ), findsOneWidget );
      expect( find.byType( SnackBar ), findsNothing );
    } );
  } );

  group( "🔴 the pane POLLS — gap G3", () {
    // 🔴 EVERY PART OF POLLING EXISTED BEFORE THIS AND NOTHING PULLED THE CORD. The bloc
    // mixed in `PanePollingMixin`, overrode `pollInterval` to read the connection, and
    // honoured the cancel token — but no code under `lib/features/holding_area` ever
    // called `startPolling` or `onPaneVisible`, so held work updated only on mount, on
    // pull-to-refresh, or on a reconnect. A reviewer reading the bloc sees a complete
    // feature; only the pane shows that it never ran.

    int fetches( StubAdapter a ) => a.captured
        .where( ( o ) => o.method == 'GET' && o.path.contains( HoldingAreaRepository.path ) )
        .length;

    testWidgets( "becoming visible issues the first fetch — and only one", ( tester ) async {
      // ⚠️ AND ONLY ONE. The pane used to `add( HoldingAreaRefreshRequested() )` in
      // `initState`; `onPaneVisible` fires a fetch of its own, so keeping both would
      // double every arrival on this pane.
      serve( [ _row( 'a', 'sam' ) ] );
      await pumpPane( tester );

      expect( fetches( adapter ), 1 );
      expect( bloc.isPolling, isTrue, reason: 'the timer is running while on screen' );
    } );

    testWidgets( "🔴 the timer fires a SECOND fetch with nobody touching the pane",
        ( tester ) async {
      serve( [ _row( 'a', 'sam' ) ] );
      await pumpPane( tester );
      expect( fetches( adapter ), 1 );

      // One interval on the test clock. 60 s is the wifi figure — `isMobile` is false
      // with no connectivity plugin under test, and the 180 s mobile path is pinned
      // separately against an injected service.
      await tester.pump( const Duration( seconds: 61 ) );
      await settle( tester );

      expect( fetches( adapter ), 2, reason: 'a poll tick, not a gesture' );
    } );

    testWidgets( "🔴 leaving the pane stops the timer", ( tester ) async {
      // The other half of G3, and the one that costs battery rather than freshness: a
      // pane whose timer survives its route polls against a screen nobody is looking at
      // for the life of the process.
      serve( [ _row( 'a', 'sam' ) ] );
      await pumpPane( tester );

      // ⚠️ PROVE THE TIMER WAS RUNNING FIRST. Without this tick the assertion below —
      // "no further requests" — is satisfied just as well by a pane that never polled at
      // all, which is the exact bug this group exists to catch. A test that passes
      // without the feature is worse than no test.
      await tester.pump( const Duration( seconds: 61 ) );
      await settle( tester );
      expect( fetches( adapter ), 2, reason: 'the timer is demonstrably alive' );

      await tester.pumpWidget( const MaterialApp( home: Scaffold( body: SizedBox() ) ) );
      await tester.pumpAndSettle();

      expect( bloc.isPolling, isFalse );

      final before = fetches( adapter );
      await tester.pump( const Duration( seconds: 121 ) );
      await settle( tester );
      expect( fetches( adapter ), before, reason: 'not one request after the route left' );
    } );

    testWidgets( "a poll does not blank the pane the operator is reading", ( tester ) async {
      serve( [ _row( 'a', 'sam' ), _row( 'b', 'sam' ) ] );
      await pumpPane( tester );
      await expandGroup( tester, 'Sam' );

      await tester.pump( const Duration( seconds: 61 ) );
      await settle( tester );

      expect( find.byType( TaskRow ), findsNWidgets( 2 ) );
      expect( find.text( 'Sam · 2' ), findsOneWidget );
    } );
  } );

  group( "against the captured fixture", () {
    testWidgets( "the live page renders its two blocks at 360 dp without overflowing",
        ( tester ) async {
      adapter.handlers[ 'GET ${HoldingAreaRepository.path}' ] =
          ( _ ) => jsonBody( _fixture( 'holding_area.json' ) );
      await pumpPane( tester );

      expect( find.byType( FilerGroupHeader ), findsNWidgets( 2 ) );
      expect( tester.takeException(), isNull );
    } );

    testWidgets( "🔴 the WIDE capture groups eight sessions into six personas",
        ( tester ) async {
      // Real captured data: eight distinct `created_by` values, six people. Maria and
      // Mr Radio are the two who filed from more than one seat.
      adapter.handlers[ 'GET ${HoldingAreaRepository.path}' ] =
          ( _ ) => jsonBody( _fixture( 'holding_area_multi_session.json' ) );
      await pumpPane( tester );

      // ⚠️ THE GROUP COUNT IS READ OFF THE STATE, NOT OFF THE TREE, AND THAT IS NOT A
      // DODGE. `ListView` builds lazily, so at 360×800 only the headers near the
      // viewport exist as widgets — `findsNWidgets( 6 )` would be asserting the size of
      // Flutter's build window, which is a fact about the scroll cache and not about
      // this pane. What IS a fact about the pane is asserted below it: the personas are
      // named on screen, folded, in order.
      expect( bloc.state.groups.map( ( g ) => g.filer ).toList(),
          [ 'Krishna', 'Maria', 'Maya', 'Mr Radio', 'Rachel', 'Sam' ] );
      expect( find.byType( TaskRow ), findsNothing, reason: 'all six arrive folded' );
      expect( find.text( 'Maria · 2' ), findsOneWidget );
      expect( find.text( 'Mr Radio · 7' ), findsOneWidget,
          reason: 'one row from 75c92041 and six from 8fa24215, under one name' );
      expect( tester.takeException(), isNull );
    } );

    testWidgets( "🔴 folding measurably shortens the scroll to the persona you want",
        ( tester ) async {
      // ⚠️ RICK'S COMPLAINT, MEASURED RATHER THAN ASSERTED, AND MEASURED IN HIS OWN
      // TERMS: *"it's just an enormous amount of text to scroll through to get to the
      // one persona you're interested in."* So the quantity is the SCROLL OFFSET needed
      // to reach the last persona, and the experiment is the same target twice with one
      // variable changed.
      //
      // ⚠️ THE OFFSET IS EXACT, UNLIKE `maxScrollExtent`. A lazily built `ListView`
      // ESTIMATES its extent from the children it has built so far, so an assertion
      // about the extent is partly an assertion about Flutter's build window. Where the
      // viewport actually came to rest is not an estimate.
      adapter.handlers[ 'GET ${HoldingAreaRepository.path}' ] =
          ( _ ) => jsonBody( _fixture( 'holding_area_multi_session.json' ) );
      await pumpPane( tester );

      // ⚠️ THE PANE'S OWN SCROLLABLE, NAMED EXPLICITLY. An unfolded group puts a
      // `TextField` on screen and a `TextField` carries its own `Scrollable`, so the
      // bare `find.byType( Scrollable )` that works while everything is folded throws
      // "Too many elements" the moment the test opens a group — which is precisely the
      // half of this experiment that matters.
      final paneScroller = find.descendant(
        of       : find.byKey( const Key( TestKeys.holdingView ) ),
        matching : find.byType( Scrollable ),
      );

      Future<double> scrollToLastPersona() async {
        await tester.scrollUntilVisible(
          find.text( 'Sam · 1' ), 120, scrollable: paneScroller.first );
        await tester.pumpAndSettle();
        return tester.state<ScrollableState>( paneScroller.first ).position.pixels;
      }

      final folded = await scrollToLastPersona();

      // Open the biggest group — Mr Radio's seven rows, which is the case folding is
      // for — and go back for the same persona.
      await tester.scrollUntilVisible(
        find.text( 'Mr Radio · 7' ), -120, scrollable: paneScroller.first );
      await tester.pumpAndSettle();
      await expandGroup( tester, 'Mr Radio' );

      final withOneOpen = await scrollToLastPersona();

      expect( withOneOpen, greaterThan( folded ),
          reason: 'ONE open persona already costs the operator more scrolling; folding '
                  'every other one is what keeps the list short' );
      expect( find.byType( TaskRow ), findsWidgets );
    } );
  } );
}
