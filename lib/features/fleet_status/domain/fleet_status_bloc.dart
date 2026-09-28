import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../fleet/domain/pane_polling_mixin.dart';
import '../../fleet/domain/pane_visibility_mixin.dart';
import '../data/fleet_models.dart';
import '../data/fleet_repository.dart';
import '../data/fleet_watchable_models.dart';

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

sealed class FleetStatusEvent extends Equatable {
  const FleetStatusEvent();
  @override
  List<Object?> get props => const [];
}

/// A poll landed, or a manual refresh completed.
class FleetStatusLoaded extends FleetStatusEvent {
  final FleetComposite composite;
  final int?           cap;
  final int?           capMaximum;

  /// Which seats this caller may watch, or **null meaning "this event says nothing about
  /// watchability, keep what you have"**.
  ///
  /// 🔴 NULL AND `FleetWatchableRoster.none` ARE DIFFERENT ANSWERS, AND CONFLATING THEM
  /// IS A BUG I WROTE AND CAUGHT. `none` means the projection was read and nothing is
  /// watchable — every button hides. Null means this particular event is not a poll:
  /// [FleetStatusBloc.setCap] re-emits `Loaded` to carry the server's re-read of the
  /// dial, and with a non-nullable field defaulting to `none` that emit would have
  /// **wiped every watch button off the pane on any cap change** — a control vanishing
  /// because an unrelated number moved. A poll always supplies a roster, so a genuine
  /// loss of admin still empties the set.
  final FleetWatchableRoster? watchable;

  const FleetStatusLoaded(
    this.composite, {
    this.cap,
    this.capMaximum,
    this.watchable,
  } );

  @override
  List<Object?> get props =>
      [ composite, cap, capMaximum, watchable?.watchableSessionIds ];
}

/// A fetch failed. Distinct from the composite's own "unreachable".
class FleetStatusFailed extends FleetStatusEvent {
  final String message;
  const FleetStatusFailed( this.message );
  @override
  List<Object?> get props => [ message ];
}

/// The operator pulled to refresh.
class FleetStatusRefreshRequested extends FleetStatusEvent {
  const FleetStatusRefreshRequested();
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class FleetStatusState extends Equatable {
  final FleetComposite? composite;
  final int?            cap;
  final int?            capMaximum;
  final String?         error;
  final bool            loading;

  /// The full session ids this caller may open a console on.
  ///
  /// ⚠️ EMPTY IS THE DEFAULT AND EMPTY MEANS "NO BUTTONS", which is also what a 403, a
  /// failed projection call, an unreachable arbiter and an older server all produce. The
  /// pane cannot tell those apart and deliberately does not try: §5 says a refused watch
  /// shows no error and no dead button.
  final Set<String> watchableSessionIds;

  const FleetStatusState( {
    this.composite,
    this.cap,
    this.capMaximum,
    this.error,
    this.loading = false,
    this.watchableSessionIds = const <String>{},
  } );

  FleetStatusState copyWith( {
    FleetComposite? composite,
    int?            cap,
    int?            capMaximum,
    String?         error,
    bool?           loading,
    bool            clearError = false,
    Set<String>?    watchableSessionIds,
  } ) {
    return FleetStatusState(
      composite  : composite  ?? this.composite,
      cap        : cap        ?? this.cap,
      capMaximum : capMaximum ?? this.capMaximum,
      error      : clearError ? null : ( error ?? this.error ),
      loading    : loading    ?? this.loading,
      watchableSessionIds : watchableSessionIds ?? this.watchableSessionIds,
    );
  }

  @override
  List<Object?> get props =>
      [ composite, cap, capMaximum, error, loading, watchableSessionIds ];
}

// ---------------------------------------------------------------------------
// Bloc
// ---------------------------------------------------------------------------

/// Fleet Status — the pane's poll loop and its one write.
///
/// 🔴 THIS BLOC IS ROUTE-SCOPED, NOT AN APP-ROOT SINGLETON, and that is a
/// deliberate departure from this app's convention rather than an oversight.
/// `app.dart:248-278` registers its providers at the app root, so a pane bloc
/// built that way outlives its route and keeps polling whichever destination
/// happens to be showing. `PanePollingMixin` documents the same requirement
/// from the other side: the route must call [onPaneVisible] / [onPaneHidden],
/// and the guarding test is *with pane A on screen, pane B issues zero
/// requests*.
///
/// ⚠️ THE POLL AND THE CAP READ ARE ONE REQUEST PAIR, NOT TWO LOOPS. The web
/// makes the same choice — the dial rides the same refresh as the table
/// (`FleetStatusStore.ts:14-17`) — so the dial cannot drift from the table by
/// a poll interval.
class FleetStatusBloc extends Bloc<FleetStatusEvent, FleetStatusState>
    with PaneVisibilityMixin<FleetStatusEvent, FleetStatusState>,
        PanePollingMixin<FleetStatusEvent, FleetStatusState> {
  final FleetRepository _repo;

  FleetStatusBloc( this._repo ) : super( const FleetStatusState() ) {
    on<FleetStatusLoaded>( ( event, emit ) => emit( state.copyWith(
      composite  : event.composite,
      cap        : event.cap,
      capMaximum : event.capMaximum,
      loading    : false,
      clearError : true,
      // Null means "nothing to say" — keep the set the last poll established.
      watchableSessionIds : event.watchable?.watchableSessionIds
                            ?? state.watchableSessionIds,
    ) ) );

    on<FleetStatusFailed>( ( event, emit ) => emit( state.copyWith(
      error   : event.message,
      loading : false,
    ) ) );

    on<FleetStatusRefreshRequested>( ( event, emit ) async {
      emit( state.copyWith( loading: true ) );
      await pollOnce( CancelToken() );
    } );
  }

  /// One poll: the composite and the dial's numbers together.
  ///
  /// Requires:
  ///     - token is handed to every request, or the mixin's cancellation buys
  ///       nothing when the pane goes away mid-flight
  ///
  /// Ensures:
  ///     - adds [FleetStatusLoaded] on success, [FleetStatusFailed] otherwise
  ///     - a cancelled COMPOSITE fetch adds NOTHING — there is no table to show,
  ///       and the pane is going away
  ///     - 🔴 a cancelled DIAL fetch still adds [FleetStatusLoaded] with the
  ///       composite already in hand (B1a, 2026-09-23). It used to escape to the
  ///       outer cancel-return, adding neither state while holding a good table:
  ///       `composite == null && error == null` is the screen's spinner branch
  ///     - every exit path prints ONE `[FleetStatus] poll:` line (B1b). Rick's
  ///       09-22 spinner left no console output at all, so the next one has to
  ///       name the path it took
  ///     - never throws
  @override
  Future<void> pollOnce( CancelToken token ) async {
    try {
      final composite = await _repo.fetchState( cancelToken: token );

      // ⚠️ A FAILED CAP READ MUST NOT BLANK THE TABLE. The dial is one control;
      // the table is the pane. They are fetched together but they fail apart.
      int? cap;
      int? capMaximum;
      try {
        final dial  = await _repo.fetchSizeCap( cancelToken: token );
        final rawC  = dial[ "cap" ];
        final rawM  = dial[ "maximum" ] ?? dial[ "cap_maximum" ];
        cap         = rawC is num ? rawC.toInt() : null;
        capMaximum  = rawM is num ? rawM.toInt() : null;
        debugPrint( '[FleetStatus] poll: loaded, cap=$cap' );
      } on FleetApiException catch ( e ) {
        // Leave the dial's last known numbers standing rather than zeroing a
        // control the operator may be about to use.
        cap        = state.cap;
        capMaximum = state.capMaximum;
        debugPrint( '[FleetStatus] poll: loaded, dial failed (${e.message}) — kept cap=$cap' );
      } on DioException catch ( e ) {
        // 🔴 THE DOOR THE COMMENT ABOVE DID NOT COVER. Only a CANCEL is caught
        // here — the table is in hand, so fail apart exactly as for an API error.
        // Anything else still falls through to the outer handler, unchanged.
        if ( e.type != DioExceptionType.cancel ) rethrow;
        cap        = state.cap;
        capMaximum = state.capMaximum;
        debugPrint( '[FleetStatus] poll: loaded, dial CANCELLED — kept cap=$cap' );
      }

      // ⚠️ THE ROSTER FAILS APART FROM THE TABLE, for the same reason the dial does —
      // and more so, because most callers are not admins and for them "unavailable" is
      // the CORRECT answer rather than a fault. `fetchWatchable` already swallows
      // everything but a cancellation, so this only has to handle the pane going away.
      //
      // 🔴 NULL, NOT `FleetWatchableRoster.none`, AND THE DIFFERENCE IS THE WHOLE BUG.
      // `none` is an ANSWER — "the projection was read and nothing is watchable" — and the
      // reducer's `??` cannot see past it, so a cancelled fetch wiped an established roster
      // and every watch button vanished. Null means "this poll learned nothing about
      // watchability", which is exactly what a cancellation is.
      //
      // I wrote the sibling of this bug into `setCap` and fixed it there, then left this
      // door open: the fix was a nullable FIELD, but this local was still initialised to a
      // legal value, so the conflation the field's own docstring forbids survived one level
      // down. Found by Pocholo 📣 2026-09-27 with a probe, not by a test — good poll
      // `{seat-alpha}`, then after a cancel `{}`. The lesson is that "nullable means
      // unknown" has to hold at every assignment, not just at the declaration.
      FleetWatchableRoster? watchable;
      try {
        watchable = await _repo.fetchWatchable( cancelToken: token );
      } on DioException catch ( e ) {
        if ( e.type != DioExceptionType.cancel ) rethrow;
        debugPrint(
          '[FleetStatus] poll: watchable roster CANCELLED — keeping the last known roster' );
      }

      if ( isClosed ) {
        debugPrint( '[FleetStatus] poll: bloc closed before Loaded could be added' );
        return;
      }
      add( FleetStatusLoaded(
        composite,
        cap        : cap,
        capMaximum : capMaximum,
        watchable  : watchable,
      ) );
    } on FleetApiException catch ( e ) {
      debugPrint( '[FleetStatus] poll: FAILED (${e.message})' );
      if ( isClosed ) return;
      add( FleetStatusFailed( e.message ) );
    } on DioException catch ( e ) {
      // A cancelled COMPOSITE fetch is the pane going away with nothing to show —
      // returning is right here, and is the one path that adds no state (B1a′).
      if ( e.type == DioExceptionType.cancel ) {
        debugPrint( '[FleetStatus] poll: composite CANCELLED — no state added' );
        return;
      }
      debugPrint( '[FleetStatus] poll: FAILED (${e.type.name}: ${e.message})' );
      if ( isClosed ) return;
      add( FleetStatusFailed( e.message ?? e.type.name ) );
    }
  }

  /// Set the fleet-size cap and adopt the SERVER'S answer.
  ///
  /// 🔴 THE VALUE WRITTEN INTO STATE IS THE ONE THE SERVER RE-READ, NEVER THE
  /// ONE POSTED (`FleetStatusStore.ts:185-188`). The spawn path reads the cap
  /// fresh from disk, so a dial that echoed its own input would display a
  /// number the fleet is not enforcing.
  ///
  /// Ensures:
  ///     - on success, state carries the server's `cap`
  ///     - on refusal, RE-READS live state so the handle snaps back to what is
  ///       actually enforced rather than sitting on a number the operator never
  ///       got (`FleetStatusStore.ts:203-206`), and rethrows so the dial can
  ///       surface the server's words
  Future<void> setCap( int cap ) async {
    try {
      final answer   = await _repo.setSizeCap( cap );
      final rawC     = answer[ "cap" ];
      final rawM     = answer[ "maximum" ] ?? answer[ "cap_maximum" ];
      if ( isClosed ) return;
      add( FleetStatusLoaded(
        state.composite ?? const FleetComposite(),
        cap        : rawC is num ? rawC.toInt() : state.cap,
        capMaximum : rawM is num ? rawM.toInt() : state.capMaximum,
      ) );
    } catch ( _ ) {
      // Re-read rather than guess. The mixin's token is not used here: this is
      // an operator action, not a poll, and it should complete even if the pane
      // is mid-transition.
      await pollOnce( CancelToken() );
      rethrow;
    }
  }
}
