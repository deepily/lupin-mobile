import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lupin_mobile/services/notification_filter/notification_stop_list.dart';

void main() {
  group( 'NotificationStopList', () {
    Future<NotificationStopList> make( [ Map<String, Object> seed = const {} ] ) async {
      SharedPreferences.setMockInitialValues( seed );
      return NotificationStopList( await SharedPreferences.getInstance() );
    }

    test( 'first run seeds the Claude Code tool-chatter prefixes, all enabled', () async {
      final sl = await make();
      expect( sl.patterns.map( ( p ) => p.pattern ), NotificationStopList.defaultPatterns );
      expect( sl.patterns.every( ( p ) => p.enabled ), isTrue );
      expect( sl.active.length, NotificationStopList.defaultPatterns.length );
    } );

    test( 'matches: case-insensitive PREFIX on the trimmed message; null/blank never match; disabled patterns ignored', () async {
      final sl = await make();
      expect( sl.matches( 'Done: mcp__cosa-voice__notify' ), isTrue );
      expect( sl.matches( '  done: BASH ls -la' ), isTrue, reason: 'trim + case-insensitive' );
      expect( sl.matches( 'Done: ToolSearch select:foo' ), isTrue );
      expect( sl.matches( 'Starting: Bash' ), isFalse, reason: 'prefix, not substring' );
      expect( sl.matches( 'Wave 1 done: Bash' ), isFalse );
      expect( sl.matches( null ), isFalse );
      expect( sl.matches( '   ' ), isFalse );
      expect( sl.matches( 'The build finished' ), isFalse );

      await sl.setEnabled( 1, false );   // Done: Bash off
      expect( sl.matches( 'Done: Bash ls' ), isFalse );
      expect( sl.matches( 'Done: mcp x' ), isTrue );
    } );

    test( 'persists as JSON under the prefs key and reloads on a fresh instance', () async {
      final sl = await make();
      await sl.setEnabled( 0, false );
      expect( await sl.add( 'Done: WebFetch' ), isTrue );
      final sp  = await SharedPreferences.getInstance();
      final raw = sp.getString( NotificationStopList.prefsKey )!;
      final decoded = ( jsonDecode( raw ) as List ).cast<Map<String, dynamic>>();
      expect( decoded.first, const { 'pattern': 'Done: mcp', 'enabled': false } );
      expect( decoded.last,  const { 'pattern': 'Done: WebFetch', 'enabled': true } );

      final again = NotificationStopList( sp );          // same store, new object
      expect( again.patterns.first.enabled, isFalse );
      expect( again.patterns.last.pattern, 'Done: WebFetch' );
      expect( again.matches( 'Done: mcp x' ), isFalse );
      expect( again.matches( 'done: webfetch https://…' ), isTrue );
    } );

    test( 'corrupt or non-list stored JSON falls back to the seeds (never throws)', () async {
      final a = await make( { NotificationStopList.prefsKey: '{not json' } );
      expect( a.patterns.map( ( p ) => p.pattern ), NotificationStopList.defaultPatterns );
      final b = await make( { NotificationStopList.prefsKey: '{"a":1}' } );
      expect( b.patterns.length, NotificationStopList.defaultPatterns.length );
      final c = await make( { NotificationStopList.prefsKey: '[{"pattern":"  "},{"pattern":"Keep me","enabled":false}, 42]' } );
      expect( c.patterns, [ const StopPattern( pattern: 'Keep me', enabled: false ) ],
          reason: 'blank patterns + non-map entries dropped' );
    } );

    test( 'add ignores blank and case-insensitive duplicates; removeAt / setEnabled ignore bad indexes; reset restores seeds', () async {
      final sl = await make();
      expect( await sl.add( '   ' ), isFalse );
      expect( await sl.add( 'done: bash' ), isFalse, reason: 'duplicate of the seeded Done: Bash' );
      expect( await sl.add( 'Done: Agent' ), isTrue );
      expect( sl.patterns.last.pattern, 'Done: Agent' );

      final n = sl.patterns.length;
      await sl.removeAt( 99 );
      await sl.setEnabled( -1, false );
      expect( sl.patterns.length, n );

      await sl.removeAt( 0 );
      expect( sl.patterns.first.pattern, 'Done: Bash' );

      await sl.resetToDefaults();
      expect( sl.patterns.map( ( p ) => p.pattern ), NotificationStopList.defaultPatterns );
      expect( sl.patterns.every( ( p ) => p.enabled ), isTrue );
    } );

    test( 'every mutation notifies listeners exactly once; patterns view is unmodifiable', () async {
      final sl = await make();
      var n = 0;
      sl.addListener( () => n++ );
      await sl.setEnabled( 0, false );
      await sl.add( 'X' );
      await sl.removeAt( 0 );
      await sl.resetToDefaults();
      expect( n, 4 );
      await sl.add( '' );        // rejected ⇒ no notify
      expect( n, 4 );
      expect( () => sl.patterns.add( const StopPattern( pattern: 'nope' ) ), throwsUnsupportedError );
    } );

    test( 'StopPattern value semantics + json round trip', () {
      const p = StopPattern( pattern: 'Done: X' );
      expect( p, const StopPattern( pattern: 'Done: X', enabled: true ) );
      expect( p.hashCode, const StopPattern( pattern: 'Done: X' ).hashCode );
      expect( p.copyWith( enabled: false ).enabled, isFalse );
      expect( StopPattern.fromJson( p.toJson() ), p );
      expect( StopPattern.fromJson( const { 'pattern': 'Y' } ).enabled, isTrue );
      expect( StopPattern.fromJson( const { 'pattern': 'Y', 'enabled': false } ).enabled, isFalse );
      expect( p.toString(), contains( 'Done: X' ) );
    } );

    test( 'collapseGroups defaults ON, persists, and notifies', () async {
      final sl = await make();
      expect( sl.collapseGroups, isTrue );
      var n = 0; sl.addListener( () => n++ );
      await sl.setCollapseGroups( false );
      expect( sl.collapseGroups, isFalse );
      expect( n, 1 );
      final again = NotificationStopList( await SharedPreferences.getInstance() );
      expect( again.collapseGroups, isFalse );
    } );
  } );
}
