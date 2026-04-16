import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Thin wrapper over flutter_secure_storage that namespaces keys by
/// server context (dev / test). One store instance per app lifetime —
/// callers pass `contextId` explicitly so switching contexts does not
/// require re-instantiating the store.
///
/// Stored items:
///   - refresh_token  (per-context)
///   - last_email     (per-context)
///   - session_id     (per-context, per-user — used for WS "wise penguin" resume)
class SecureCredentialStore {
  final FlutterSecureStorage _storage;

  SecureCredentialStore( [ FlutterSecureStorage? storage ] )
      : _storage = storage ?? const FlutterSecureStorage(
          aOptions: AndroidOptions( encryptedSharedPreferences: true ),
        );

  String _k( String contextId, String key ) => "auth.$contextId.$key";
  String _sessionKey( String contextId, String email ) =>
      "auth.$contextId.session.${email.toLowerCase()}";

  // --- refresh token ---------------------------------------------------

  Future<void> writeRefreshToken( String contextId, String token ) =>
      _storage.write( key: _k( contextId, "refresh_token" ), value: token );

  Future<String?> readRefreshToken( String contextId ) =>
      _storage.read( key: _k( contextId, "refresh_token" ) );

  Future<void> deleteRefreshToken( String contextId ) =>
      _storage.delete( key: _k( contextId, "refresh_token" ) );

  // --- last-used email -------------------------------------------------

  Future<void> writeLastEmail( String contextId, String email ) =>
      _storage.write( key: _k( contextId, "last_email" ), value: email );

  Future<String?> readLastEmail( String contextId ) =>
      _storage.read( key: _k( contextId, "last_email" ) );

  // --- WS session id ("wise penguin") ---------------------------------

  Future<void> writeSessionId( String contextId, String email, String sessionId ) =>
      _storage.write( key: _sessionKey( contextId, email ), value: sessionId );

  Future<String?> readSessionId( String contextId, String email ) =>
      _storage.read( key: _sessionKey( contextId, email ) );

  Future<void> deleteSessionId( String contextId, String email ) =>
      _storage.delete( key: _sessionKey( contextId, email ) );

  /// Wipe only the refresh-token / session-id entries for a context
  /// (keeps last-email for next login pre-fill).
  Future<void> clearContextSession( String contextId ) async {
    await deleteRefreshToken( contextId );
    final all = await _storage.readAll();
    final prefix = "auth.$contextId.session.";
    for ( final key in all.keys ) {
      if ( key.startsWith( prefix ) ) await _storage.delete( key: key );
    }
  }
}
