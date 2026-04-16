/// Process-wide access-token holder.
///
/// AuthBloc sets this after login/refresh; the HTTP interceptor and
/// WebSocket services read it to construct `Authorization: Bearer <token>`.
/// Kept as a top-level mutable function to avoid a circular dependency
/// between the auth feature and the transport services.
library;

typedef AccessTokenReader = String? Function();

String? _currentAccessToken;

/// Default reader — can be replaced by tests.
AccessTokenReader readAccessToken = () => _currentAccessToken;

void setAccessToken( String? token ) {
  _currentAccessToken = token;
}

void clearAccessToken() {
  _currentAccessToken = null;
}
