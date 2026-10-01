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

/// An input to [FleetStatusBloc].
sealed class FleetStatusEvent extends Equatable {
  /// Creates an event.
  const FleetStatusEvent();
  @override
  List<Object?> get props => const [];
}

/// A poll landed, or a manual refresh completed.
class FleetStatusLoaded extends FleetStatusEvent {
  /// The fleet table and envelope from this poll.
  final FleetComposite composite;

  /// The fleet-size cap, or null when it could not be read.
  final int?           cap;

  /// The server's ceiling for the cap, or null when unknown.
  final int?           capMaximum;

  /// Which seats this caller may watch, or null meaning "keep what you have".
  ///
  /// Null and `FleetWatchableRoster.none` are different answers. `none` means the
  /// projection was read and nothing is watchable, so every button hides. Null means this
  /// event is not a poll. The bloc's `setCap` re-emits `Loaded` for the dial, and a
  /// default of `none` would wipe every watch button on any cap change. A poll always
  /// supplies a roster, so a real loss of admin still empties the set.
  final FleetWatchableRoster? watchable;

  /// Creates the event; [watchable] stays null when the event is not a poll.
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
  /// The failure text to show.
  final String message;

  /// Creates the event.
  const FleetStatusFailed( this.message );
  @override
  List<Object?> get props => [ message ];
}

/// The operator pulled to refresh.
class FleetStatusRefreshRequested extends FleetStatusEvent {
  /// Creates the event.
  const FleetStatusRefreshRequested();
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

/// The Fleet Status pane's state.
class FleetStatusState extends Equatable {
  /// The latest fleet composite, or null before the first poll lands.
  final FleetComposite? composite;

  /// The fleet-size cap, or null when unknown.
  final int?            cap;

  /// The server's ceiling for the cap, or null when unknown.
  final int?            capMaximum;

  /// The latest failure text, or null.
  final String?         error;

  /// True while a manual refresh is in flight.
  final bool            loading;

  /// The full session ids this caller may open a console on.
  ///
  /// Empty means no buttons. A 403, a failed projection call, an unreachable arbiter and
  /// an older server all produce it. The pane does not tell them apart: a refused watch
  /// shows no error and no dead button.
  final Set<String> watchableSessionIds;

  /// Creates the state; everything defaults to empty.
  const FleetStatusState( {
    this.composite,
    this.cap,
    this.capMaximum,
    this.error,
    this.loading = false,
    this.watchableSessionIds = const <String>{},
  } );

  /// Copies the state with changes; [clearError] drops the error.
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

/// Fleet Status: the pane's poll loop and its one write.
///
/// Register it per route, not at the app root. A root-level bloc outlives its route and
/// keeps polling whichever destination is showing, which departs from the app's usual
/// convention. The route must call [onPaneVisible] and [onPaneHidden], as
/// [PanePollingMixin] requires. The poll and the cap read are one request pair, so the
/// dial cannot drift from the table by a poll interval.
class FleetStatusBloc extends Bloc<FleetStatusEvent, FleetStatusState>
    with PaneVisibilityMixin<FleetStatusEvent, FleetStatusState>,
        PanePollingMixin<FleetStatusEvent, FleetStatusState> {
  final FleetRepository _repo;

  /// Creates the bloc over [_repo].
  FleetStatusBloc( this._repo ) : super( const FleetStatusState() ) {
    on<FleetStatusLoaded>( ( event, emit ) => emit( state.copyWith(
      composite  : event.composite,
      cap        : event.cap,
      capMaximum : event.capMaximum,
      loading    : false,
      clearError : true,
      // Null means nothing to say: keep the set the last poll established.
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

  /// Polls the composite and the dial's numbers together.
  ///
  /// Requires:
  ///     - token is handed to every request, or cancellation does nothing when the pane
  ///       goes away mid-flight
  ///
  /// Ensures:
  ///     - adds [FleetStatusLoaded] on success and [FleetStatusFailed] otherwise
  ///     - a cancelled composite fetch adds nothing, because there is no table to show
  ///     - a cancelled dial fetch still adds [FleetStatusLoaded] with the composite in
  ///       hand; otherwise `composite == null && error == null`, the screen's spinner
  ///       branch, would show with a good table held
  ///     - every exit path prints one `[FleetStatus] poll:` line, so a stuck spinner names
  ///       the path it took
  ///     - never throws
  @override
  Future<void> pollOnce( CancelToken token ) async {
    try {
      final composite = await _repo.fetchState( cancelToken: token );

      // A failed cap read must not blank the table: the dial is one control and the table
      // is the pane, so they are fetched together but fail apart.
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
        // Keep the dial's last known numbers instead of zeroing a control in use.
        cap        = state.cap;
        capMaximum = state.capMaximum;
        debugPrint( '[FleetStatus] poll: loaded, dial failed (${e.message}) — kept cap=$cap' );
      } on DioException catch ( e ) {
        // Only a cancel is caught here. The table is in hand, so it fails apart as for an
        // API error. Anything else falls through to the outer handler.
        if ( e.type != DioExceptionType.cancel ) rethrow;
        cap        = state.cap;
        capMaximum = state.capMaximum;
        debugPrint( '[FleetStatus] poll: loaded, dial CANCELLED — kept cap=$cap' );
      }

      // The roster fails apart from the table, as the dial does; most callers are not
      // admins, and for them "unavailable" is the correct answer. `fetchWatchable`
      // swallows everything but a cancellation, so only the pane going away is handled
      // here. The local stays null on a cancel, not `FleetWatchableRoster.none`. `none` is
      // an answer, and the reducer's `??` cannot see past it, so a cancelled fetch would
      // wipe an established roster and every watch button. Null means this poll learned
      // nothing about watchability. "Nullable means unknown" must hold at every
      // assignment, not only at the declaration.
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
      // A cancelled composite fetch is the pane going away with nothing to show; returning
      // is right, and it is the one path that adds no state.
      if ( e.type == DioExceptionType.cancel ) {
        debugPrint( '[FleetStatus] poll: composite CANCELLED — no state added' );
        return;
      }
      debugPrint( '[FleetStatus] poll: FAILED (${e.type.name}: ${e.message})' );
      if ( isClosed ) return;
      add( FleetStatusFailed( e.message ?? e.type.name ) );
    }
  }

  /// Sets the fleet-size cap and adopts the server's answer.
  ///
  /// The value written into state is the one the server re-read, never the one posted.
  /// The spawn path reads the cap fresh from disk, so a dial that echoed its input would
  /// show a number the fleet is not enforcing.
  ///
  /// Ensures:
  ///     - on success, state carries the server's `cap`
  ///     - on refusal, re-reads live state so the handle snaps back to what is enforced,
  ///       and rethrows so the dial can show the server's words
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
      // Re-read rather than guess. The mixin's token is not used: this is an operator
      // action, not a poll, and it should complete even if the pane is mid-transition.
      await pollOnce( CancelToken() );
      rethrow;
    }
  }
}
