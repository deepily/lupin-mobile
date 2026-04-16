import 'package:equatable/equatable.dart';

import '../data/decision_proxy_models.dart';

abstract class DecisionProxyEvent extends Equatable {
  const DecisionProxyEvent();

  @override
  List<Object?> get props => [];
}

class DecisionProxyLoadDashboard extends DecisionProxyEvent {
  final String userEmail;
  const DecisionProxyLoadDashboard( this.userEmail );

  @override
  List<Object?> get props => [ userEmail ];
}

class DecisionProxySetMode extends DecisionProxyEvent {
  final TrustMode mode;
  final String    domain;
  const DecisionProxySetMode( { required this.mode, this.domain = "swe" } );

  @override
  List<Object?> get props => [ mode, domain ];
}

class DecisionProxyRatify extends DecisionProxyEvent {
  final String  decisionId;
  final String  userEmail;
  final bool    approved;
  final String? feedback;

  const DecisionProxyRatify( {
    required this.decisionId,
    required this.userEmail,
    required this.approved,
    this.feedback,
  } );

  @override
  List<Object?> get props => [ decisionId, userEmail, approved, feedback ];
}

class DecisionProxyDeleteDecision extends DecisionProxyEvent {
  final String decisionId;
  final String userEmail;

  const DecisionProxyDeleteDecision( {
    required this.decisionId,
    required this.userEmail,
  } );

  @override
  List<Object?> get props => [ decisionId, userEmail ];
}

class DecisionProxyAcknowledge extends DecisionProxyEvent {
  final String userEmail;
  const DecisionProxyAcknowledge( this.userEmail );

  @override
  List<Object?> get props => [ userEmail ];
}

class DecisionProxyLoadTrust extends DecisionProxyEvent {
  final String  userEmail;
  final String? domain;
  const DecisionProxyLoadTrust( { required this.userEmail, this.domain } );

  @override
  List<Object?> get props => [ userEmail, domain ];
}
