/// Models for POST /api/test-suite/submit.
library;

// ─────────────────────────────────────────────
// Request
// ─────────────────────────────────────────────

class TestSuiteRequest {
  final String               testTypes;     // comma-separated, default "integration,e2e"
  final String?              pytestArgs;    // space-separated pytest flags
  final bool                 dryRun;
  final String?              websocketId;
  final String?              scheduledAt;
  final bool?                autoFixOnFailure;
  final Map<String, String>? envVars;       // filtered to TFE_/BFE_/LUPIN_TEST_ prefixes

  const TestSuiteRequest( {
    this.testTypes       = 'integration,e2e',
    this.pytestArgs,
    this.dryRun          = false,
    this.websocketId,
    this.scheduledAt,
    this.autoFixOnFailure,
    this.envVars,
  } );

  /// v2 wave 2 — `/api/v2/submit` args (1:1 with the factory; `env_vars` is
  /// still prefix-filtered server-side).
  static const submitCommand = 'agent router go to test suite';
  Map<String, dynamic> toSubmitArgs() => {
    'test_types'                                      : testTypes,
    if ( pytestArgs != null         ) 'pytest_args'        : pytestArgs,
    if ( dryRun                     ) 'dry_run'            : dryRun,
    if ( autoFixOnFailure != null   ) 'auto_fix_on_failure': autoFixOnFailure,
    if ( envVars != null && envVars!.isNotEmpty ) 'env_vars' : envVars,
  };

  Map<String, dynamic> toJson() => {
    'test_types'                                      : testTypes,
    if ( pytestArgs != null         ) 'pytest_args'        : pytestArgs,
    if ( dryRun                     ) 'dry_run'            : dryRun,
    if ( websocketId != null        ) 'websocket_id'       : websocketId,
    if ( scheduledAt != null        ) 'scheduled_at'       : scheduledAt,
    if ( autoFixOnFailure != null   ) 'auto_fix_on_failure': autoFixOnFailure,
    if ( envVars != null && envVars!.isNotEmpty ) 'env_vars' : envVars,
  };
}
