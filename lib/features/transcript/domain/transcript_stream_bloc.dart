import 'dart:async';

import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_constants.dart';
import '../../fleet/domain/pane_visibility_mixin.dart';
import '../data/transcript_models.dart';
import '../data/transcript_repository.dart';
import 'transcript_frame_router.dart';

// ---------------------------------------------------------------------------
// Events
// ---------------------------------------------------------------------------

sealed class TranscriptEvent extends Equatable {
  const TranscriptEvent();
  @override
  List<Object?> get props => const [];
}

/// A REST read landed. `replace` distinguishes the two reasons for one:
/// a fresh open or an epoch change (replace) from a catch-up or gap repair (append).
class TranscriptBacklogLoaded extends TranscriptEvent {
  final TranscriptBacklog backlog;
  final bool              replace;
  const TranscriptBacklogLoaded( this.backlog, { this.replace = false } );
  @override
  List<Object?> get props => [ backlog.offset, backlog.nextOffset, replace ];
}

/// A backwards page landed (C-7).
class TranscriptEarlierLoaded extends TranscriptEvent {
  final TranscriptBacklog backlog;
  const TranscriptEarlierLoaded( this.backlog );
  @override
  List<Object?> get props => [ backlog.offset, backlog.blocks.length ];
}

/// A socket chunk arrived.
class TranscriptAppendReceived extends TranscriptEvent {
  final TranscriptAppend frame;
  const TranscriptAppendReceived( this.frame );
  @override
  List<Object?> get props => [ frame.offset, frame.nextOffset, frame.fileEpoch ];
}

/// A socket state frame arrived.
class TranscriptStateReceived extends TranscriptEvent {
  final TranscriptStateFrame frame;
  const TranscriptStateReceived( this.frame );
  @override
  List<Object?> get props => [ frame.state, frame.fileEpoch ];
}

/// The buffer and offset are dropped: an epoch changed, or the server refused our epoch.
class TranscriptCleared extends TranscriptEvent {
  final String? newEpoch;
  const TranscriptCleared( this.newEpoch );
  @override
  List<Object?> get props => [ newEpoch ];
}

/// A retryable failure. Not a refusal.
class TranscriptFailed extends TranscriptEvent {
  final String message;
  const TranscriptFailed( this.message );
  @override
  List<Object?> get props => [ message ];
}

/// The server will not serve this console. **Terminal.**
class TranscriptRefusalReceived extends TranscriptEvent {
  final String? reason;
  const TranscriptRefusalReceived( this.reason );
  @override
  List<Object?> get props => [ reason ];
}

/// One truncated block's full text came back from REST.
class TranscriptBlockFilled extends TranscriptEvent {
  final int             index;
  final TranscriptBlock full;
  const TranscriptBlockFilled( this.index, this.full );
  @override
  List<Object?> get props => [ index, full.text.length ];
}

class TranscriptLoadingChanged extends TranscriptEvent {
  final bool loading;
  final bool loadingEarlier;
  const TranscriptLoadingChanged( { this.loading = false, this.loadingEarlier = false } );
  @override
  List<Object?> get props => [ loading, loadingEarlier ];
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class TranscriptViewState extends Equatable {
  /// Oldest first. The screen reverses for display (OSQ-9 ruled B: live end at the bottom).
  final List<TranscriptBlock> blocks;

  final String? fileEpoch;

  /// 🔴 THE SEQUENCE CURSOR. §3: "`offset` is the sequence number… `next_offset` always
  /// lands at the end of a complete line." A chunk whose `offset` is not this value has a
  /// gap in front of it.
  final int? lastNextOffset;

  /// The oldest offset held, for "Load earlier" to page back from.
  final int? oldestOffset;

  /// The backwards pager has reached the start of this epoch, so it hides (C-7).
  final bool atEpochStart;

  final bool loading;
  final bool loadingEarlier;

  /// A retryable failure. The console shows it and keeps its buffer.
  final String? error;

  /// 🔴 TERMINAL AND NOT A KIND OF ERROR. §5 (F-Clayton-C6): a refused watch "shows a static
  /// 'Console not available for this session' message with the server's reason if one is
  /// given, keeps no buffer, sends no further watch, **does not retry**, and offers only
  /// Back. No spinner, no retry loop." Folding it into [error] would let a foreground return
  /// or an `auth_success` re-arm it, which C5.21's negative control fails on.
  final bool    refused;
  final String? refusedReason;

  /// How many REST repairs this bloc has issued. C5.1 and C5.6 assert on it, and C5.6's
  /// control is a clean sequence where it must stay at zero.
  final int repairFetches;

  const TranscriptViewState( {
    this.blocks         = const [],
    this.fileEpoch,
    this.lastNextOffset,
    this.oldestOffset,
    this.atEpochStart   = false,
    this.loading        = false,
    this.loadingEarlier = false,
    this.error,
    this.refused        = false,
    this.refusedReason,
    this.repairFetches  = 0,
  } );

  /// Total bytes held, by the shared size definition (C8).
  int get bufferBytes =>
      blocks.fold( 0, ( sum, b ) => sum + b.sizeBytes );

  TranscriptViewState copyWith( {
    List<TranscriptBlock>? blocks,
    String? fileEpoch,
    int?    lastNextOffset,
    int?    oldestOffset,
    bool?   atEpochStart,
    bool?   loading,
    bool?   loadingEarlier,
    String? error,
    bool    clearError = false,
    bool?   refused,
    String? refusedReason,
    int?    repairFetches,
  } ) {
    return TranscriptViewState(
      blocks         : blocks         ?? this.blocks,
      fileEpoch      : fileEpoch      ?? this.fileEpoch,
      lastNextOffset : lastNextOffset ?? this.lastNextOffset,
      oldestOffset   : oldestOffset   ?? this.oldestOffset,
      atEpochStart   : atEpochStart   ?? this.atEpochStart,
      loading        : loading        ?? this.loading,
      loadingEarlier : loadingEarlier ?? this.loadingEarlier,
      error          : clearError ? null : ( error ?? this.error ),
      refused        : refused        ?? this.refused,
      refusedReason  : refusedReason  ?? this.refusedReason,
      repairFetches  : repairFetches  ?? this.repairFetches,
    );
  }

  @override
  List<Object?> get props => [
    blocks, fileEpoch, lastNextOffset, oldestOffset, atEpochStart,
    loading, loadingEarlier, error, refused, refusedReason, repairFetches,
  ];
}

// ---------------------------------------------------------------------------
// Bloc
// ---------------------------------------------------------------------------

/// One watched seat's console.
///
/// 🔴 ROUTE-SCOPED, NEVER APP-ROOT (C1). It is built by the Live Console route's own
/// `BlocProvider( create: )` and closed when that route pops — which is what sends
/// `cc_transcript_unwatch` and cancels the in-flight fetch. An app-root instance would keep
/// its watch open after the operator walked away, and C5.11's negative control is exactly
/// that: register it app-root and the test must fail.
///
/// It mixes in [PaneVisibilityMixin] and **not** `PanePollingMixin`: a WebSocket pushes to
/// this screen, so there is nothing to poll. That asymmetry is why the mixin was split.
class TranscriptStreamBloc extends Bloc<TranscriptEvent, TranscriptViewState>
    with PaneVisibilityMixin<TranscriptEvent, TranscriptViewState> {
  /// The seat's full `stable_session_id` (§3's `cc_session_id`).
  final String ccSessionId;

  final TranscriptRepository   _repo;
  final TranscriptFrameRouter  _router;

  /// How watch and unwatch reach the server.
  ///
  /// ⚠️ A FUNCTION, NOT THE SERVICE. `WebSocketService` is a singleton with private state,
  /// and what this bloc needs from it is one verb — `sendMessage` (`:375`). Injecting the
  /// verb is the same seam `lifecycleStream` and `isMeteredConnection` already use, and for
  /// the same reason: a hard singleton cannot be faked, so what is injectable is the thing
  /// the consumer actually uses. The "enhanced" service is legacy and stays untouched (F6).
  final Future<void> Function( Map<String, dynamic> frame ) _send;

  /// The ring's cap in bytes.
  ///
  /// 🔴 READ FROM CONFIG, NEVER HARD-CODED (F-Clayton-C9), and provisional pending OSQ-5.
  /// It is a constructor parameter so C5.3 can assert the eviction RULE against a small cap
  /// instead of manufacturing 256 KB of fixture — a test that has to build a quarter of a
  /// megabyte to exercise a boundary usually ends up asserting the fixture instead.
  final int ringBytes;

  StreamSubscription<TranscriptAppend>? _appendSub;
  StreamSubscription<TranscriptStateFrame>? _stateSub;

  TranscriptStreamBloc( {
    required this.ccSessionId,
    required TranscriptRepository repository,
    required TranscriptFrameRouter router,
    required Future<void> Function( Map<String, dynamic> ) send,
    this.ringBytes = AppConstants.transcriptRingBytes,
  } )  : _repo   = repository,
        _router  = router,
        _send    = send,
        super( const TranscriptViewState() ) {

    on<TranscriptLoadingChanged>( ( e, emit ) => emit( state.copyWith(
      loading        : e.loading,
      loadingEarlier : e.loadingEarlier,
    ) ) );

    on<TranscriptBacklogLoaded>( _onBacklog );
    on<TranscriptEarlierLoaded>( _onEarlier );
    on<TranscriptAppendReceived>( _onAppend );
    on<TranscriptStateReceived>( _onStateFrame );
    on<TranscriptCleared>( ( e, emit ) => emit( TranscriptViewState(
      fileEpoch     : e.newEpoch,
      loading       : true,
      repairFetches : state.repairFetches,
    ) ) );
    on<TranscriptFailed>( ( e, emit ) => emit( state.copyWith(
      error          : e.message,
      loading        : false,
      loadingEarlier : false,
    ) ) );
    on<TranscriptRefusalReceived>( ( e, emit ) => emit( TranscriptViewState(
      refused       : true,
      refusedReason : e.reason,
      repairFetches : state.repairFetches,
    ) ) );
    on<TranscriptBlockFilled>( ( e, emit ) {
      if ( e.index < 0 || e.index >= state.blocks.length ) return;
      final next = [ ...state.blocks ]..[ e.index ] = e.full;
      emit( state.copyWith( blocks: next ) );
    } );
  }

  /// Subscribe to this seat's frames and start the visibility machine.
  ///
  /// ⚠️ THE SUBSCRIPTION IS SEPARATE FROM THE WATCH, and both are separate from
  /// `startVisibility()`. Subscribing to the router costs nothing and must happen before the
  /// first watch, or a chunk that arrives between the two is lost. The WATCH is sent by
  /// `onActiveChanged`, once the route says the screen is on view.
  void start() {
    _appendSub ??= _router.appendsFor( ccSessionId )
        .listen( ( f ) => add( TranscriptAppendReceived( f ) ) );
    _stateSub  ??= _router.statesFor( ccSessionId )
        .listen( ( f ) => add( TranscriptStateReceived( f ) ) );
    startVisibility();
  }

  /// The visibility hook — §5's catch-up-then-re-watch two-step.
  ///
  /// 🔴 THE CATCH-UP IS HERE AND NOT IN `start()`, WHICH IS THE WHOLE POINT OF C-2. A
  /// catch-up placed in the subscribe-time verb fires ONCE and passes a test that returns to
  /// the foreground once. `_reconcile` calls this on EVERY transition, so the catch-up runs
  /// on every return from the background — which is what C5.7 asserts with **two** returns
  /// in one test.
  @override
  void onActiveChanged( { required bool active, required bool refreshNow } ) {
    if ( !active ) {
      // The mixin has already cancelled the in-flight fetch. What is left is telling the
      // server to stop sending: §5, "on screen close, and when the app goes to the
      // background: cc_transcript_unwatch".
      _sendUnwatch();
      return;
    }
    if ( refreshNow ) _catchUpThenWatch();
  }

  /// On reconnect (`auth_success`): watch the open screen again from its last offset and
  /// epoch.
  ///
  /// 🔴 THIS IS THE STALE-EPOCH PATH, AND A PHONE IS THE CLIENT MOST LIKELY TO HIT IT (§5,
  /// T15). If the seat cleared while the phone was away, the watch names an epoch that is no
  /// longer current and the server answers `epoch_mismatch` rather than silently rebasing —
  /// a rebase "would hand the client the whole new file labelled as its own continuation".
  void onReconnected() {
    if ( state.refused ) {
      // C5.21: no further watch after a refusal, including across a reconnect.
      debugPrint( '[Transcript] auth_success ignored — this console was refused' );
      return;
    }
    if ( !isPaneActive ) return;
    _catchUpThenWatch();
  }

  /// "Load earlier" — a page backwards from the oldest block held (C-7).
  Future<void> loadEarlier() async {
    if ( state.refused || state.atEpochStart || state.loadingEarlier ) return;

    final from = state.oldestOffset;
    if ( from == null ) return;

    final token = claimRequest();
    if ( token == null ) return;

    add( const TranscriptLoadingChanged( loadingEarlier: true ) );
    try {
      final page = await _repo.fetchBefore(
        ccSessionId  : ccSessionId,
        beforeOffset : from,
        cancelToken  : token,
      );
      if ( isClosed ) return;
      add( TranscriptEarlierLoaded( page ) );
    } on TranscriptRefused catch ( e ) {
      if ( !isClosed ) add( TranscriptRefusalReceived( e.reason ) );
    } on DioException catch ( e ) {
      if ( e.type != DioExceptionType.cancel ) rethrow;
      // The route closed mid-page. Nothing to say and nobody to say it to.
    } on TranscriptApiException catch ( e ) {
      if ( !isClosed ) add( TranscriptFailed( e.message ) );
    } finally {
      releaseRequest( token );
      if ( !isClosed ) add( const TranscriptLoadingChanged() );
    }
  }

  /// Fetch one server-truncated block's full text.
  ///
  /// 🔴 EXACTLY ONE REST FETCH, AND THE ANSWER REPLACES THE BLOCK (C5.19). Expanding from
  /// memory would re-show the truncated prefix and call it the full text — which is why
  /// that row's control has the stub return text that DIFFERS from the prefix.
  Future<void> expandTruncated( int index ) async {
    if ( index < 0 || index >= state.blocks.length ) return;

    final block = state.blocks[ index ];
    if ( !block.truncated ) return;

    final offset = block.offset;
    if ( offset == null ) {
      debugPrint( '[Transcript] truncated block $index has no offset — cannot fetch' );
      return;
    }

    final token = claimRequest();
    if ( token == null ) return;

    try {
      final full = await _repo.fetchFullBlock(
        ccSessionId : ccSessionId,
        blockOffset : offset,
        cancelToken : token,
      );
      if ( isClosed ) return;

      final replacement = full.blocks.isNotEmpty ? full.blocks.first : null;
      if ( replacement == null ) return;

      // 🔴 THE FULL TEXT IS MERGED ONTO THE **ORIGINAL** BLOCK, NOT SUBSTITUTED FOR IT, and
      // the difference is not cosmetic. A REST read for one block's full text answers with
      // the TEXT; it is not obliged to repeat that block's `offset` or its tool `name`, and
      // the fake proved it — my first version took the response's block wholesale, lost the
      // offset, and the screen's offset-keyed element was rebuilt from scratch. The block
      // re-collapsed and hid the text the operator had just waited on. C5.19 caught it.
      //
      // ⇒ Identity comes from the block we already have; only the text and the truncation
      // flag come from the server. `truncated: false` so the marker goes and a second tap
      // does not re-fetch.
      add( TranscriptBlockFilled(
        index,
        block.withText( replacement.text, truncated: false ),
      ) );
    } on DioException catch ( e ) {
      if ( e.type != DioExceptionType.cancel ) rethrow;
    } on TranscriptRefused catch ( e ) {
      if ( !isClosed ) add( TranscriptRefusalReceived( e.reason ) );
    } on TranscriptApiException catch ( e ) {
      if ( !isClosed ) add( TranscriptFailed( e.message ) );
    } finally {
      releaseRequest( token );
    }
  }

  // -------------------------------------------------------------------------
  // The wire
  // -------------------------------------------------------------------------

  /// REST catch-up, then watch from where that response ended.
  ///
  /// Ensures:
  ///     - on a FIRST open, `tail_bytes` — the LAST ~64 KB (ruling Q6). **Never
  ///       `since_offset=0`**, which returns the FIRST 64 KB and would open the screen at
  ///       the top of the transcript (§2 item 4, A2.9; C5.16)
  ///     - on a resume, `since_offset` from [TranscriptViewState.lastNextOffset]
  ///     - the watch's `from_offset` is the RESPONSE's `next_offset`, so the server starts
  ///       exactly where the backlog stopped — §3: "the server starts where the client
  ///       asked… never silently starts at the current end of the file"
  ///     - a refusal is terminal and no watch is sent
  ///     - `forceTail` overrides the resume branch, for the one case where `state` cannot
  ///       be trusted to answer it
  Future<void> _catchUpThenWatch( { bool forceTail = false } ) async {
    if ( state.refused ) return;

    final token = claimRequest();
    if ( token == null ) return;

    // 🔴 `forceTail` EXISTS BECAUSE A REDUCER'S `add()` HAS NOT LANDED YET WHEN THE NEXT
    // MICROTASK RUNS, AND THAT COST ME FOUR RED TESTS. An epoch change adds
    // `TranscriptCleared` — which drops `lastNextOffset` — and then schedules this. But the
    // bloc's event queue processes `TranscriptCleared` asynchronously, so reading
    // `state.lastNextOffset` here still sees the OLD epoch's cursor and takes the resume
    // branch: a `since_offset` read against a file that no longer exists, at an offset that
    // means nothing in the new one. The caller knows it cleared; the state does not know yet.
    // So the caller says so, rather than this method inferring it from a value in flight.
    final resuming = !forceTail && state.lastNextOffset != null;
    if ( !resuming ) add( const TranscriptLoadingChanged( loading: true ) );

    try {
      final backlog = resuming
          ? await _repo.fetchSince(
              ccSessionId : ccSessionId,
              sinceOffset : state.lastNextOffset!,
              cancelToken : token,
            )
          : await _repo.fetchTail(
              ccSessionId : ccSessionId,
              cancelToken : token,
            );

      if ( isClosed ) return;
      add( TranscriptBacklogLoaded( backlog, replace: !resuming ) );

      await _sendWatch(
        fromOffset : backlog.nextOffset ?? state.lastNextOffset,
        fileEpoch  : backlog.fileEpoch ?? state.fileEpoch,
      );
    } on TranscriptRefused catch ( e ) {
      if ( !isClosed ) add( TranscriptRefusalReceived( e.reason ) );
    } on DioException catch ( e ) {
      if ( e.type != DioExceptionType.cancel ) rethrow;
      debugPrint( '[Transcript] catch-up cancelled — the route went away' );
    } on TranscriptApiException catch ( e ) {
      if ( !isClosed ) add( TranscriptFailed( e.message ) );
    } finally {
      releaseRequest( token );
      if ( !isClosed && !resuming ) add( const TranscriptLoadingChanged() );
    }
  }

  /// Repair a gap: fetch from `last_next_offset` and append.
  ///
  /// §3's gap rule: "if `chunk.offset != last_next_offset`, drop the chunk and fetch over
  /// REST from `last_next_offset`."
  Future<void> _repairGap( int from ) async {
    final token = claimRequest();
    if ( token == null ) return;

    try {
      final repair = await _repo.fetchSince(
        ccSessionId : ccSessionId,
        sinceOffset : from,
        cancelToken : token,
      );
      if ( !isClosed ) add( TranscriptBacklogLoaded( repair ) );
    } on DioException catch ( e ) {
      if ( e.type != DioExceptionType.cancel ) rethrow;
    } on TranscriptRefused catch ( e ) {
      if ( !isClosed ) add( TranscriptRefusalReceived( e.reason ) );
    } on TranscriptApiException catch ( e ) {
      if ( !isClosed ) add( TranscriptFailed( e.message ) );
    } finally {
      releaseRequest( token );
    }
  }

  Future<void> _sendWatch( { int? fromOffset, String? fileEpoch } ) async {
    try {
      await _send( {
        "type"          : AppConstants.eventTranscriptWatch,
        "cc_session_id" : ccSessionId,
        "from_offset"   : fromOffset ?? 0,
        // §3: `file_epoch` is nullable — null means "whatever file is current", and the
        // server answers with the epoch it chose. So a FIRST watch needs no prior REST call.
        "file_epoch"    : fileEpoch,
      } );
    } on Object catch ( e ) {
      // A disconnected socket is not a refusal and not a reason to blank the backlog we
      // just fetched. `auth_success` will bring us back through `onReconnected`.
      debugPrint( '[Transcript] watch not sent (${ e.runtimeType }) — awaiting reconnect' );
    }
  }

  void _sendUnwatch() {
    _send( {
      "type"          : AppConstants.eventTranscriptUnwatch,
      "cc_session_id" : ccSessionId,
    } ).catchError( ( Object e ) {
      // Unwatching a socket that is already gone is a no-op, not a failure: the server
      // drops the watcher when the connection closes.
      debugPrint( '[Transcript] unwatch not sent (${ e.runtimeType }) — socket is gone' );
    } );
  }

  // -------------------------------------------------------------------------
  // Reducers
  // -------------------------------------------------------------------------

  void _onBacklog( TranscriptBacklogLoaded e, Emitter<TranscriptViewState> emit ) {
    final b = e.backlog;

    final blocks = e.replace
        ? [ ...b.blocks ]
        : [ ...state.blocks, ...b.blocks ];

    emit( state.copyWith(
      blocks         : _evict( blocks ),
      fileEpoch      : b.fileEpoch ?? state.fileEpoch,
      lastNextOffset : b.nextOffset ?? state.lastNextOffset,
      oldestOffset   : e.replace
          ? b.offset
          : ( state.oldestOffset ?? b.offset ),
      atEpochStart   : e.replace ? b.atStart : state.atEpochStart,
      loading        : false,
      clearError     : true,
    ) );
  }

  /// A backwards page goes on the FRONT, and the cursor does not move.
  ///
  /// ⚠️ `lastNextOffset` IS DELIBERATELY UNTOUCHED HERE. It is the LIVE end's cursor, and a
  /// page of older content must not rewind it — doing so would make the next chunk look like
  /// a gap and fire a repair fetch for content already held.
  void _onEarlier( TranscriptEarlierLoaded e, Emitter<TranscriptViewState> emit ) {
    final b = e.backlog;

    emit( state.copyWith(
      // 🔴 EVICT FROM THE **LIVE** END WOULD BE WRONG HERE AND RIGHT EVERYWHERE ELSE, so
      // the older page is trimmed instead: a "Load earlier" that evicted the newest blocks
      // to make room would scroll the live end out of the buffer the operator is following.
      blocks         : _evictOldestFirst( [ ...b.blocks, ...state.blocks ] ),
      oldestOffset   : b.offset ?? state.oldestOffset,
      atEpochStart   : b.atStart,
      loadingEarlier : false,
      clearError     : true,
    ) );
  }

  void _onAppend( TranscriptAppendReceived e, Emitter<TranscriptViewState> emit ) {
    final f = e.frame;

    if ( state.refused ) return;

    // 🔴 EPOCH FIRST, BEFORE THE GAP CHECK. A `/clear` on the watched seat changes the
    // epoch while `cc_session_id` stays put, and the new file's offsets are unrelated to
    // ours — so an offset comparison across an epoch boundary is meaningless, and treating
    // it as a gap would issue a repair fetch against the WRONG file.
    final incoming = f.fileEpoch;
    if ( incoming != null && state.fileEpoch != null && incoming != state.fileEpoch ) {
      debugPrint(
        '[Transcript] epoch changed ${ state.fileEpoch } -> $incoming — clearing' );
      add( TranscriptCleared( incoming ) );
      _catchUpAfterEpochChange();
      return;
    }

    final expected = state.lastNextOffset;
    final offset   = f.offset;

    if ( expected != null && offset != null && offset != expected ) {
      // §3's gap rule. The chunk is DROPPED — not appended and then repaired, which would
      // render out-of-order content for one frame and leave it in the buffer.
      debugPrint( '[Transcript] gap: chunk at $offset, expected $expected — repairing' );
      emit( state.copyWith( repairFetches: state.repairFetches + 1 ) );
      _repairGap( expected );
      return;
    }

    emit( state.copyWith(
      blocks         : _evict( [ ...state.blocks, ...f.blocks ] ),
      fileEpoch      : incoming ?? state.fileEpoch,
      lastNextOffset : f.nextOffset ?? state.lastNextOffset,
      oldestOffset   : state.oldestOffset ?? f.offset,
      clearError     : true,
    ) );
  }

  void _onStateFrame( TranscriptStateReceived e, Emitter<TranscriptViewState> emit ) {
    final f = e.frame;

    switch ( f.state ) {
      case TranscriptStreamState.refused:
        emit( TranscriptViewState(
          refused       : true,
          refusedReason : f.reason,
          repairFetches : state.repairFetches,
        ) );

      case TranscriptStreamState.epochMismatch:
      case TranscriptStreamState.rotated:
        // 🔴 CLEAR AND RE-FETCH, NEVER APPEND. §3 (T15): the server refuses a stale epoch
        // rather than rebasing, precisely so the client can tell the difference. Appending
        // here would splice a different file onto this one.
        debugPrint( '[Transcript] ${ f.rawState } — clearing and re-fetching' );
        add( TranscriptCleared( f.fileEpoch ) );
        _catchUpAfterEpochChange();

      case TranscriptStreamState.live:
        emit( state.copyWith(
          fileEpoch  : f.fileEpoch ?? state.fileEpoch,
          clearError : true,
        ) );

      case TranscriptStreamState.ended:
        // The seat is gone. Keep what we have — the operator may still be reading it — and
        // say nothing, because "ended" is not an error.
        debugPrint( '[Transcript] seat ended; buffer kept' );

      case TranscriptStreamState.unknown:
        // A state this client does not know. Do not retry, do not clear, do not guess.
        debugPrint( '[Transcript] unknown state "${ f.rawState }" — ignored' );
    }
  }

  /// After a clear, re-fetch the backlog from the top of the new epoch's live end.
  ///
  /// The `TranscriptCleared` event has already dropped `lastNextOffset`, so
  /// [_catchUpThenWatch] takes its first-open branch — a `tail_bytes` read, which is right:
  /// a new epoch has a new live end.
  void _catchUpAfterEpochChange() {
    // The in-flight token belongs to a fetch against the OLD epoch; its answer must not land
    // in the new buffer.
    cancelInFlight( 'epoch changed' );
    scheduleMicrotask( () {
      // `forceTail: true`, NOT a read of `state`: see the comment in `_catchUpThenWatch`.
      // A new epoch has a new live end, so the right read is a tail read regardless of what
      // cursor the old epoch left behind.
      if ( !isClosed ) _catchUpThenWatch( forceTail: true );
    } );
  }

  // -------------------------------------------------------------------------
  // The ring
  // -------------------------------------------------------------------------

  /// Trim to [ringBytes], oldest first.
  ///
  /// 🔴 THE CAP IS IN BYTES AND THE EVICTION IS BY COUNT, WHICH IS THE APP'S EXISTING IDIOM
  /// PLUS THE ONE NEW PART. `monitoring_models.dart:141-142` already evicts with
  /// `removeAt( 0 )` past a limit; byte accounting is what C8 adds, and it uses
  /// [TranscriptBlock.sizeBytes] — the UTF-8 length after server truncation — so "never
  /// exceeds its cap" means the same thing here as on the server.
  ///
  /// ⚠️ ONE BLOCK LARGER THAN THE WHOLE RING IS KEPT, NOT DROPPED. Evicting it would leave
  /// an empty console showing nothing while the server had sent something, which is worse
  /// than briefly exceeding a provisional cap. Named because it is the one case where the
  /// buffer can be over [ringBytes].
  List<TranscriptBlock> _evict( List<TranscriptBlock> blocks ) =>
      _evictOldestFirst( blocks );

  List<TranscriptBlock> _evictOldestFirst( List<TranscriptBlock> blocks ) {
    if ( blocks.isEmpty ) return blocks;

    var total = blocks.fold( 0, ( int sum, b ) => sum + b.sizeBytes );
    if ( total <= ringBytes ) return blocks;

    final out = [ ...blocks ];
    while ( out.length > 1 && total > ringBytes ) {
      total -= out.first.sizeBytes;
      out.removeAt( 0 );
    }
    return out;
  }

  @override
  Future<void> close() {
    // 🔴 THE UNWATCH GOES OUT BEFORE THE SUBSCRIPTIONS DIE, or the server keeps streaming to
    // a client that has stopped listening. C5.11 asserts the fake socket RECORDED an
    // unwatch, which is only true if this runs.
    _sendUnwatch();

    _appendSub?.cancel();
    _stateSub?.cancel();
    _appendSub = null;
    _stateSub  = null;
    _router.release( ccSessionId );

    // `super.close()` reaches PaneVisibilityMixin, which cancels the in-flight fetch and the
    // lifecycle subscription (C5.12).
    return super.close();
  }
}
