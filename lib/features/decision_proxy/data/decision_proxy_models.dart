/// Data models for the Lupin decision-proxy / trust API (9 endpoints).
///
/// Field names match `cosa/rest/routers/decision_proxy.py` JSON exactly.
library;

DateTime? _parseDt( dynamic v ) =>
    v == null ? null : DateTime.tryParse( v.toString() );

T? _as<T>( dynamic v ) => v is T ? v : null;

/// Trust modes the backend recognizes.
enum TrustMode { disabled, shadow, suggest, active, unknown }

TrustMode trustModeFromString( String? s ) {
  switch ( s ) {
    case "disabled": return TrustMode.disabled;
    case "shadow":   return TrustMode.shadow;
    case "suggest":  return TrustMode.suggest;
    case "active":   return TrustMode.active;
    default:         return TrustMode.unknown;
  }
}

String trustModeToString( TrustMode m ) {
  switch ( m ) {
    case TrustMode.disabled: return "disabled";
    case TrustMode.shadow:   return "shadow";
    case TrustMode.suggest:  return "suggest";
    case TrustMode.active:   return "active";
    case TrustMode.unknown:  return "unknown";
  }
}

/// Single pending or historical decision (used by /pending, /decisions/...).
class ProxyDecision {
  final String   id;
  final String?  notificationId;
  final String   domain;
  final String   category;
  final String   question;
  final String?  senderId;
  final String   action;            // shadow | suggest | act | defer
  final dynamic  decisionValue;
  final double   confidence;        // 0.0 - 1.0
  final int      trustLevel;        // 1-4
  final String   reason;
  final String   ratificationState; // pending | approved | rejected | not_required
  final String   dataOrigin;        // organic | synthetic_seed | synthetic_generated
  final Map<String, dynamic>? metadataJson;
  final DateTime? createdAt;
  final Map<String, dynamic> raw;

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

/// `GET /api/proxy/pending/...` summary block.
class PendingSummary {
  final int                 totalPending;
  final Map<String, int>    byCategory;
  final Map<String, int>    byTrustLevel;
  final DateTime?           oldestPending;

  const PendingSummary( {
    required this.totalPending,
    required this.byCategory,
    required this.byTrustLevel,
    this.oldestPending,
  } );

  factory PendingSummary.fromJson( Map<String, dynamic> json ) {
    Map<String, int> _intMap( dynamic m ) {
      if ( m is! Map ) return const {};
      return m.map( ( k, v ) => MapEntry(
        k.toString(),
        ( v is num ) ? v.toInt() : 0,
      ) );
    }
    return PendingSummary(
      totalPending  : ( json["total_pending"] as num? )?.toInt() ?? 0,
      byCategory    : _intMap( json["by_category"] ),
      byTrustLevel  : _intMap( json["by_trust_level"] ),
      oldestPending : _parseDt( json["oldest_pending"] ),
    );
  }
}

/// `GET /api/proxy/pending/...` envelope.
class PendingDecisionsResponse {
  final String              status;
  final List<ProxyDecision> decisions;
  final PendingSummary      summary;

  const PendingDecisionsResponse( {
    required this.status,
    required this.decisions,
    required this.summary,
  } );

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

/// `POST /api/proxy/ratify/{decision_id}` response.
class RatifyResponse {
  final String   status;
  final String   decisionId;
  final String   ratificationState;   // approved | rejected
  final String   ratifiedBy;
  final DateTime? ratifiedAt;
  final String?  feedback;
  final String?  domain;
  final String?  category;

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

/// `DELETE /api/proxy/decision/{decision_id}` response.
class DeleteDecisionResponse {
  final String status;
  final String decisionId;
  final String deletedBy;

  const DeleteDecisionResponse( {
    required this.status,
    required this.decisionId,
    required this.deletedBy,
  } );

  factory DeleteDecisionResponse.fromJson( Map<String, dynamic> json ) {
    return DeleteDecisionResponse(
      status     : ( json["status"] ?? "" ).toString(),
      decisionId : ( json["decision_id"] ?? "" ).toString(),
      deletedBy  : ( json["deleted_by"] ?? "" ).toString(),
    );
  }
}

/// `GET /api/proxy/trust/{user_email}` per-domain entry.
class TrustStateItem {
  final String   id;
  final String   domain;
  final String   category;
  final int      trustLevel;
  final int      totalDecisions;
  final int      successfulDecisions;
  final int      rejectedDecisions;
  final String?  circuitBreakerState;   // open | closed
  final DateTime? createdAt;
  final DateTime? updatedAt;

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

class TrustStateResponse {
  final String               status;
  final String               userEmail;
  final List<TrustStateItem> trustStates;

  const TrustStateResponse( {
    required this.status,
    required this.userEmail,
    required this.trustStates,
  } );

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

/// `GET /api/proxy/decisions/{domain}/{category}` envelope.
class DecisionsByCategoryResponse {
  final String              status;
  final String              domain;
  final String              category;
  final List<ProxyDecision> decisions;

  const DecisionsByCategoryResponse( {
    required this.status,
    required this.domain,
    required this.category,
    required this.decisions,
  } );

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

/// `GET /api/proxy/batch-id` response.
class BatchIdResponse {
  final String status;
  final String batchId;

  const BatchIdResponse( { required this.status, required this.batchId } );

  factory BatchIdResponse.fromJson( Map<String, dynamic> json ) {
    return BatchIdResponse(
      status  : ( json["status"] ?? "" ).toString(),
      batchId : ( json["batch_id"] ?? "" ).toString(),
    );
  }
}

/// `POST /api/proxy/acknowledge` response (no request body required;
/// backend rotates the batch as a side effect).
class AcknowledgeResponse {
  final String status;
  final String retiredBatch;
  final String newBatch;

  const AcknowledgeResponse( {
    required this.status,
    required this.retiredBatch,
    required this.newBatch,
  } );

  factory AcknowledgeResponse.fromJson( Map<String, dynamic> json ) {
    return AcknowledgeResponse(
      status       : ( json["status"] ?? "" ).toString(),
      retiredBatch : ( json["retired_batch"] ?? "" ).toString(),
      newBatch     : ( json["new_batch"] ?? "" ).toString(),
    );
  }
}

/// `GET /api/proxy/mode` response.
class TrustModeStatus {
  final String     status;
  final TrustMode  iniMode;
  final TrustMode? runningMode;
  final TrustMode  effective;
  final bool       hasRunningJob;

  const TrustModeStatus( {
    required this.status,
    required this.iniMode,
    this.runningMode,
    required this.effective,
    required this.hasRunningJob,
  } );

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

/// `PUT /api/proxy/mode` request body.
class TrustModeUpdateRequest {
  final TrustMode mode;
  final String    domain;

  const TrustModeUpdateRequest( {
    required this.mode,
    this.domain = "swe",
  } );

  Map<String, dynamic> toJson() => {
    "mode"   : trustModeToString( mode ),
    "domain" : domain,
  };
}

/// `PUT /api/proxy/mode` response (running OR queued shape).
class TrustModeUpdateResponse {
  final String   status;       // "updated" or "queued"
  final TrustMode oldMode;
  final TrustMode newMode;
  final String   target;       // "running" or "next_job"
  final String?  jobId;        // present when status == "updated"
  final String?  message;      // present when status == "queued"

  const TrustModeUpdateResponse( {
    required this.status,
    required this.oldMode,
    required this.newMode,
    required this.target,
    this.jobId,
    this.message,
  } );

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
