/// Stable widget keys for UI tests (widget + integration + future Patrol/Maestro).
///
/// Production code attaches these via `Key( TestKeys.xxx )`; test code
/// looks them up via `find.byKey( Key( TestKeys.xxx ) )`. A single source
/// of truth prevents selector drift as UI copy/structure evolves and
/// survives i18n (unlike `find.text`).
class TestKeys {
  TestKeys._();

  // Login
  static const loginEmailField    = 'login.email';
  static const loginPasswordField = 'login.password';
  static const loginSubmitButton  = 'login.submit';

  // Inbox — suffixed with senderId at use-site, e.g. '${inboxSenderTilePrefix}s-1'
  static const inboxSenderTilePrefix = 'inbox.sender.';

  // Deep research form
  static const drQueryField     = 'dr.query';
  static const drDryRunCheckbox = 'dr.dryRun';
  static const drSubmitButton   = 'dr.submit';
}
