import 'package:equatable/equatable.dart';

import '../data/decision_proxy_models.dart';

/// A state of the decision-proxy bloc.
abstract class DecisionProxyState extends Equatable {
  /// Creates a state.
  const DecisionProxyState();

  @override
  List<Object?> get props => [];
}

/// Nothing has been requested yet.
class DecisionProxyInitial extends DecisionProxyState {
  /// Creates the state.
  const DecisionProxyInitial();
}

/// A dashboard load is in flight.
class DecisionProxyLoading extends DecisionProxyState {
  /// Creates the state.
  const DecisionProxyLoading();
}

/// The dashboard data is ready to show.
class DecisionProxyDashboardLoaded extends DecisionProxyState {
  /// The proxy's trust mode.
  final TrustModeStatus           mode;

  /// Decisions awaiting ratification.
  final List<ProxyDecision>       pending;

  /// Counts over the pending decisions.
  final PendingSummary            summary;

  /// The current batch id, or null when the batch lookup failed.
  final BatchIdResponse?          batch;

  /// Creates the state.
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

/// The per-domain trust states are ready to show.
class DecisionProxyTrustLoaded extends DecisionProxyState {
  /// The loaded trust states.
  final TrustStateResponse trust;

  /// Creates the state.
  const DecisionProxyTrustLoaded( this.trust );

  @override
  List<Object?> get props => [ trust.trustStates.length ];
}

/// A request failed.
class DecisionProxyError extends DecisionProxyState {
  /// The server's message for the failure.
  final String message;

  /// Creates the state.
  const DecisionProxyError( this.message );

  @override
  List<Object?> get props => [ message ];
}
