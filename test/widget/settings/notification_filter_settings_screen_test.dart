import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/settings/presentation/notification_filter_settings_screen.dart';
import 'package:lupin_mobile/services/notification_filter/notification_stop_list.dart';

void main() {
  group( 'NotificationFilterSettingsScreen', () {
    late NotificationStopList stopList;

    setUp( () async {
      SharedPreferences.setMockInitialValues( {} );
      stopList = NotificationStopList( await SharedPreferences.getInstance() );
    } );

    Widget underTest() => MaterialApp( home: NotificationFilterSettingsScreen( stopList: stopList ) );

    /// Tall viewport so all seeded rows (ListView.builder) are laid out.
    Future<void> pumpTall( WidgetTester tester ) async {
      tester.view.physicalSize     = const Size( 1080, 2400 );
      tester.view.devicePixelRatio = 1.0;
      addTearDown( tester.view.resetPhysicalSize );
      addTearDown( tester.view.resetDevicePixelRatio );
      await tester.pumpWidget( underTest() );
      await tester.pump();
    }

    Finder toggle( String p ) => find.byKey( Key( '${TestKeys.settingsStopListTogglePrefix}$p' ) );

    // ⚠️ BODY CHANGED BY ROW f27a61f4, NAME KEPT (ruling R2 + Clayton): the row is
    // a `ListTile` with its own leading `Checkbox` now, because tapping the tile
    // body is the EDIT gesture. `toggle(p)` still keys the box itself.
    testWidgets( 'renders every seeded pattern as a checked row', ( tester ) async {
      await pumpTall( tester );
      for ( final p in NotificationStopList.defaultPatterns ) {
        expect( toggle( p ), findsOneWidget, reason: 'missing $p' );
        expect( tester.widget<Checkbox>( toggle( p ) ).value, isTrue );
      }
      expect( find.text( 'hidden + muted' ), findsNWidgets( NotificationStopList.defaultPatterns.length ) );
    } );

    // ⚠️ BODY CHANGED BY ROW f27a61f4, NAME KEPT: this tapped the tile CENTRE,
    // which is now the edit gesture. It taps the box, which is the only thing
    // that toggles. The claim is the same claim.
    testWidgets( 'unchecking a row persists enabled=false and flips the subtitle', ( tester ) async {
      await pumpTall( tester );
      await tester.tap( toggle( 'Done: Bash' ) );
      await tester.pump();
      expect( tester.widget<Checkbox>( toggle( 'Done: Bash' ) ).value, isFalse );
      expect( find.text( 'shown + spoken' ), findsOneWidget );
      expect( stopList.matches( 'Done: Bash x' ), isFalse );
      final again = NotificationStopList( await SharedPreferences.getInstance() );
      expect( again.patterns.firstWhere( ( p ) => p.pattern == 'Done: Bash' ).enabled, isFalse );
    } );

    testWidgets( 'adding a pattern via the field appends a checked row; blank/duplicate shows a snackbar', ( tester ) async {
      await pumpTall( tester );
      await tester.enterText( find.byKey( const Key( TestKeys.settingsStopListAddField ) ), 'Done: WebFetch' );
      await tester.tap( find.byKey( const Key( TestKeys.settingsStopListAddButton ) ) );
      await tester.pump();
      expect( toggle( 'Done: WebFetch' ), findsOneWidget );
      expect( stopList.matches( 'done: webfetch http' ), isTrue );
      expect( tester.widget<TextField>( find.byKey( const Key( TestKeys.settingsStopListAddField ) ) ).controller!.text, isEmpty );

      await tester.enterText( find.byKey( const Key( TestKeys.settingsStopListAddField ) ), 'done: webfetch' );
      await tester.tap( find.byKey( const Key( TestKeys.settingsStopListAddButton ) ) );
      await tester.pump();
      expect( find.text( 'Empty or duplicate pattern' ), findsOneWidget );
    } );

    testWidgets( 'swipe-to-dismiss removes the pattern', ( tester ) async {
      await pumpTall( tester );
      await tester.drag( find.byKey( const Key( '${TestKeys.settingsStopListRowPrefix}Done: Read' ) ), const Offset( -600, 0 ) );
      await tester.pumpAndSettle();
      expect( toggle( 'Done: Read' ), findsNothing );
      expect( stopList.patterns.any( ( p ) => p.pattern == 'Done: Read' ), isFalse );
    } );

    // ===== ROW f27a61f4 — a visible delete with undo, and tap-to-edit ==========

    Finder del( String p ) => find.byKey( Key( '${TestKeys.settingsStopListDeletePrefix}$p' ) );

    testWidgets( 'row f27a61f4 — the trash button deletes the row', ( tester ) async {
      await pumpTall( tester );
      expect( del( 'Done: Read' ), findsOneWidget, reason: 'the affordance is VISIBLE, unlike the swipe' );
      await tester.tap( del( 'Done: Read' ) );
      await tester.pump();
      expect( toggle( 'Done: Read' ), findsNothing );
      expect( stopList.patterns.any( ( p ) => p.pattern == 'Done: Read' ), isFalse );
      expect( find.text( 'Deleted "Done: Read"' ), findsOneWidget );
    } );

    testWidgets( 'row f27a61f4 — Undo puts the row back at its OWN index with its OWN checked state', ( tester ) async {
      await pumpTall( tester );
      // Uncheck it first: an undo that restored an enabled copy would pass a
      // weaker test and lose the user's state.
      await tester.tap( toggle( 'Done: ToolSearch' ) );
      await tester.pump();
      final index = stopList.patterns.indexWhere( ( p ) => p.pattern == 'Done: ToolSearch' );
      expect( index, 2 );

      await tester.tap( del( 'Done: ToolSearch' ) );
      // Two pumps, NOT pumpAndSettle: the snackbar has to finish sliding in
      // before its action is hit-testable, and settling would wait out its
      // auto-dismiss and take the Undo button away with it.
      await tester.pump();
      await tester.pump( const Duration( milliseconds: 750 ) );
      await tester.tap( find.text( 'Undo' ) );
      await tester.pumpAndSettle();

      expect( stopList.patterns[ index ].pattern, 'Done: ToolSearch', reason: 'same position' );
      expect( stopList.patterns[ index ].enabled, isFalse, reason: 'same checked state' );
      expect( stopList.patterns.map( ( p ) => p.pattern ), NotificationStopList.defaultPatterns );
      expect( tester.widget<Checkbox>( toggle( 'Done: ToolSearch' ) ).value, isFalse );
    } );

    testWidgets( 'row f27a61f4 — tapping the text edits in place, keeping checked state and position', ( tester ) async {
      await pumpTall( tester );
      await tester.tap( toggle( 'Done: Grep' ) );          // uncheck, so the edit must preserve it
      await tester.pump();
      final index = stopList.patterns.indexWhere( ( p ) => p.pattern == 'Done: Grep' );

      await tester.tap( find.text( 'Done: Grep' ) );       // the TEXT, not the box
      await tester.pumpAndSettle();
      expect( find.byKey( const Key( TestKeys.settingsStopListEditField ) ), findsOneWidget );
      await tester.enterText( find.byKey( const Key( TestKeys.settingsStopListEditField ) ), 'Done: Grepp' );
      await tester.tap( find.byKey( const Key( TestKeys.settingsStopListEditSave ) ) );
      await tester.pumpAndSettle();

      expect( stopList.patterns[ index ].pattern, 'Done: Grepp' );
      expect( stopList.patterns[ index ].enabled, isFalse );
      expect( stopList.patterns.length, NotificationStopList.defaultPatterns.length );
      expect( toggle( 'Done: Grepp' ), findsOneWidget );
      expect( toggle( 'Done: Grep' ), findsNothing );
      // The misspelling Rick actually hit: it is fixable without losing the row.
      expect( stopList.matches( 'done: grepp lib' ), isFalse, reason: 'unchecked ⇒ inactive' );
      final again = NotificationStopList( await SharedPreferences.getInstance() );
      expect( again.patterns[ index ].pattern, 'Done: Grepp' );
    } );

    testWidgets( 'row f27a61f4 — a BLANK edit is refused and the row is untouched', ( tester ) async {
      await pumpTall( tester );
      final before = stopList.patterns.toList();
      await tester.tap( find.text( 'Done: Edit' ) );
      await tester.pumpAndSettle();
      await tester.enterText( find.byKey( const Key( TestKeys.settingsStopListEditField ) ), '   ' );
      await tester.tap( find.byKey( const Key( TestKeys.settingsStopListEditSave ) ) );
      await tester.pumpAndSettle();
      expect( find.text( 'Empty or duplicate pattern' ), findsOneWidget );
      // Asserted at the STORE, not only on screen: `_load` silently DROPS blank
      // patterns, so a blank that reached the store would look fine now and
      // vanish on the next launch.
      expect( stopList.patterns, before );
      final again = NotificationStopList( await SharedPreferences.getInstance() );
      expect( again.patterns.map( ( p ) => p.pattern ), before.map( ( p ) => p.pattern ) );
    } );

    testWidgets( 'row f27a61f4 — an edit that collides with another row is refused, list unchanged (R4)', ( tester ) async {
      await pumpTall( tester );
      final before = stopList.patterns.toList();
      await tester.tap( find.text( 'Done: Read' ) );
      await tester.pumpAndSettle();
      await tester.enterText( find.byKey( const Key( TestKeys.settingsStopListEditField ) ), 'done: bash' );
      await tester.tap( find.byKey( const Key( TestKeys.settingsStopListEditSave ) ) );
      await tester.pumpAndSettle();
      expect( find.text( 'Empty or duplicate pattern' ), findsOneWidget );
      expect( stopList.patterns, before, reason: 'refused, so nothing moved' );
      // ⚠️ The claim is "a colliding edit is refused and the list is unchanged",
      // NOT "duplicates cannot exist": `_load` still reads a pair saved by an
      // older build off the phone.
      expect( stopList.patterns.where( ( p ) => p.pattern == 'Done: Bash' ).length, 1 );
    } );

    testWidgets( 'row f27a61f4 — the keyboard\'s done key saves the edit too', ( tester ) async {
      await pumpTall( tester );
      await tester.tap( find.text( 'Done: Glob' ) );
      await tester.pumpAndSettle();
      await tester.enterText( find.byKey( const Key( TestKeys.settingsStopListEditField ) ), 'Done: Globb' );
      // The other way out of a one-field dialog, and the one a phone keyboard
      // offers first — it must not be a dead end.
      await tester.testTextInput.receiveAction( TextInputAction.done );
      await tester.pumpAndSettle();
      expect( stopList.patterns.last.pattern, 'Done: Globb' );
      expect( toggle( 'Done: Globb' ), findsOneWidget );
    } );

    testWidgets( 'row f27a61f4 — Cancel leaves the pattern alone', ( tester ) async {
      await pumpTall( tester );
      final before = stopList.patterns.toList();
      await tester.tap( find.text( 'Done: Write' ) );
      await tester.pumpAndSettle();
      await tester.enterText( find.byKey( const Key( TestKeys.settingsStopListEditField ) ), 'Done: Wrote' );
      await tester.tap( find.byKey( const Key( TestKeys.settingsStopListEditCancel ) ) );
      await tester.pumpAndSettle();
      expect( stopList.patterns, before );
      expect( find.text( 'Done: Write' ), findsOneWidget );
    } );

    testWidgets( 'overflow → Reset to defaults restores the seeds', ( tester ) async {
      await stopList.removeAt( 0 );
      await stopList.setEnabled( 0, false );
      await pumpTall( tester );
      await tester.tap( find.byKey( const Key( TestKeys.settingsStopListMenu ) ) );
      await tester.pumpAndSettle();
      await tester.tap( find.byKey( const Key( TestKeys.settingsStopListReset ) ) );
      await tester.pumpAndSettle();
      expect( stopList.patterns.map( ( p ) => p.pattern ), NotificationStopList.defaultPatterns );
      expect( stopList.patterns.every( ( p ) => p.enabled ), isTrue );
      expect( toggle( 'Done: mcp' ), findsOneWidget );
    } );

    testWidgets( 'empty list shows the everything-is-shown hint', ( tester ) async {
      for ( var i = stopList.patterns.length - 1; i >= 0; i-- ) {
        await stopList.removeAt( i );
      }
      await pumpTall( tester );
      expect( find.text( 'No patterns — everything is shown and spoken.' ), findsOneWidget );
    } );

    testWidgets( 'collapse toggle reflects + persists the pref', ( tester ) async {
      await pumpTall( tester );
      final sw = find.byKey( const Key( TestKeys.settingsCollapseGroups ) );
      expect( tester.widget<SwitchListTile>( sw ).value, isTrue );
      await tester.tap( sw );
      await tester.pump();
      expect( tester.widget<SwitchListTile>( sw ).value, isFalse );
      expect( stopList.collapseGroups, isFalse );
    } );
  } );
}
