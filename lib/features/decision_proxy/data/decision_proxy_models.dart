/// Data models for the Lupin decision-proxy and trust API.
///
/// Field names match the server's JSON exactly.
library;

DateTime? _parseDt( dynamic v ) =>
    v == null ? null : DateTime.tryParse( v.toString() );

T? _as<T>( dynamic v ) => v is T ? v : null;

/// Trust modes the backend recognizes.
enum TrustMode {
  /// The proxy is off.
  disabled,

  /// The proxy records what it would decide and acts on nothing.
  shadow,

  /// The proxy proposes a decision and waits for the user.
  suggest,

  /// The proxy decides on its own.
  active,

  /// A mode string this client does not recognize.
  unknown
}

/// Parses a mode string; null or an unrecognized string gives [TrustMode.unknown].
TrustMode trustModeFromString( String? s ) {
  switch ( s ) {
    case "disabled": return TrustMode.disabled;
    case "shadow":   return TrustMode.shadow;
    case "suggest":  return TrustMode.suggest;
    case "active":   return TrustMode.active;
    default:         return TrustMode.unknown;
  }
}

/// Returns the wire string for [m]; [TrustMode.unknown] maps to `"unknown"`.
String trustModeToString( TrustMode m ) {
  switch ( m ) {
    case TrustMode.disabled: return "disabled";
    case TrustMode.shadow:   return "shadow";
    case TrustMode.suggest:  return "suggest";
    case TrustMode.active:   return "active";
    case TrustMode.unknown:  return "unknown";
  }
}

/// A single pending or historical proxy decision.
///
/// It is the item type of the pending list and the by-category list.
class ProxyDecision {
  /// Server id of the decision.
  final String   id;

  /// Notification the decision answers, when there is one.
  final String?  notificationId;

  /// Decision domain, for example the area of work it belongs to.
  final String   domain;

  /// Category within the domain.
  final String   category;

  /// The question the proxy was asked.
  final String   question;

  /// Session that asked the question, when known.
  final String?  senderId;

  /// What the proxy did: shadow, suggest, act or defer.
  final String   action;

  /// The proxy's answer, in whatever shape the question took.
  final dynamic  decisionValue;

  /// Proxy confidence, from 0.0 to 1.0.
  final double   confidence;

  /// Trust level the decision was made at, from 1 to 4.
  final int      trustLevel;

  /// The proxy's stated reason for the decision.
  final String   reason;

  /// Ratification state: pending, approved, rejected or not_required.
  final String   ratificationState;

  /// Where the row came from: organic, synthetic_seed or synthetic_generated.
  final String   dataOrigin;

  /// Free-form metadata the server attached, when any.
  final Map<String, dynamic>? metadataJson;

  /// When the decision was created.
  final DateTime? createdAt;

  /// The unparsed JSON the decision was built from.
  final Map<String, dynamic> raw;

  /// Creates a decision from already-parsed fields.
  const ProxyDecision( {
    required this.id,
    this.notificationId,
    required this.domain,
    required this.category,
    required this.question,
    this.senderId,
    required this.action,
    this.decisionValue,
    required this.confidence,
    required this.trustLevel,
    required this.reason,
    required this.ratificationState,
    required this.dataOrigin,
    this.metadataJson,
    this.createdAt,
    this.raw = const {},
  } );

  /// Builds a decision from server JSON, defaulting missing fields to empty or neutral values.
  factory ProxyDecision.fromJson( Map<String, dynamic> json ) {
    return ProxyDecision(
      id                : json["id"].toString(),
      notificationId    : _as<String>( json["notification_id"] ),
      domain            : ( json["domain"] ?? "" ).toString(),
      category          : ( json["category"] ?? "" ).toString(),
      question          : ( json["question"] ?? "" ).toString(),
      senderId          : _as<String>( json["sender_id"] ),
      action            : ( json["action"] ?? "" ).toString(),
      decisionValue     : json["decision_value"],
      confidence        : ( json["confidence"] as num? )?.toDouble() ?? 0.0,
      trustLevel        : ( json["trust_level"] as num? )?.toInt() ?? 1,
      reason            : ( json["reason"] ?? "" ).toString(),
      ratificationState : ( json["ratification_state"] ?? "pending" ).toString(),
      dataOrigin        : ( json["data_origin"] ?? "organic" ).toString(),
      metadataJson      : _as<Map<String, dynamic>>( json["metadata_json"] ),
      createdAt         : _parseDt( json["created_at"] ),
      raw               : Map<String, dynamic>.from( json ),
    );
  }
}

/// The summary block of the pending-decisions response.
class PendingSummary {
  /// How many decisions await ratification.
  final int                 totalPending;

  /// Pending counts keyed by category.
  final Map<String, int>    byCategory;

  /// Pending counts keyed by trust level.
  final Map<String, int>    byTrustLevel;

  /// Creation time of the oldest pending decision, when any are pending.
  final DateTime?           oldestPending;

  /// Creates a summary from already-parsed fields.
  const PendingSummary( {
    required this.totalPending,
    required this.byCategory,
    required this.byTrustLevel,
    this.oldestPending,
  } );

  /// Builds a summary from server JSON; a missing count map becomes empty.
  factory PendingSummary.fromJson( Map<String, dynamic> json ) {
    Map<String, int> intMap( dynamic m ) {
      if ( m is! Map ) return const {};
      return m.map( ( k, v ) => MapEntry(
        k.toString(),
        ( v is num ) ? v.toInt() : 0,
      ) );
    }
    return PendingSummary(
      totalPending  : ( json["total_pending"] as num? )?.toInt() ?? 0,
      byCategory    : intMap( json["by_category"] ),
      byTrustLevel  : intMap( json["by_trust_level"] ),
      oldestPending : _parseDt( json["oldest_pending"] ),
    );
  }
}

/// The envelope of the pending-decisions response.
class PendingDecisionsResponse {
  /// Server status string.
  final String              status;

  /// The pending decisions.
  final List<ProxyDecision> decisions;

  /// Counts over the pending decisions.
  final PendingSummary      summary;

  /// Creates a response from already-parsed fields.
  const PendingDecisionsResponse( {
    required this.status,
    required this.decisions,
    required this.summary,
  } );

  /// Builds a response from server JSON, skipping list entries that are not maps.
  factory PendingDecisionsResponse.fromJson( Map<String, dynamic> json ) {
    final raw = ( json["decisions"] as List? ) ?? const [];
    return PendingDecisionsResponse(
      status    : ( json["status"] ?? "" ).toString(),
      decisions : raw
          .whereType<Map>()
          .map( ( m ) => ProxyDecision.fromJson( Map<String, dynamic>.from( m ) ) )
          .toList(),
      summary   : PendingSummary.fromJson(
        Map<String, dynamic>.from( ( json["summary"] as Map? ) ?? {} ),
      ),
    );
  }
}

/// The response to ratifying a decision.
class RatifyResponse {
  /// Server status string.
  final String   status;

  /// Id of the decision that was ratified.
  final String   decisionId;

  /// Resulting state: approved or rejected.
  final String   ratificationState;

  /// Who ratified the decision.
  final String   ratifiedBy;

  /// When the decision was ratified.
  final DateTime? ratifiedAt;

  /// Free-text feedback the user attached, when any.
  final String?  feedback;

  /// Domain of the decision, when the server echoes it.
  final String?  domain;

  /// Category of the decision, when the server echoes it.
  final String?  category;

  /// Creates a response from already-parsed fields.
  const RatifyResponse( {
    required this.status,
    required this.decisionId,
    required this.ratificationState,
    required this.ratifiedBy,
    this.ratifiedAt,
    this.feedback,
    this.domain,
    this.category,
  } );

  /// Builds a response from server JSON, defaulting missing strings to empty.
  factory RatifyResponse.fromJson( Map<String, dynamic> json ) {
    return RatifyResponse(
      status            : ( json["status"] ?? "" ).toString(),
      decisionId        : ( json["decision_id"] ?? "" ).toString(),
      ratificationState : ( json["ratification_state"] ?? "" ).toString(),
      ratifiedBy        : ( json["ratified_by"] ?? "" ).toString(),
      ratifiedAt        : _parseDt( json["ratified_at"] ),
      feedback          : _as<String>( json["feedback"] ),
      domain            : _as<String>( json["domain"] ),
      category          : _as<String>( json["category"] ),
    );
  }
}

/// The response to deleting a decision.
class DeleteDecisionResponse {
  /// Server status string.
  final String status;

  /// Id of the decision that was deleted.
  final String decisionId;

  /// Who deleted the decision.
  final String deletedBy;

  /// Creates a response from already-parsed fields.
  const DeleteDecisionResponse( {
    required this.status,
    required this.decisionId,
    required this.deletedBy,
  } );

  /// Builds a response from server JSON, defaulting missing strings to empty.
  factory DeleteDecisionResponse.fromJson( Map<String, dynamic> json ) {
    return DeleteDecisionResponse(
      status     : ( json["status"] ?? "" ).toString(),
      decisionId : ( json["decision_id"] ?? "" ).toString(),
      deletedBy  : ( json["deleted_by"] ?? "" ).toString(),
    );
  }
}

/// One per-domain entry of a user's trust state.
class TrustStateItem {
  /// Server id of the trust row.
  final String   id;

  /// Decision domain the row covers.
  final String   domain;

  /// Category within the domain.
  final String   category;

  /// Current trust level.
  final int      trustLevel;

  /// How many decisions the proxy has made here.
  final int      totalDecisions;

  /// How many of them the user approved.
  final int      successfulDecisions;

  /// How many of them the user rejected.
  final int      rejectedDecisions;

  /// Circuit-breaker state, open or closed, when the server reports one.
  final String?  circuitBreakerState;

  /// When the row was created.
  final DateTime? createdAt;

  /// When the row last changed.
  final DateTime? updatedAt;

  /// Creates an item from already-parsed fields.
  const TrustStateItem( {
    required this.id,
    required this.domain,
    required this.category,
    required this.trustLevel,
    required this.totalDecisions,
    required this.successfulDecisions,
    required this.rejectedDecisions,
    this.circuitBreakerState,
    this.createdAt,
    this.updatedAt,
  } );

  /// Builds an item from server JSON, defaulting missing numbers to a neutral value.
  factory TrustStateItem.fromJson( Map<String, dynamic> json ) {
    return TrustStateItem(
      id                  : json["id"].toString(),
      domain              : ( json["domain"] ?? "" ).toString(),
      category            : ( json["category"] ?? "" ).toString(),
      trustLevel          : ( json["trust_level"] as num? )?.toInt() ?? 1,
      totalDecisions      : ( json["total_decisions"] as num? )?.toInt() ?? 0,
      successfulDecisions : ( json["successful_decisions"] as num? )?.toInt() ?? 0,
      rejectedDecisions   : ( json["rejected_decisions"] as num? )?.toInt() ?? 0,
      circuitBreakerState : _as<String>( json["circuit_breaker_state"] ),
      createdAt           : _parseDt( json["created_at"] ),
      updatedAt           : _parseDt( json["updated_at"] ),
    );
  }
}

/// The envelope of the per-user trust-state response.
class TrustStateResponse {
  /// Server status string.
  final String               status;

  /// Email of the user the states belong to.
  final String               userEmail;

  /// One entry per domain and category.
  final List<TrustStateItem> trustStates;

  /// Creates a response from already-parsed fields.
  const TrustStateResponse( {
    required this.status,
    required this.userEmail,
    required this.trustStates,
  } );

  /// Builds a response from server JSON, skipping list entries that are not maps.
  factory TrustStateResponse.fromJson( Map<String, dynamic> json ) {
    final raw = ( json["trust_states"] as List? ) ?? const [];
    return TrustStateResponse(
      status      : ( json["status"] ?? "" ).toString(),
      userEmail   : ( json["user_email"] ?? "" ).toString(),
      trustStates : raw
          .whereType<Map>()
          .map( ( m ) => TrustStateItem.fromJson( Map<String, dynamic>.from( m ) ) )
          .toList(),
    );
  }
}

/// The envelope of the decisions-by-category response.
class DecisionsByCategoryResponse {
  /// Server status string.
  final String              status;

  /// Domain that was queried.
  final String              domain;

  /// Category that was queried.
  final String              category;

  /// The decisions in that domain and category.
  final List<ProxyDecision> decisions;

  /// Creates a response from already-parsed fields.
  const DecisionsByCategoryResponse( {
    required this.status,
    required this.domain,
    required this.category,
    required this.decisions,
  } );

  /// Builds a response from server JSON, skipping list entries that are not maps.
  factory DecisionsByCategoryResponse.fromJson( Map<String, dynamic> json ) {
    final raw = ( json["decisions"] as List? ) ?? const [];
    return DecisionsByCategoryResponse(
      status    : ( json["status"] ?? "" ).toString(),
      domain    : ( json["domain"] ?? "" ).toString(),
      category  : ( json["category"] ?? "" ).toString(),
      decisions : raw
          .whereType<Map>()
          .map( ( m ) => ProxyDecision.fromJson( Map<String, dynamic>.from( m ) ) )
          .toList(),
    );
  }
}

/// The response that names the current batch of unacknowledged decisions.
class BatchIdResponse {
  /// Server status string.
  final String status;

  /// Id of the current batch.
  final String batchId;

  /// Creates a response from already-parsed fields.
  const BatchIdResponse( { required this.status, required this.batchId } );

  /// Builds a response from server JSON, defaulting missing strings to empty.
  factory BatchIdResponse.fromJson( Map<String, dynamic> json ) {
    return BatchIdResponse(
      status  : ( json["status"] ?? "" ).toString(),
      batchId : ( json["batch_id"] ?? "" ).toString(),
    );
  }
}

/// The response to acknowledging the current batch.
///
/// The request has no body. The backend rotates the batch as a side effect.
class AcknowledgeResponse {
  /// Server status string.
  final String status;

  /// Id of the batch that was retired.
  final String retiredBatch;

  /// Id of the batch that replaced it.
  final String newBatch;

  /// Creates a response from already-parsed fields.
  const AcknowledgeResponse( {
    required this.status,
    required this.retiredBatch,
    required this.newBatch,
  } );

  /// Builds a response from server JSON, defaulting missing strings to empty.
  factory AcknowledgeResponse.fromJson( Map<String, dynamic> json ) {
    return AcknowledgeResponse(
      status       : ( json["status"] ?? "" ).toString(),
      retiredBatch : ( json["retired_batch"] ?? "" ).toString(),
      newBatch     : ( json["new_batch"] ?? "" ).toString(),
    );
  }
}

/// The response that reports the proxy's trust mode.
class TrustModeStatus {
  /// Server status string.
  final String     status;

  /// Mode set in the server's configuration file.
  final TrustMode  iniMode;

  /// Mode of the running job, null when no job is running.
  final TrustMode? runningMode;

  /// The mode actually in force.
  final TrustMode  effective;

  /// Whether a job is running now.
  final bool       hasRunningJob;

  /// Creates a status from already-parsed fields.
  const TrustModeStatus( {
    required this.status,
    required this.iniMode,
    this.runningMode,
    required this.effective,
    required this.hasRunningJob,
  } );

  /// Builds a status from server JSON; unrecognized modes become [TrustMode.unknown].
  factory TrustModeStatus.fromJson( Map<String, dynamic> json ) {
    return TrustModeStatus(
      status        : ( json["status"] ?? "" ).toString(),
      iniMode       : trustModeFromString( _as<String>( json["ini_mode"] ) ),
      runningMode   : json["running_mode"] == null
          ? null
          : trustModeFromString( _as<String>( json["running_mode"] ) ),
      effective     : trustModeFromString( _as<String>( json["effective"] ) ),
      hasRunningJob : json["has_running_job"] == true,
    );
  }
}

/// The request body that changes the proxy's trust mode.
class TrustModeUpdateRequest {
  /// The mode to switch to.
  final TrustMode mode;

  /// Domain the change applies to.
  final String    domain;

  /// Creates a request; [domain] defaults to `"swe"`.
  const TrustModeUpdateRequest( {
    required this.mode,
    this.domain = "swe",
  } );

  /// Returns the JSON body to send.
  Map<String, dynamic> toJson() => {
    "mode"   : trustModeToString( mode ),
    "domain" : domain,
  };
}

/// The response to a mode change, in either the running or the queued shape.
class TrustModeUpdateResponse {
  /// Either `"updated"` or `"queued"`.
  final String   status;

  /// Mode before the change.
  final TrustMode oldMode;

  /// Mode after the change.
  final TrustMode newMode;

  /// Either `"running"` or `"next_job"`.
  final String   target;

  /// Id of the running job; present only when [status] is `"updated"`.
  final String?  jobId;

  /// Explanation from the server; present only when [status] is `"queued"`.
  final String?  message;

  /// Creates a response from already-parsed fields.
  const TrustModeUpdateResponse( {
    required this.status,
    required this.oldMode,
    required this.newMode,
    required this.target,
    this.jobId,
    this.message,
  } );

  /// Builds a response from server JSON; unrecognized modes become [TrustMode.unknown].
  factory TrustModeUpdateResponse.fromJson( Map<String, dynamic> json ) {
    return TrustModeUpdateResponse(
      status  : ( json["status"] ?? "" ).toString(),
      oldMode : trustModeFromString( _as<String>( json["old_mode"] ) ),
      newMode : trustModeFromString( _as<String>( json["new_mode"] ) ),
      target  : ( json["target"] ?? "" ).toString(),
      jobId   : _as<String>( json["job_id"] ),
      message : _as<String>( json["message"] ),
    );
  }
}
