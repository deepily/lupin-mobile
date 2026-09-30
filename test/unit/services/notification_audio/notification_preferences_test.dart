import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lupin_mobile/services/notification_audio/notification_preferences.dart';

void main() {
  group( "NotificationPreferences", () {
    setUp( () {
      SharedPreferences.setMockInitialValues( {} );
    } );

    Future<NotificationPreferences> newPrefs() async {
      final sp = await SharedPreferences.getInstance();
      return NotificationPreferences( sp );
    }

    test( "defaults match web client parity (ding+speak on high+urgent, medium dings, master off)", () async {
      final p = await newPrefs();
      expect( p.dingOnMedium,  true  );
      expect( p.dingOnHigh,    true  );
      expect( p.dingOnUrgent,  true  );
      expect( p.speakOnHigh,   true  );
      expect( p.speakOnUrgent, true  );
      expect( p.masterMute,    false );
    } );

    test( "writes persist across instances", () async {
      final p1 = await newPrefs();
      await p1.setDingOnMedium( false );
      await p1.setSpeakOnHigh( false );
      await p1.setMasterMute( true );

      final p2 = await newPrefs();
      expect( p2.dingOnMedium,  false );
      expect( p2.speakOnHigh,   false );
      expect( p2.masterMute,    true  );
      // Untouched values keep their defaults.
      expect( p2.dingOnHigh,    true  );
      expect( p2.dingOnUrgent,  true  );
      expect( p2.speakOnUrgent, true  );
    } );

    test( "toggle-off-then-on restores true", () async {
      final p = await newPrefs();
      await p.setDingOnUrgent( false );
      expect( p.dingOnUrgent, false );
      await p.setDingOnUrgent( true );
      expect( p.dingOnUrgent, true );
    } );

    test( 'speakSystemSenders defaults to true and persists', () async {
      SharedPreferences.setMockInitialValues( {} );
      final p = NotificationPreferences( await SharedPreferences.getInstance() );
      expect( p.speakSystemSenders, isTrue );
      await p.setSpeakSystemSenders( false );
      expect( p.speakSystemSenders, isFalse );
      final again = NotificationPreferences( await SharedPreferences.getInstance() );
      expect( again.speakSystemSenders, isFalse );
    } );

    test( 'ttsFraction defaults to 0.2, snaps to 10% steps, clamps, and persists', () async {
      SharedPreferences.setMockInitialValues( {} );
      final p = NotificationPreferences( await SharedPreferences.getInstance() );
      expect( p.ttsFraction, NotificationPreferences.defaultTtsFraction );
      await p.setTtsFraction( 0.57 );
      expect( p.ttsFraction, 0.6 );
      await p.setTtsFraction( 1.7 );
      expect( p.ttsFraction, 1.0 );
      await p.setTtsFraction( -3 );
      expect( p.ttsFraction, 0.0 );
      expect( NotificationPreferences.snapTtsFraction( 0.25 ), 0.3 );
    } );
  } );

  test( 'wakeNotifications defaults ON, and round-trips through storage (row 1af7b3de)', () async {
    SharedPreferences.setMockInitialValues( {} );
    final prefs = NotificationPreferences( await SharedPreferences.getInstance() );
    expect( prefs.wakeNotifications, isTrue,
        reason: "opt-OUT: an install that has never seen the switch behaves as before" );

    await prefs.setWakeNotifications( false );
    expect( prefs.wakeNotifications, isFalse );

    // The background isolate builds its OWN NotificationPreferences from its own
    // SharedPreferences handle, so the value has to survive the instance.
    final fresh = NotificationPreferences( await SharedPreferences.getInstance() );
    expect( fresh.wakeNotifications, isFalse );
  } );

  group( "notification management view (row 7cac3a17)", () {
    Future<NotificationPreferences> prefsWith( Map<String, Object> seed ) async {
      SharedPreferences.setMockInitialValues( seed );
      return NotificationPreferences( await SharedPreferences.getInstance() );
    }

    test( "defaults: master on, both surfaces on", () async {
      final p = await prefsWith( {} );
      expect( p.enabled,           true );
      expect( p.backgroundEnabled, true );
      expect( p.foregroundEnabled, true );
    } );

    test( "default priorities reproduce today's behaviour, which is NOT symmetric", () async {
      final p = await prefsWith( {} );
      for ( final priority in NotificationPreferences.priorities ) {
        expect( p.priorityEnabled( "background", priority ), true,
                reason: "the wake path shows every item it fetches today" );
      }
      expect( p.priorityEnabled( "foreground", "low" ), false,
              reason: "low is already silent in the foreground today" );
      for ( final priority in [ "medium", "high", "urgent" ] ) {
        expect( p.priorityEnabled( "foreground", priority ), true );
      }
    } );

    test( "every switch round-trips across instances", () async {
      final p1 = await prefsWith( {} );
      await p1.setEnabled( false );
      await p1.setBackgroundEnabled( false );
      await p1.setForegroundEnabled( false );
      await p1.setPriorityEnabled( "background", "urgent", false );
      await p1.setPriorityEnabled( "foreground", "low",    true  );

      final p2 = NotificationPreferences( await SharedPreferences.getInstance() );
      expect( p2.enabled,           false );
      expect( p2.backgroundEnabled, false );
      expect( p2.foregroundEnabled, false );
      expect( p2.priorityEnabled( "background", "urgent" ), false );
      expect( p2.priorityEnabled( "foreground", "low"    ), true  );
    } );

    test( "the two surfaces' checkboxes are independent keys", () async {
      final p = await prefsWith( {} );
      await p.setPriorityEnabled( "background", "high", false );
      expect( p.priorityEnabled( "background", "high" ), false );
      expect( p.priorityEnabled( "foreground", "high" ), true,
              reason: "same priority, different surface, different checkbox" );
    } );

    group( "migration from the single wake switch (row 1af7b3de)", () {
      test( "a user who turned wake notifications OFF does not find them back ON", () async {
        final p = await prefsWith( {
          NotificationPreferences.keyWakeNotifications: false,
        } );
        expect( p.backgroundEnabled, false,
                reason: "the old switch answers until the new one is written" );
      } );

      test( "a user who left the old switch ON keeps them on", () async {
        final p = await prefsWith( {
          NotificationPreferences.keyWakeNotifications: true,
        } );
        expect( p.backgroundEnabled, true );
      } );

      test( "the NEW key wins once it is written, whatever the old one says", () async {
        final p = await prefsWith( {
          NotificationPreferences.keyWakeNotifications : false,
          NotificationPreferences.keyBackgroundEnabled : true,
        } );
        expect( p.backgroundEnabled, true );
      } );

      test( "writing the new key does NOT delete the old one", () async {
        final p = await prefsWith( {
          NotificationPreferences.keyWakeNotifications: false,
        } );
        await p.setBackgroundEnabled( true );
        // A rollback to Pocholo's branch has to still find the user's choice
        // where he left it; deleting the key would silently turn wake
        // notifications back on for them.
        expect( p.wakeNotifications, false );
      } );

      test( "neither key present ⇒ on, which is what a fresh install has always done", () async {
        final p = await prefsWith( {} );
        expect( p.backgroundEnabled, true );
      } );
    } );
  } );
}
