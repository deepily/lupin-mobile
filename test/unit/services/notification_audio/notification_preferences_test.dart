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
  } );
}
