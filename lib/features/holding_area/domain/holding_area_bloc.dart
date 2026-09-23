import 'dart:async';

import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../services/network/network_connectivity_service.dart';
import '../../fleet/data/task_write_repository.dart';
import '../../fleet_status/data/fleet_models.dart';
import '../../fleet_status/data/fleet_repository.dart';
import '../../fleet/domain/pane_polling_mixin.dart';
import '../../fleet/data/task_verbs.dart';
import '../../fleet/domain/unsent_write.dart';
import '../data/holding_area_models.dart';
import '../data/holding_area_repository.dart';

// ─── Events ──────────────────────────────────────────────────────────────────

sealed class HoldingAreaEvent {
  const HoldingAreaEvent();
}

/// A poll tick, a pull-to-refresh, or a resume.
class HoldingAreaRefreshRequested extends HoldingAreaEvent {
  final CancelToken? cancelToken;
  const HoldingAreaRefreshRequested( { this.cancelToken } );
}

/// One row, one verb. The per-row control — the precise instrument.
class HoldingAreaRowVerbPressed extends HoldingAreaEvent {
  final String   id;
  final TaskVerb verb;
  const HoldingAreaRowVerbPressed( { required this.id, required this.verb } );
}

/// Approve every row one filer filed.
///
/// The CONFIRM is the pane's, not the bloc's: by the time this event is added the
/// operator has already answered it. A bloc that popped its own dialog could not be
/// tested without a widget tree, and a pane that dispatched before confirming would put
/// the gate somewhere a later hand can skip.
class HoldingAreaApproveAllPressed extends HoldingAreaEvent {
  final String filer;
  const HoldingAreaApproveAllPressed( this.filer );
}

/// Close every row one filer filed as won't-fix, under ONE reason.
class HoldingAreaWontFixAllPressed extends HoldingAreaEvent {
  final String filer;
  final String reason;
  const HoldingAreaWontFixAllPressed( { required this.filer, required this.reason } );
}

/// An operator changed a held row's priority or owner. Goes through the FIELD door.
///
/// 🔴 A SEPARATE EVENT FROM [HoldingAreaRowVerbPressed], BECAUSE THEY ARE SEPARATE
/// SERVER DOORS. Fields go to `PATCH /api/tasks/{id}`; status goes to
/// `POST /api/tasks/{id}/transition`. Routing a priority change through the verb event
/// would post it to the transition endpoint, which is the plan's §4.2 failure read
/// backwards.
class HoldingAreaFieldChanged extends HoldingAreaEvent {
  final String  id;
  final String? priority;
  final String? ownerPersona;
  const HoldingAreaFieldChanged( {
    required this.id,
    this.priority,
    this.ownerPersona,
  } );
}

/// Fetch the live persona roster the owner control offers.
///
/// ⚠️ A COURTESY READ ON A PANE ABOUT TASKS. Every failure collapses to an empty roster
/// and none of them paints an error — an arbiter the phone cannot reach is a reason the
/// owner dropdown offers less, not a reason to tell the operator the holding area is
/// broken.
class HoldingAreaRosterRequested extends HoldingAreaEvent {
  const HoldingAreaRosterRequested();
}

/// The operator folded or unfolded one persona's group.
///
/// 🔴 THE EVENT CARRIES THE PERSONA, NOT AN INDEX. Group positions move under a poll —
/// a persona whose last held row is approved away disappears and every group below it
/// shifts up — so an index captured at build time can toggle a DIFFERENT persona by the
/// time the tap lands. The Task List's toggle keys on its label for the same reason.
/// The connection came back — resend what the network ate.
///
/// ⚠️ ITS OWN EVENT RATHER THAN A LIMB OF THE REFRESH: one sends the operator's work TO
/// the server, the other pulls the server's state back. Folding them together would make
/// "refresh" mean "also write", which is not a thing a pull-to-refresh should ever do.
class HoldingAreaUnsentRetryRequested extends HoldingAreaEvent {
  const HoldingAreaUnsentRetryRequested();
}

class HoldingAreaGroupToggled extends HoldingAreaEvent {
  final String filer;
  const HoldingAreaGroupToggled( this.filer );
}

/// The operator typed in one group's batch reason box.
class HoldingAreaReasonChanged extends HoldingAreaEvent {
  final String filer;
  final String reason;
  const HoldingAreaReasonChanged( { required this.filer, required this.reason } );
}

// ─── State ───────────────────────────────────────────────────────────────────

class HoldingAreaState extends Equatable {
  final List<FilerGroup> groups;
  final bool loading;
  final String? error;

  /// True when the page is not the whole held set — surfaced as a visible banner.
  final bool incomplete;
  final int total;

  /// Per-group batch reason text, keyed by filer. The OPERATOR's typing, so it survives
  /// a poll — a refresh that blanked a half-typed justification every sixty seconds
  /// would make the batch control unusable on exactly the groups big enough to need it.
  final Map<String, String> reasons;

  /// Per-group validation complaint, keyed by filer. Set when won't-fix-all is pressed
  /// with an empty box, cleared as soon as the operator types.
  final Map<String, String> reasonErrors;

  /// What the last batch actually did.
  ///
  /// 🔴 A SEPARATE FIELD FROM [error], BECAUSE THE TWO HAVE DIFFERENT LIFETIMES AND THE
  /// SHORTER ONE WAS EATING THE LONGER. A batch ends by refetching, the refetch clears
  /// the fetch error, and a partial-batch report parked in `error` was therefore wiped
  /// about eighty milliseconds after it appeared — the operator saw nothing, in the one
  /// case where some of their rows moved and some did not. A fetch error is answered by
  /// the next fetch; a report about what a press DID is answered only by the operator
  /// reading it.
  final String? batchNotice;

  /// Filers whose batch write is in flight. The pane disables both batch controls for
  /// that group — a second press while N transitions are still landing would double the
  /// writes without doubling the count the operator read.
  final Set<String> busyFilers;

  /// The personas a held row may be reassigned to — the LIVE fleet, from the arbiter.
  ///
  /// ⚠️ NOT THE OWNERS THE BOARD ALREADY SHOWS. That set is smaller by definition: it
  /// carries only personas who already hold a row, so it cannot hand work to a seat that
  /// owns none yet. Empty when the arbiter is unreachable, which degrades the control
  /// rather than the pane.
  final List<String> reassignTargets;

  /// Personas the operator has UNFOLDED.
  ///
  /// 🔴 AN `expanded` SET, NOT THE TASK LIST'S `collapsed` SET, AND THE INVERSION IS THE
  /// WHOLE FEATURE. Rick asked for *"folded by default so that we can do progressive
  /// disclosure"*. Tracking what is collapsed makes EXPANDED the default, which is the
  /// state he was complaining about; the empty set has to mean "everything is folded" or
  /// the default arrives wrong and no test of the toggle would notice.
  ///
  /// ⚠️ NOT PERSISTED, AND NOT RESTORED ACROSS A VISIT (N2c). The bloc is route-scoped,
  /// so leaving the pane and coming back folds everything again. That is the specified
  /// behaviour; if Rick wants it remembered it is a ruling, because it means choosing
  /// where to remember it.
  ///
  /// ⚠️ IT SURVIVES A POLL, WHICH IS NOT THE SAME THING. A refresh that re-folded the
  /// group the operator is reading — every 60 or 180 seconds, mid-scroll — would make
  /// the pane unusable on exactly the personas big enough to need folding. The refresh
  /// handler replaces `groups` and leaves this alone.
  final Set<String> expanded;

  /// Writes the operator made that never reached the server, keyed by task id.
  ///
  /// 🔴 PER ROW, EVEN FOR A BATCH, AND THAT IS THE HALF A GROUP-LEVEL NOTICE CANNOT DO.
  /// Approve-all writes N rows in one press and they fail INDEPENDENTLY — the existing
  /// `batchNotice` already reports "one did not, the rest did", which is the right
  /// sentence and still leaves the operator scanning the group to find WHICH one. Keying
  /// the marks by task id means the rows that did not land are the rows wearing a mark.
  final Map<String, UnsentWrite> unsent;

  const HoldingAreaState( {
    this.groups       = const <FilerGroup>[],
    this.loading      = false,
    this.error,
    this.incomplete   = false,
    this.total        = 0,
    this.reasons      = const <String, String>{},
    this.reasonErrors = const <String, String>{},
    this.busyFilers   = const <String>{},
    this.expanded     = const <String>{},
    this.reassignTargets = const <String>[],
    this.unsent          = const <String, UnsentWrite>{},
    this.batchNotice,
  } );

  HoldingAreaState copyWith( {
    List<FilerGroup>? groups,
    bool? loading,
    String? error,
    bool clearError = false,
    bool? incomplete,
    int? total,
    Map<String, String>? reasons,
    Map<String, String>? reasonErrors,
    Set<String>? busyFilers,
    Set<String>? expanded,
    List<String>? reassignTargets,
    Map<String, UnsentWrite>? unsent,
    String? batchNotice,
    bool clearBatchNotice = false,
  } ) =>
      HoldingAreaState(
        groups       : groups ?? this.groups,
        loading      : loading ?? this.loading,
        error        : clearError ? null : ( error ?? this.error ),
        incomplete   : incomplete ?? this.incomplete,
        total        : total ?? this.total,
        reasons      : reasons ?? this.reasons,
        reasonErrors : reasonErrors ?? this.reasonErrors,
        busyFilers   : busyFilers ?? this.busyFilers,
        expanded     : expanded ?? this.expanded,
        reassignTargets : reassignTargets ?? this.reassignTargets,
        unsent          : unsent ?? this.unsent,
        batchNotice  : clearBatchNotice ? null : ( batchNotice ?? this.batchNotice ),
      );

  /// The reason currently typed for one group, or the empty string.
  String reasonFor( String filer ) => reasons[ filer ] ?? '';

  /// What the operator did to this row that has not landed, if anything.
  String? unsentLabelFor( String taskId ) => unsent[ taskId ]?.label;

  /// Whether one persona's rows are on screen. Folded unless the operator said otherwise.
  bool isExpanded( String filer ) => expanded.contains( filer );

  @override
  List<Object?> get props =>
      [ groups, loading, error, incomplete, total, reasons, reasonErrors, busyFilers,
        expanded, reassignTargets, unsent, batchNotice ];
}

// ─── Bloc ────────────────────────────────────────────────────────────────────

/// The Holding Area pane's bloc.
///
/// ⚠️ ROUTE-SCOPED, NOT AN APP-ROOT SINGLETON, for the reason the Task List's bloc
/// records: a pane bloc registered at the app root outlives its route and its poll timer
/// then runs against whichever destination is showing. See [PanePollingMixin].
class HoldingAreaBloc extends Bloc<HoldingAreaEvent, HoldingAreaState>
    with PanePollingMixin<HoldingAreaEvent, HoldingAreaState> {
  final HoldingAreaRepository _repo;
  final TaskWriteRepository   _writes;
  final NetworkConnectivityService _network;

  /// ⚠️ OPTIONAL, AND THE REASSIGNMENT ROSTER IS ALL IT IS FOR. Passed rather than
  /// required so the pane still renders — and still shows held work — when the arbiter
  /// is unreachable or when a test does not care about the owner control.
  final FleetRepository? _fleet;

  StreamSubscription<NetworkState>? _connectivitySub;

  HoldingAreaBloc(
    this._repo,
    this._writes, {
    NetworkConnectivityService? network,
    FleetRepository? fleet,
  } )  : _network = network ?? NetworkConnectivityService(),
        _fleet   = fleet,
        super( const HoldingAreaState() ) {
    on<HoldingAreaRefreshRequested>( _onRefresh );
    on<HoldingAreaRowVerbPressed>( _onRowVerb );
    on<HoldingAreaApproveAllPressed>( _onApproveAll );
    on<HoldingAreaWontFixAllPressed>( _onWontFixAll );
    on<HoldingAreaReasonChanged>( _onReasonChanged );
    on<HoldingAreaGroupToggled>( _onGroupToggled );
    on<HoldingAreaFieldChanged>( _onField );
    on<HoldingAreaRosterRequested>( _onRoster );
    on<HoldingAreaUnsentRetryRequested>( _onRetryUnsent );
  }

  /// The poll interval reads the connection, same measurement as the Task List: a full
  /// page is ~2.1 MB and a terse one ~107 KB, so sixty seconds on a metered connection is
  /// rude even terse.
  ///
  /// ⚠️ THE INTERVAL ITSELF IS `PanePollingMixin.pollInterval` NOW. This pane's copy was
  /// identical to the Task List's, and the two were one edit away from disagreeing. All
  /// that is overridden here is WHICH network service answers, because this bloc holds an
  /// injected one its tests fake.
  @override
  bool get isMeteredConnection => _network.isMobile;

  @override
  Future<void> pollOnce( CancelToken token ) async {
    add( HoldingAreaRefreshRequested( cancelToken: token ) );
  }

  /// The connection came back: resend what the network ate, once each.
  ///
  /// 🔴 ONE ATTEMPT PER WRITE PER EDGE, and the retry goes out BEFORE the refetch — a
  /// refetch landing first repaints the pane from a server that does not yet have the
  /// operator's write, so the row flickers back to held and only then leaves.
  ///
  /// ⚠️ A RETRY THAT MEETS A REFUSAL STOPS BEING UNSENT: the connection is plainly fine,
  /// so the mark would never clear. The record is dropped and the SERVER'S OWN WORDS go
  /// to `batchNotice`, which is the field that survives the refetch this pane schedules.
  Future<void> _onRetryUnsent(
    HoldingAreaUnsentRetryRequested event,
    Emitter<HoldingAreaState> emit,
  ) async {
    if ( state.unsent.isEmpty ) return;

    final outcome = await retryUnsentWrites( state.unsent, _send );

    emit( state.copyWith(
      unsent           : outcome.remaining,
      batchNotice      : outcome.refusals.isEmpty ? null : outcome.refusals.first,
      clearBatchNotice : outcome.refusals.isEmpty,
    ) );
  }

  /// Send one remembered write back through the door it came from.
  ///
  /// ⚠️ THE DOOR IS DECIDED BY WHAT THE WRITE CHANGES, exactly as §4.2 requires of a
  /// fresh one. A retry that guessed the other door would be the same silent failure the
  /// field door is famous for: a PATCH carrying a status is ignored without complaint.
  Future<void> _send( UnsentWrite write ) {
    final verb = write.verb;
    if ( verb != null ) {
      return _writes.transition( id: write.taskId, verb: verb );
    }
    return _writes.patchFields(
      id           : write.taskId,
      priority     : write.priority,
      ownerPersona : write.ownerPersona,
    );
  }

  Map<String, UnsentWrite> _withUnsent( UnsentWrite write ) =>
      <String, UnsentWrite>{ ...state.unsent, write.taskId : write };

  /// Refresh on the connectivity-RESTORED edge only. Firing on every state change would
  /// refetch on the way down too, which is a request into a connection that just failed.
  void startConnectivityRefresh() {
    _connectivitySub ??= _network.networkStateStream.listen( ( state ) {
      if ( state != NetworkState.connected ) return;
      // The retry goes FIRST — see [_onRetryUnsent].
      add( const HoldingAreaUnsentRetryRequested() );
      add( const HoldingAreaRefreshRequested() );
    } );
  }

  Future<void> _onRefresh(
    HoldingAreaRefreshRequested event,
    Emitter<HoldingAreaState> emit,
  ) async {
    emit( state.copyWith( loading: true, clearError: true ) );
    try {
      final page = await _repo.fetch( cancelToken: event.cancelToken );
      emit( state.copyWith(
        groups     : groupByFiler( page.rows ),
        loading    : false,
        incomplete : page.isIncomplete,
        total      : page.total,
      ) );
    } on DioException catch ( e ) {
      // A cancelled poll is the lifecycle rule working, NOT an error to paint.
      if ( CancelToken.isCancel( e ) ) {
        emit( state.copyWith( loading: false ) );
        return;
      }
      emit( state.copyWith( loading: false, error: e.message ?? 'request failed' ) );
    } on HoldingAreaFetchException catch ( e ) {
      emit( state.copyWith( loading: false, error: e.message ) );
    }
  }

  Future<void> _onRowVerb(
    HoldingAreaRowVerbPressed event,
    Emitter<HoldingAreaState> emit,
  ) async {
    try {
      await _writes.transition( id: event.id, verb: event.verb );
    } on Object catch ( e ) {
      // 🔴 G6: THE NOTICE SAYS IT FAILED; THE MARK SAYS WHICH ROW AND WHAT WAS DONE TO
      // IT. Only a transport failure is kept — a server that answered and refused is an
      // error with its own words, and a mark for it would never clear.
      emit( state.copyWith(
        batchNotice : _writeError( e ),
        unsent      : isTransportFailure( e )
            ? _withUnsent( UnsentWrite(
                taskId : event.id,
                label  : verbLabel( event.verb.name ),
                verb   : event.verb,
              ) )
            : state.unsent,
      ) );
      return;
    }
    // The write landed, so whatever this row was carrying is no longer unsent.
    if ( state.unsent.containsKey( event.id ) ) {
      emit( state.copyWith( unsent: { ...state.unsent }..remove( event.id ) ) );
    }
    // 🔴 REFETCH RATHER THAN DROP THE ROW LOCALLY. An approved row leaves this pane, and
    // removing it here would paint a write as applied that the server may have only
    // queued — the 202 case. The fetch is what proves it left.
    add( const HoldingAreaRefreshRequested() );
  }

  Future<void> _onApproveAll(
    HoldingAreaApproveAllPressed event,
    Emitter<HoldingAreaState> emit,
  ) async {
    await _batch(
      filer : event.filer,
      emit  : emit,
      verb  : ( _ ) => TaskVerb.approve(),
    );
  }

  Future<void> _onWontFixAll(
    HoldingAreaWontFixAllPressed event,
    Emitter<HoldingAreaState> emit,
  ) async {
    // 🔴 THE BLANK CHECK IS HERE AS WELL AS IN THE PANE, AND THE DUPLICATION IS THE
    // POINT. The pane's check is what the operator sees; this one is what makes the rule
    // true. A batch dispatched from anywhere else — a test, a later caller, a keyboard
    // shortcut nobody wired to the button — would otherwise send N transitions the
    // server answers with N identical 422s.
    if ( event.reason.trim().isEmpty ) {
      // 🔴 THE COMPLAINT UNFOLDS THE GROUP, BECAUSE THE BOX IT IS ABOUT IS HIDDEN WHILE
      // FOLDED. Collapsing by default took the reason box off screen while leaving both
      // batch buttons on it — deliberately, since the header must still show what the
      // batch would act on. Without this line, pressing won't-fix-all on a folded group
      // sets a complaint the operator cannot see, about a field they cannot reach, and
      // the pane's only feedback is that nothing happened.
      //
      // ⚠️ IT UNFOLDS RATHER THAN REFUSING TO FIRE. Making the button inert while folded
      // would be the other way to close the hole and is worse: an inert control explains
      // nothing, and the operator's next move is to press it again.
      emit( state.copyWith(
        reasonErrors : { ...state.reasonErrors, event.filer: kHoldingWontFixReasonMissing },
        expanded     : { ...state.expanded, event.filer },
      ) );
      return;
    }

    await _batch(
      filer : event.filer,
      emit  : emit,
      verb  : ( _ ) => TaskVerb.wontFix( reason: event.reason.trim() ),
    );
  }

  /// Run one verb over every row in a group.
  ///
  /// ⚠️ SEQUENTIAL, NOT `Future.wait`. Fifty concurrent transitions against one store is
  /// a self-inflicted thundering herd, and the first failure in a `Future.wait` discards
  /// the outcomes of everything racing alongside it — the operator would learn that
  /// "something failed" with no way to know which rows moved.
  ///
  /// 🔴 A PARTIAL BATCH IS REPORTED AS PARTIAL. The loop does not stop at the first
  /// failure and does not pretend the rest succeeded: it counts, then says how many of
  /// how many landed. A batch that silently half-applied is the failure this pane can
  /// least afford, because the pane it half-applied in is the one the operator uses to
  /// see what is still held.
  Future<void> _batch( {
    required String filer,
    required Emitter<HoldingAreaState> emit,
    required TaskVerb Function( String id ) verb,
  } ) async {
    final group = state.groups.where( ( g ) => g.filer == filer ).firstOrNull;
    if ( group == null || group.rows.isEmpty ) return;

    emit( state.copyWith(
      busyFilers       : { ...state.busyFilers, filer },
      clearError       : true,
      clearBatchNotice : true,
      reasonErrors     : { ...state.reasonErrors }..remove( filer ),
    ) );

    final ids      = group.ids;
    var   applied  = 0;
    Object? firstFailure;

    // 🔴 THE ROWS THAT DID NOT LAND ARE THE ROWS THAT WEAR A MARK. "One of fourteen did
    // not move" is the right sentence and still leaves the operator scanning the group to
    // find which one. A batch fails per row, so it is recorded per row.
    final marks = <String, UnsentWrite>{ ...state.unsent };

    for ( final id in ids ) {
      try {
        await _writes.transition( id: id, verb: verb( id ) );
        applied++;
        marks.remove( id );   // it landed; any older mark on this row is spent
      } on Object catch ( e ) {
        firstFailure ??= e;
        if ( isTransportFailure( e ) ) {
          marks[ id ] = UnsentWrite(
            taskId : id,
            label  : verbLabel( verb( id ).name ),
            verb   : verb( id ),
          );
        }
      }
    }

    final next     = { ...state.busyFilers }..remove( filer );
    final complete = applied == ids.length;

    emit( state.copyWith(
      busyFilers       : next,
      // ⚠️ THE NOTICE SURVIVES THE REFETCH BELOW. Parking it in `error` would have it
      // cleared by the very refresh this batch schedules.
      batchNotice      : complete
          ? null
          : '${ids.length - applied} of ${ids.length} rows did not move '
            '(${_writeError( firstFailure! )}) — the rest did',
      clearBatchNotice : complete,
      unsent           : marks,
      reasons          : complete
          ? ( { ...state.reasons }..remove( filer ) )
          : state.reasons,
    ) );

    add( const HoldingAreaRefreshRequested() );
  }

  /// The FIELD door — priority and owner only, never status. Status is [_onRowVerb].
  ///
  /// 🔴 REFETCH RATHER THAN REPAINT LOCALLY, for the reason [_onRowVerb] already gives:
  /// a priority the server refused, or accepted only as a 202, would otherwise sit on
  /// screen looking applied.
  Future<void> _onField(
    HoldingAreaFieldChanged event,
    Emitter<HoldingAreaState> emit,
  ) async {
    try {
      await _writes.patchFields(
        id           : event.id,
        priority     : event.priority,
        ownerPersona : event.ownerPersona,
      );
    } on Object catch ( e ) {
      // ⚠️ THE SAME CHANNEL A FAILED ROW VERB USES, AND DELIBERATELY NOT `error`. A
      // fetch error is answered by the next fetch — which this handler is about to
      // schedule — so a field failure parked there would be wiped before the operator
      // read it. That is the bug `batchNotice` was split out for.
      //
      // 🔴 AND THE FIELD DOOR IS REMEMBERED TOO (G6). A priority edit lost to a dropped
      // signal is the operator's act exactly as a verb is. This handler arrived with
      // Chloé's half of the pane while this row was in flight, so it is wired here
      // rather than left as the one write on either task pane that forgets.
      emit( state.copyWith(
        batchNotice : _writeError( e ),
        unsent      : isTransportFailure( e )
            ? _withUnsent( UnsentWrite(
                taskId       : event.id,
                label        : event.priority != null ? 'Priority' : 'Owner',
                priority     : event.priority,
                ownerPersona : event.ownerPersona,
              ) )
            : state.unsent,
      ) );
      return;
    }
    if ( state.unsent.containsKey( event.id ) ) {
      emit( state.copyWith( unsent: { ...state.unsent }..remove( event.id ) ) );
    }
    add( const HoldingAreaRefreshRequested() );
  }

  /// The live persona roster for the owner control.
  ///
  /// 🔴 EVERY FAILURE COLLAPSES TO AN EMPTY ROSTER AND NONE OF THEM PAINTS AN ERROR.
  /// This is a courtesy read on a pane about held work: an arbiter that cannot be
  /// reached is a reason the owner dropdown offers only the current owner, not a reason
  /// to tell the operator their holding area is broken.
  ///
  /// ⚠️ AND IT MUST NOT THROW PAST THE HANDLER EITHER. An unhandled error inside a bloc
  /// handler surfaces through `onError` and can take the bloc down — turning "the
  /// arbiter is unreachable" into "the Holding Area stopped polling".
  Future<void> _onRoster(
    HoldingAreaRosterRequested event,
    Emitter<HoldingAreaState> emit,
  ) async {
    final fleet = _fleet;
    if ( fleet == null ) return;

    try {
      final composite = await fleet.fetchState();
      emit( state.copyWith( reassignTargets: activeReassignTargets( composite ) ) );
    } on FleetApiException {
      // The phone cannot see the fleet. The held set is fine; the roster is empty.
    } on DioException {
      // Includes the cancelled case, which is the lifecycle rule working.
    }
  }

  /// Fold or unfold one persona's rows.
  ///
  /// ⚠️ ONE GROUP AT A TIME, AND OPENING ONE DOES NOT CLOSE THE OTHERS. An accordion that
  /// allows a single open section is a different control, and it would make comparing two
  /// personas' held work impossible without scrolling back and forth. Rick asked to
  /// *"toggle or collapse each individual persona's items"* — each, independently.
  void _onGroupToggled( HoldingAreaGroupToggled event, Emitter<HoldingAreaState> emit ) {
    final next = Set<String>.from( state.expanded );
    if ( !next.remove( event.filer ) ) next.add( event.filer );
    emit( state.copyWith( expanded: next ) );
  }

  void _onReasonChanged( HoldingAreaReasonChanged event, Emitter<HoldingAreaState> emit ) {
    emit( state.copyWith(
      reasons      : { ...state.reasons, event.filer: event.reason },
      // Typing clears the complaint. Leaving it up while the box fills would make the
      // pane argue with what the operator can see.
      reasonErrors : { ...state.reasonErrors }..remove( event.filer ),
    ) );
  }

  /// The operator-facing text for a failed write.
  ///
  /// 🔴 THE 202 CASE GETS ITS OWN SENTENCE, AND IT MUST NOT SAY "FAILED".
  /// [TaskAwaitingApprovalException] means the server ACCEPTED the request and did not
  /// apply it. Reporting that as a failure would be wrong in the one direction that
  /// causes harm: the natural response to a failure is to press again, and pressing
  /// again files a second approval ticket for a change already waiting on one.
  String _writeError( Object e ) {
    if ( e is TaskAwaitingApprovalException ) {
      return 'awaiting human approval — the request was accepted, the change has not '
             'happened yet, and pressing again files a second ticket';
    }
    if ( e is TaskWriteException ) return e.message;
    if ( e is DioException ) return e.message ?? 'write failed';
    return e.toString();
  }

  @override
  Future<void> close() {
    _connectivitySub?.cancel();
    _connectivitySub = null;
    return super.close();
  }
}
