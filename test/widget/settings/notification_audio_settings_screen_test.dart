import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lupin_mobile/core/testing/test_keys.dart';
import 'package:lupin_mobile/features/settings/presentation/notification_audio_settings_screen.dart';
import 'package:lupin_mobile/services/notification_audio/notification_preferences.dart';

void main() {
  group( "NotificationAudioSettingsScreen", () {
    late NotificationPreferences prefs;

    setUp( () async {
      SharedPreferences.setMockInitialValues( {} );
      final sp = await SharedPreferences.getInstance();
      prefs = NotificationPreferences( sp );
    } );

    Widget underTest() {
      return MaterialApp(
        home: NotificationAudioSettingsScreen( prefs: prefs ),
      );
    }

    testWidgets( "renders all six toggles with default values", ( tester ) async {
      await tester.pumpWidget( underTest() );
      await tester.pump();

      for ( final key in [
        TestKeys.settingsMasterMute,
        TestKeys.settingsDingMedium,
        TestKeys.settingsDingHigh,
        TestKeys.settingsDingUrgent,
        TestKeys.settingsSpeakHigh,
        TestKeys.settingsSpeakUrgent,
      ] ) {
        expect( find.byKey( Key( key ) ), findsOneWidget, reason: "missing $key" );
      }

      SwitchListTile tile( String key ) =>
          tester.widget<SwitchListTile>( find.byKey( Key( key ) ) );

      // Defaults: master mute off, all dings on, both speech on.
      expect( tile( TestKeys.settingsMasterMute  ).value, false );
      expect( tile( TestKeys.settingsDingMedium  ).value, true  );
      expect( tile( TestKeys.settingsDingHigh    ).value, true  );
      expect( tile( TestKeys.settingsDingUrgent  ).value, true  );
      expect( tile( TestKeys.settingsSpeakHigh   ).value, true  );
      expect( tile( TestKeys.settingsSpeakUrgent ).value, true  );
    } );

    testWidgets( "speak-system-senders switch: default ON; toggling persists OFF (Rick 2026-08-21)", ( tester ) async {
      await tester.pumpWidget( underTest() );
      await tester.pump();
      final key = find.byKey( const Key( TestKeys.settingsSpeakSystem ) );
      await tester.dragUntilVisible( key, find.byType( ListView ), const Offset( 0, -200 ) );
      await tester.pump();
      expect( tester.widget<SwitchListTile>( key ).value, isTrue );
      await tester.tap( key );
      await tester.pump();
      expect( tester.widget<SwitchListTile>( key ).value, isFalse );
      expect( prefs.speakSystemSenders, isFalse );
    } );

    testWidgets( "toggling master mute flips the switch immediately", ( tester ) async {
      await tester.pumpWidget( underTest() );
      await tester.pump();

      await tester.tap( find.byKey( const Key( TestKeys.settingsMasterMute ) ) );
      await tester.pump();

      SwitchListTile tile( String key ) =>
          tester.widget<SwitchListTile>( find.byKey( Key( key ) ) );
      expect( tile( TestKeys.settingsMasterMute ).value, true );
    } );

    testWidgets( "toggling speak-on-urgent flips the switch immediately (scrolled into view)", ( tester ) async {
      await tester.pumpWidget( underTest() );
      await tester.pump();

      // The switch sits below the fold in the default 800x600 test viewport;
      // scroll it into view before tapping.
      final switchFinder = find.byKey( const Key( TestKeys.settingsSpeakUrgent ) );
      await tester.ensureVisible( switchFinder );
      await tester.pump();
      await tester.tap( switchFinder );
      await tester.pump();

      SwitchListTile tile( String key ) =>
          tester.widget<SwitchListTile>( find.byKey( Key( key ) ) );
      expect( tile( TestKeys.settingsSpeakUrgent ).value, false );
    } );
  } );
}
