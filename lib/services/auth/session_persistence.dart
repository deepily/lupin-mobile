import 'secure_credential_store.dart';

/// Persists and resumes the WebSocket "wise penguin" session ID per
/// (server-context, user-email). Thin delegator over SecureCredentialStore
/// that hides the keying scheme from WS services.
class SessionPersistence {
  final SecureCredentialStore _store;

  SessionPersistence( this._store );

  Future<void> save( {
    required String contextId,
    required String email,
    required String sessionId,
  } ) => _store.writeSessionId( contextId, email, sessionId );

  Future<String?> load( {
    required String contextId,
    required String email,
  } ) => _store.readSessionId( contextId, email );

  Future<void> clear( {
    required String contextId,
    required String email,
  } ) => _store.deleteSessionId( contextId, email );
}
