/// Process-wide access-token holder.
///
/// AuthBloc sets the token after login or refresh. The HTTP interceptor and the WebSocket services read it
/// to build `Authorization: Bearer <token>`. It is a top-level mutable function to avoid a circular
/// dependency between the auth feature and the transport services.
library;

/// Reads the current access token, or null when signed out.
typedef AccessTokenReader = String? Function();

String? _currentAccessToken;

/// Default reader of the current token; tests may replace it.
AccessTokenReader readAccessToken = () => _currentAccessToken;

/// Stores [token] as the current access token; null clears it.
void setAccessToken( String? token ) {
  _currentAccessToken = token;
}

/// Clears the current access token.
void clearAccessToken() {
  _currentAccessToken = null;
}
