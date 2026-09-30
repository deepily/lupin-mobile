import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Durable identity and resume cursor for the `/ws/queue` socket (row 281a10d6,
/// server half dc446601).
///
/// Holds two values:
///   - `device_id` : a random per-install id, generated once. The server keys
///                   its one-socket-per-device slot on it.
///   - `last_seq`  : the highest frame `seq` this install has processed.
///
/// 🔴 BACKED BY [SharedPreferencesAsync], NEVER THE `SharedPreferences`
/// SINGLETON. The FCM background isolate and the UI isolate each cache their
/// own copy of the singleton, so a value one isolate writes is invisible to the
/// other's cached reads. The async API reads the platform store every time.
/// (src/rnd/2026.09.28-background-wake-socket-problem-statement-response.md)
class WsResumeStore {
  /// One-way doors: renaming either spelling silently resets every install.
  static const keyDeviceId = 'ws.device_id';
  static const keyLastSeq  = 'ws.last_seq';

  final SharedPreferencesAsync _prefs;
  final Random                 _random;

  /// Requires: nothing. [prefs] and [random] exist for tests.
  WsResumeStore( { SharedPreferencesAsync? prefs, Random? random } )
      : _prefs  = prefs ?? SharedPreferencesAsync(),
        _random = random ?? Random.secure();

  /// Ensures:
  ///   - returns the persisted id, or generates a v4 UUID, persists and returns it
  ///   - every later call, in any isolate or after a restart, returns the same id
  Future<String> deviceId() async {
    final existing = await _prefs.getString( keyDeviceId );
    if ( existing != null && existing.isNotEmpty ) return existing;
    final fresh = _newUuidV4();
    await _prefs.setString( keyDeviceId, fresh );
    return fresh;
  }

  /// Ensures: returns the stored cursor, or 0 (a fresh client, nothing to resume).
  Future<int> lastSeq() async => await _prefs.getInt( keyLastSeq ) ?? 0;

  /// Requires: seq >= 0
  Future<void> setLastSeq( int seq ) => _prefs.setInt( keyLastSeq, seq );

  String _newUuidV4() {
    final bytes = List<int>.generate( 16, ( _ ) => _random.nextInt( 256 ) );
    bytes[ 6 ] = ( bytes[ 6 ] & 0x0f ) | 0x40;   // version 4
    bytes[ 8 ] = ( bytes[ 8 ] & 0x3f ) | 0x80;   // RFC 4122 variant
    final hex = bytes.map( ( b ) => b.toRadixString( 16 ).padLeft( 2, '0' ) ).join();
    return '${hex.substring( 0, 8 )}-${hex.substring( 8, 12 )}-${hex.substring( 12, 16 )}-'
           '${hex.substring( 16, 20 )}-${hex.substring( 20 )}';
  }
}
