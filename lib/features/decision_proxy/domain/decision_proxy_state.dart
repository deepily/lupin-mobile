import 'package:equatable/equatable.dart';

import '../data/decision_proxy_models.dart';

abstract class DecisionProxyState extends Equatable {
  const DecisionProxyState();

  @override
  List<Object?> get props => [];
}

class DecisionProxyInitial extends DecisionProxyState {
  const DecisionProxyInitial();
}

class DecisionProxyLoading extends DecisionProxyState {
  const DecisionProxyLoading();
}

class DecisionProxyDashboardLoaded extends DecisionProxyState {
  final TrustModeStatus           mode;
  final List<ProxyDecision>       pending;
  final PendingSummary            summary;
  final BatchIdResponse?          batch;

  const DecisionProxyDashboardLoaded( {
    required this.mode,
    required this.pending,
    required this.summary,
    this.batch,
  } );

  @override
  List<Object?> get props => [
    mode.iniMode, mode.runningMode, mode.effective,
    pending.length, summary.totalPending, batch?.batchId,
  ];
}

class DecisionProxyTrustLoaded extends DecisionProxyState {
  final TrustStateResponse trust;
  const DecisionProxyTrustLoaded( this.trust );

  @override
  List<Object?> get props => [ trust.trustStates.length ];
}

class DecisionProxyError extends DecisionProxyState {
  final String message;
  const DecisionProxyError( this.message );

  @override
  List<Object?> get props => [ message ];
}
