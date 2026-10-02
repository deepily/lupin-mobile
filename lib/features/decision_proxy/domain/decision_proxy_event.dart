import 'package:equatable/equatable.dart';

import '../data/decision_proxy_models.dart';

/// An input to the decision-proxy bloc.
abstract class DecisionProxyEvent extends Equatable {
  /// Creates an event.
  const DecisionProxyEvent();

  @override
  List<Object?> get props => [];
}

/// Load the dashboard: trust mode, pending decisions and the current batch id.
class DecisionProxyLoadDashboard extends DecisionProxyEvent {
  /// The user whose pending decisions to load.
  final String userEmail;

  /// Creates the event for [userEmail].
  const DecisionProxyLoadDashboard( this.userEmail );

  @override
  List<Object?> get props => [ userEmail ];
}

/// Change the proxy's trust mode, then reload the dashboard.
class DecisionProxySetMode extends DecisionProxyEvent {
  /// The mode to switch to.
  final TrustMode mode;

  /// Domain the change applies to.
  final String    domain;

  /// Creates the event; [domain] defaults to `"swe"`.
  const DecisionProxySetMode( { required this.mode, this.domain = "swe" } );

  @override
  List<Object?> get props => [ mode, domain ];
}

/// Approve or reject one pending decision, then reload the dashboard.
class DecisionProxyRatify extends DecisionProxyEvent {
  /// Id of the decision to ratify.
  final String  decisionId;

  /// The user ratifying the decision.
  final String  userEmail;

  /// True to approve, false to reject.
  final bool    approved;

  /// Optional free-text feedback sent with the verdict.
  final String? feedback;

  /// Creates the event.
  const DecisionProxyRatify( {
    required this.decisionId,
    required this.userEmail,
    required this.approved,
    this.feedback,
  } );

  @override
  List<Object?> get props => [ decisionId, userEmail, approved, feedback ];
}

/// Delete one decision, then reload the dashboard.
class DecisionProxyDeleteDecision extends DecisionProxyEvent {
  /// Id of the decision to delete.
  final String decisionId;

  /// The user deleting the decision.
  final String userEmail;

  /// Creates the event.
  const DecisionProxyDeleteDecision( {
    required this.decisionId,
    required this.userEmail,
  } );

  @override
  List<Object?> get props => [ decisionId, userEmail ];
}

/// Acknowledge the current batch, then reload the dashboard.
class DecisionProxyAcknowledge extends DecisionProxyEvent {
  /// The user whose dashboard to reload afterwards.
  final String userEmail;

  /// Creates the event for [userEmail].
  const DecisionProxyAcknowledge( this.userEmail );

  @override
  List<Object?> get props => [ userEmail ];
}

/// Load the per-domain trust states of one user.
class DecisionProxyLoadTrust extends DecisionProxyEvent {
  /// The user whose trust states to load.
  final String  userEmail;

  /// Restricts the load to one domain; null loads every domain.
  final String? domain;

  /// Creates the event.
  const DecisionProxyLoadTrust( { required this.userEmail, this.domain } );

  @override
  List<Object?> get props => [ userEmail, domain ];
}
