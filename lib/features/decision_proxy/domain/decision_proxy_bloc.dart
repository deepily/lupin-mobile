import 'package:flutter_bloc/flutter_bloc.dart';

import '../data/decision_proxy_models.dart';
import '../data/decision_proxy_repository.dart';
import 'decision_proxy_event.dart';
import 'decision_proxy_state.dart';

class DecisionProxyBloc extends Bloc<DecisionProxyEvent, DecisionProxyState> {
  final DecisionProxyRepository _repo;

  String? _activeUserEmail;

  DecisionProxyBloc( this._repo ) : super( const DecisionProxyInitial() ) {
    on<DecisionProxyLoadDashboard>( _onLoadDashboard );
    on<DecisionProxySetMode>( _onSetMode );
    on<DecisionProxyRatify>( _onRatify );
    on<DecisionProxyDeleteDecision>( _onDelete );
    on<DecisionProxyAcknowledge>( _onAcknowledge );
    on<DecisionProxyLoadTrust>( _onLoadTrust );
  }

  Future<void> _onLoadDashboard(
    DecisionProxyLoadDashboard event,
    Emitter<DecisionProxyState> emit,
  ) async {
    _activeUserEmail = event.userEmail;
    emit( const DecisionProxyLoading() );
    try {
      final mode    = await _repo.getMode();
      final pending = await _repo.pending( event.userEmail );
      BatchIdResponse? batch;
      try { batch = await _repo.batchId(); } catch ( _ ) {}
      emit( DecisionProxyDashboardLoaded(
        mode    : mode,
        pending : pending.decisions,
        summary : pending.summary,
        batch   : batch,
      ) );
    } on DecisionProxyApiException catch ( e ) {
      emit( DecisionProxyError( e.message ) );
    }
  }

  Future<void> _onSetMode(
    DecisionProxySetMode event,
    Emitter<DecisionProxyState> emit,
  ) async {
    try {
      await _repo.setMode( TrustModeUpdateRequest(
        mode   : event.mode,
        domain : event.domain,
      ) );
      if ( _activeUserEmail != null ) {
        add( DecisionProxyLoadDashboard( _activeUserEmail! ) );
      }
    } on DecisionProxyApiException catch ( e ) {
      emit( DecisionProxyError( e.message ) );
    }
  }

  Future<void> _onRatify(
    DecisionProxyRatify event,
    Emitter<DecisionProxyState> emit,
  ) async {
    try {
      await _repo.ratify(
        event.decisionId,
        userEmail : event.userEmail,
        approved  : event.approved,
        feedback  : event.feedback,
      );
      add( DecisionProxyLoadDashboard( event.userEmail ) );
    } on DecisionProxyApiException catch ( e ) {
      emit( DecisionProxyError( e.message ) );
    }
  }

  Future<void> _onDelete(
    DecisionProxyDeleteDecision event,
    Emitter<DecisionProxyState> emit,
  ) async {
    try {
      await _repo.deleteDecision(
        event.decisionId,
        userEmail: event.userEmail,
      );
      add( DecisionProxyLoadDashboard( event.userEmail ) );
    } on DecisionProxyApiException catch ( e ) {
      emit( DecisionProxyError( e.message ) );
    }
  }

  Future<void> _onAcknowledge(
    DecisionProxyAcknowledge event,
    Emitter<DecisionProxyState> emit,
  ) async {
    try {
      await _repo.acknowledge();
      add( DecisionProxyLoadDashboard( event.userEmail ) );
    } on DecisionProxyApiException catch ( e ) {
      emit( DecisionProxyError( e.message ) );
    }
  }

  Future<void> _onLoadTrust(
    DecisionProxyLoadTrust event,
    Emitter<DecisionProxyState> emit,
  ) async {
    try {
      final t = await _repo.trustState(
        event.userEmail,
        domain: event.domain,
      );
      emit( DecisionProxyTrustLoaded( t ) );
    } on DecisionProxyApiException catch ( e ) {
      emit( DecisionProxyError( e.message ) );
    }
  }
}
