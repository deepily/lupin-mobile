import 'secure_credential_store.dart';

/// Saves and loads the WebSocket session id per server context and user email.
///
/// A thin delegator over SecureCredentialStore that hides the keying scheme from the WebSocket services.
class SessionPersistence {
  final SecureCredentialStore _store;

  /// Creates a persistence layer on [_store].
  SessionPersistence( this._store );

  /// Saves [sessionId] for [contextId] and [email].
  Future<void> save( {
    required String contextId,
    required String email,
    required String sessionId,
  } ) => _store.writeSessionId( contextId, email, sessionId );

  /// Loads the session id for [contextId] and [email], or null.
  Future<String?> load( {
    required String contextId,
    required String email,
  } ) => _store.readSessionId( contextId, email );

  /// Clears the session id for [contextId] and [email].
  Future<void> clear( {
    required String contextId,
    required String email,
  } ) => _store.deleteSessionId( contextId, email );
}
