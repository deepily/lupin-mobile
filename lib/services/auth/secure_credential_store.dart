import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Wrapper over flutter_secure_storage that namespaces keys by server context (dev or test).
///
/// One store instance serves the app lifetime. Callers pass `contextId` explicitly, so switching
/// contexts does not need a new store.
///
/// Stored items, each per context: `refresh_token`, `last_email`, and `session_id`, which is also per user
/// and used to resume the WebSocket session.
class SecureCredentialStore {
  final FlutterSecureStorage _storage;

  /// Creates a store on [storage], or on encrypted shared preferences by default.
  SecureCredentialStore( [ FlutterSecureStorage? storage ] )
      : _storage = storage ?? const FlutterSecureStorage(
          aOptions: AndroidOptions( encryptedSharedPreferences: true ),
        );

  String _k( String contextId, String key ) => "auth.$contextId.$key";
  String _sessionKey( String contextId, String email ) =>
      "auth.$contextId.session.${email.toLowerCase()}";

  // --- refresh token ---------------------------------------------------

  /// Stores the refresh token for [contextId].
  Future<void> writeRefreshToken( String contextId, String token ) =>
      _storage.write( key: _k( contextId, "refresh_token" ), value: token );

  /// Reads the refresh token for [contextId], or null.
  Future<String?> readRefreshToken( String contextId ) =>
      _storage.read( key: _k( contextId, "refresh_token" ) );

  /// Deletes the refresh token for [contextId].
  Future<void> deleteRefreshToken( String contextId ) =>
      _storage.delete( key: _k( contextId, "refresh_token" ) );

  // --- last-used email -------------------------------------------------

  /// Stores the last-used email for [contextId].
  Future<void> writeLastEmail( String contextId, String email ) =>
      _storage.write( key: _k( contextId, "last_email" ), value: email );

  /// Reads the last-used email for [contextId], or null.
  Future<String?> readLastEmail( String contextId ) =>
      _storage.read( key: _k( contextId, "last_email" ) );

  // --- WS session id ("wise penguin") ---------------------------------

  /// Stores the WebSocket session id for [contextId] and [email].
  Future<void> writeSessionId( String contextId, String email, String sessionId ) =>
      _storage.write( key: _sessionKey( contextId, email ), value: sessionId );

  /// Reads the WebSocket session id for [contextId] and [email], or null.
  Future<String?> readSessionId( String contextId, String email ) =>
      _storage.read( key: _sessionKey( contextId, email ) );

  /// Deletes the WebSocket session id for [contextId] and [email].
  Future<void> deleteSessionId( String contextId, String email ) =>
      _storage.delete( key: _sessionKey( contextId, email ) );

  /// Wipes the refresh token and session ids of one context, and keeps the last email.
  ///
  /// The kept email pre-fills the next login.
  Future<void> clearContextSession( String contextId ) async {
    await deleteRefreshToken( contextId );
    final all = await _storage.readAll();
    final prefix = "auth.$contextId.session.";
    // Snapshot the keys: a platform may hand back its live map, and deleting
    // while iterating it throws (flutter_secure_storage's test platform does).
    for ( final key in all.keys.toList() ) {
      if ( key.startsWith( prefix ) ) await _storage.delete( key: key );
    }
  }
}
