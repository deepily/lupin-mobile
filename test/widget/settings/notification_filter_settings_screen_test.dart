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

    testWidgets( 'renders every seeded pattern as a checked row', ( tester ) async {
      await pumpTall( tester );
      for ( final p in NotificationStopList.defaultPatterns ) {
        expect( toggle( p ), findsOneWidget, reason: 'missing $p' );
        expect( tester.widget<CheckboxListTile>( toggle( p ) ).value, isTrue );
      }
      expect( find.text( 'hidden + muted' ), findsNWidgets( NotificationStopList.defaultPatterns.length ) );
    } );

    testWidgets( 'unchecking a row persists enabled=false and flips the subtitle', ( tester ) async {
      await pumpTall( tester );
      await tester.tap( toggle( 'Done: Bash' ) );
      await tester.pump();
      expect( tester.widget<CheckboxListTile>( toggle( 'Done: Bash' ) ).value, isFalse );
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
