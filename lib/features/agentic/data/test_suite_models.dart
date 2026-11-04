/// Models for POST /api/test-suite/submit.
library;

// ─────────────────────────────────────────────
// Request
// ─────────────────────────────────────────────

/// Request to run a test suite.
class TestSuiteRequest {
  /// Comma-separated test types, `integration,e2e` by default.
  final String               testTypes;
  /// Space-separated pytest flags; null for none.
  final String?              pytestArgs;
  /// True asks the server to plan the job without running it.
  final bool                 dryRun;
  /// Socket id the server pushes progress to; null for none.
  final String?              websocketId;
  /// Time to start the job, as an ISO timestamp; null starts it now.
  final String?              scheduledAt;
  /// True starts a fix job when tests fail; null uses the server default.
  final bool?                autoFixOnFailure;
  /// Environment variables for the run.
  ///
  /// The server keeps only names with the TFE_, BFE_ or LUPIN_TEST_ prefix.
  final Map<String, String>? envVars;

  /// Creates a request from its parts.
  const TestSuiteRequest( {
    this.testTypes       = 'integration,e2e',
    this.pytestArgs,
    this.dryRun          = false,
    this.websocketId,
    this.scheduledAt,
    this.autoFixOnFailure,
    this.envVars,
  } );

  /// Spoken-command text that routes a `/api/v2/submit` call to this job.
  ///
  /// The server still filters `env_vars` by prefix.
  static const submitCommand = 'agent router go to test suite';
  /// Builds the `args` map of the `/api/v2/submit` body, without queue directives.
  Map<String, dynamic> toSubmitArgs() => {
    'test_types'                                      : testTypes,
    if ( pytestArgs != null         ) 'pytest_args'        : pytestArgs,
    if ( dryRun                     ) 'dry_run'            : dryRun,
    if ( autoFixOnFailure != null   ) 'auto_fix_on_failure': autoFixOnFailure,
    if ( envVars != null && envVars!.isNotEmpty ) 'env_vars' : envVars,
  };

  /// Builds the JSON body of this job's own submit endpoint.
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
