/// Plan §3.4, C row — "Preferences: default review first; the setter persists".
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lupin_mobile/services/quick_ask/quick_ask_preferences.dart';

void main() {
  group( 'QuickAskPreferences', () {
    setUp( () {
      SharedPreferences.setMockInitialValues( {} );
    } );

    Future<QuickAskPreferences> newPrefs() async =>
        QuickAskPreferences( await SharedPreferences.getInstance() );

    test( 'defaults to REVIEW FIRST on a fresh install', () async {
      final p = await newPrefs();
      expect( p.sendImmediately, isFalse );
    } );

    test( 'the setter persists across instances, both directions', () async {
      final p1 = await newPrefs();
      await p1.setSendImmediately( true );
      expect( ( await newPrefs() ).sendImmediately, isTrue );

      await p1.setSendImmediately( false );
      expect( ( await newPrefs() ).sendImmediately, isFalse );
    } );

    test( 'a value already on the device is read back, not overridden by the default', () async {
      SharedPreferences.setMockInitialValues( { 'quick_ask.send_immediately': true } );
      expect( ( await newPrefs() ).sendImmediately, isTrue );
    } );

    // 🔴 SC3 — the key is a one-way door. Renaming it after it ships silently
    // resets every user's choice, and nothing else in the suite can see that,
    // so the spelling itself is pinned here as a literal.
    test( 'the stored key is exactly quick_ask.send_immediately', () async {
      expect( QuickAskPreferences.keySendImmediately, 'quick_ask.send_immediately' );

      final p = await newPrefs();
      await p.setSendImmediately( true );
      final sp = await SharedPreferences.getInstance();
      expect( sp.getKeys(), { 'quick_ask.send_immediately' } );
    } );
  } );
}
