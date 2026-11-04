/// Models for POST /api/deep-research/submit and GET /api/deep-research/report.
library;

T? _as<T>( dynamic v ) => v is T ? v : null;

// ─────────────────────────────────────────────
// Request
// ─────────────────────────────────────────────

/// Request to run a deep research job on a query.
class DeepResearchRequest {
  /// Research question to investigate.
  final String  query;
  /// Spending cap in dollars; null uses the server default.
  final double? budget;
  /// Socket id the server pushes progress to; null for none.
  final String? websocketId;
  /// Model the lead agent uses; null uses the server default.
  final String? leadModel;
  /// True asks the server to plan the job without running it.
  final bool    dryRun;
  /// Reader level: beginner, general, expert or academic; null uses the server default.
  final String? audience;
  /// Free-text detail about the audience; null for none.
  final String? audienceContext;
  /// Time to start the job, as an ISO timestamp; null starts it now.
  final String? scheduledAt;
  /// True asks the queue to run this job with nothing else running.
  final bool    monopolize;

  /// Creates a request from its parts.
  const DeepResearchRequest( {
    required this.query,
    this.budget,
    this.websocketId,
    this.leadModel,
    this.dryRun       = false,
    this.audience,
    this.audienceContext,
    this.scheduledAt,
    this.monopolize   = false,
  } );

  /// Spoken-command text that routes a `/api/v2/submit` call to this job.
  ///
  /// The queue directives `scheduledAt` and `monopolize` travel at the top level of
  /// `SubmitRequest`, never inside `args`. The server does not read `lead_model` here.
  static const submitCommand = 'agent router go to deep research';
  /// Builds the `args` map of the `/api/v2/submit` body, without queue directives.
  Map<String, dynamic> toSubmitArgs() => {
    'query'                            : query,
    if ( budget != null          ) 'budget'           : budget,
    if ( leadModel != null       ) 'lead_model'       : leadModel,
    if ( dryRun                  ) 'dry_run'          : dryRun,
    if ( audience != null        ) 'audience'         : audience,
    if ( audienceContext != null ) 'audience_context' : audienceContext,
  };

  /// Builds the JSON body of this job's own submit endpoint.
  Map<String, dynamic> toJson() => {
    'query'                            : query,
    if ( budget != null          ) 'budget'           : budget,
    if ( websocketId != null     ) 'websocket_id'     : websocketId,
    if ( leadModel != null       ) 'lead_model'       : leadModel,
    if ( dryRun                  ) 'dry_run'          : dryRun,
    if ( audience != null        ) 'audience'         : audience,
    if ( audienceContext != null ) 'audience_context' : audienceContext,
    if ( scheduledAt != null     ) 'scheduled_at'     : scheduledAt,
    if ( monopolize              ) 'monopolize'       : monopolize,
  };
}

// ─────────────────────────────────────────────
// Report response
// ─────────────────────────────────────────────

/// Fetched markdown report from GET /api/deep-research/report?job_id=...
class DeepResearchReport {
  /// Id of the job that wrote the report.
  final String  jobId;
  /// Full report text in markdown.
  final String  markdownText;
  /// Report title; null when the server gave none.
  final String? title;
  /// Creation time as the server wrote it; null when absent.
  final String? createdAt;

  /// Creates a report from its parts.
  const DeepResearchReport( {
    required this.jobId,
    required this.markdownText,
    this.title,
    this.createdAt,
  } );

  /// Builds a report from the report endpoint's JSON body.
  factory DeepResearchReport.fromJson( Map<String, dynamic> j ) =>
      DeepResearchReport(
        jobId        : ( j[ 'job_id' ] as String? ) ?? '',
        markdownText : ( j[ 'report' ] as String? ) ?? ( j[ 'content' ] as String? ) ?? '',
        title        : _as<String>( j[ 'title' ] ),
        createdAt    : _as<String>( j[ 'created_at' ] ),
      );
}
