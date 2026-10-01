import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Durable device identity and resume cursor for the `/ws/queue` socket.
///
/// Holds `device_id`, a random per-install id generated once. The server keys its one-socket-per-device slot on it.
/// Also holds `last_seq`, the highest frame `seq` this install has processed.
/// It uses [SharedPreferencesAsync], never the `SharedPreferences` singleton. The FCM background isolate and
/// the UI isolate each cache their own singleton copy, so a value one writes is invisible to the other.
/// Design: src/rnd/2026.09.28-background-wake-socket-problem-statement-response.md
class WsResumeStore {
  /// Storage key of the device id.
  ///
  /// Never rename either storage key spelling: renaming silently resets every install.
  static const keyDeviceId = 'ws.device_id';
  /// Storage key of the resume cursor.
  static const keyLastSeq  = 'ws.last_seq';

  final SharedPreferencesAsync _prefs;
  final Random                 _random;

  /// Creates the store; [prefs] and [random] exist for tests.
  WsResumeStore( { SharedPreferencesAsync? prefs, Random? random } )
      : _prefs  = prefs ?? SharedPreferencesAsync(),
        _random = random ?? Random.secure();

  /// Returns the install's device id, generating and persisting a v4 UUID on first use.
  ///
  /// Ensures:
  ///   - every later call, in any isolate or after a restart, returns the same id
  Future<String> deviceId() async {
    final existing = await _prefs.getString( keyDeviceId );
    if ( existing != null && existing.isNotEmpty ) return existing;
    final fresh = _newUuidV4();
    await _prefs.setString( keyDeviceId, fresh );
    return fresh;
  }

  /// Returns the stored cursor, or 0 for a fresh client with nothing to resume.
  Future<int> lastSeq() async => await _prefs.getInt( keyLastSeq ) ?? 0;

  /// Stores [seq] as the cursor; [seq] must be non-negative.
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
