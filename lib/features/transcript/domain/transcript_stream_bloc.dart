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

/// An input to [TranscriptStreamBloc].
sealed class TranscriptEvent extends Equatable {
  /// Creates an event.
  const TranscriptEvent();
  @override
  List<Object?> get props => const [];
}

/// A REST read landed.
///
/// `replace` separates a fresh open or an epoch change (replace) from a catch-up or gap
/// repair (append).
class TranscriptBacklogLoaded extends TranscriptEvent {
  /// The response body.
  final TranscriptBacklog backlog;

  /// True when the buffer is replaced, false when the blocks are appended.
  final bool              replace;

  /// Creates the event.
  const TranscriptBacklogLoaded( this.backlog, { this.replace = false } );
  @override
  List<Object?> get props => [ backlog.offset, backlog.nextOffset, replace ];
}

/// A backwards page landed.
class TranscriptEarlierLoaded extends TranscriptEvent {
  /// The page of older blocks.
  final TranscriptBacklog backlog;

  /// Creates the event.
  const TranscriptEarlierLoaded( this.backlog );
  @override
  List<Object?> get props => [ backlog.offset, backlog.blocks.length ];
}

/// A socket chunk arrived.
class TranscriptAppendReceived extends TranscriptEvent {
  /// The chunk.
  final TranscriptAppend frame;

  /// Creates the event.
  const TranscriptAppendReceived( this.frame );
  @override
  List<Object?> get props => [ frame.offset, frame.nextOffset, frame.fileEpoch ];
}

/// A socket state frame arrived.
class TranscriptStateReceived extends TranscriptEvent {
  /// The state frame.
  final TranscriptStateFrame frame;

  /// Creates the event.
  const TranscriptStateReceived( this.frame );
  @override
  List<Object?> get props => [ frame.state, frame.fileEpoch ];
}

/// The buffer and offset are dropped: an epoch changed, or the server refused our epoch.
class TranscriptCleared extends TranscriptEvent {
  /// The new epoch, or null when none was named.
  final String? newEpoch;

  /// Creates the event.
  const TranscriptCleared( this.newEpoch );
  @override
  List<Object?> get props => [ newEpoch ];
}

/// A retryable failure; not a refusal.
class TranscriptFailed extends TranscriptEvent {
  /// The failure text.
  final String message;

  /// Creates the event.
  const TranscriptFailed( this.message );
  @override
  List<Object?> get props => [ message ];
}

/// The server will not serve this console; the refusal is terminal.
class TranscriptRefusalReceived extends TranscriptEvent {
  /// The server's reason, when it gave one.
  final String? reason;

  /// Creates the event.
  const TranscriptRefusalReceived( this.reason );
  @override
  List<Object?> get props => [ reason ];
}

/// One truncated block's full text came back from REST.
class TranscriptBlockFilled extends TranscriptEvent {
  /// The index of the block in the buffer.
  final int             index;

  /// The block with its full text.
  final TranscriptBlock full;

  /// Creates the event.
  const TranscriptBlockFilled( this.index, this.full );
  @override
  List<Object?> get props => [ index, full.text.length ];
}

/// The loading flags changed.
class TranscriptLoadingChanged extends TranscriptEvent {
  /// True while the opening read is in flight.
  final bool loading;

  /// True while a "Load earlier" page is in flight.
  final bool loadingEarlier;

  /// Creates the event.
  const TranscriptLoadingChanged( { this.loading = false, this.loadingEarlier = false } );
  @override
  List<Object?> get props => [ loading, loadingEarlier ];
}

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

/// The console's state.
class TranscriptViewState extends Equatable {
  /// The buffered blocks, oldest first.
  ///
  /// The screen reverses them so the live end is at the bottom.
  /// Design: src/docs/decisions/README.md (R-TR-live-end-bottom)
  final List<TranscriptBlock> blocks;

  /// The current epoch of the source file, or null before the first read.
  final String? fileEpoch;

  /// The sequence cursor: the `next_offset` of the last chunk applied.
  ///
  /// A chunk's `offset` is its sequence number, and `next_offset` always lands at the end
  /// of a complete line. A chunk whose `offset` differs from this value has a gap in
  /// front of it.
  final int? lastNextOffset;

  /// The oldest offset held, for "Load earlier" to page back from.
  final int? oldestOffset;

  /// True when the backwards pager has reached the start of this epoch, so it hides.
  final bool atEpochStart;

  /// True while the opening read is in flight.
  final bool loading;

  /// True while a "Load earlier" page is in flight.
  final bool loadingEarlier;

  /// A retryable failure; the console shows it and keeps its buffer.
  final String? error;

  /// True when the server refused this console.
  ///
  /// A refusal is terminal and not a kind of error. The screen shows a static "Console not
  /// available for this session" message with the server's reason if one is given. It keeps
  /// no buffer, sends no further watch, does not retry, and offers only Back. Folding it
  /// into [error] would let a foreground return or an `auth_success` re-arm it.
  final bool    refused;

  /// The server's reason for the refusal, when it gave one.
  final String? refusedReason;

  /// How many REST repairs this bloc has issued; a clean sequence leaves it at zero.
  final int repairFetches;

  /// Creates the state; everything defaults to empty.
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

  /// Total bytes held, by [TranscriptBlock.sizeBytes].
  int get bufferBytes =>
      blocks.fold( 0, ( sum, b ) => sum + b.sizeBytes );

  /// Copies the state with changes; [clearError] drops the error.
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
/// It is route-scoped, never app-root. The Live Console route builds it in its own
/// `BlocProvider( create: )` and closes it when the route pops. That sends
/// `cc_transcript_unwatch` and cancels the in-flight fetch. An app-root instance would
/// keep its watch open after the operator walked away. It mixes in [PaneVisibilityMixin]
/// and not `PanePollingMixin`, because a WebSocket pushes to this screen.
class TranscriptStreamBloc extends Bloc<TranscriptEvent, TranscriptViewState>
    with PaneVisibilityMixin<TranscriptEvent, TranscriptViewState> {
  /// The seat's full `stable_session_id`, sent as `cc_session_id`.
  final String ccSessionId;

  final TranscriptRepository   _repo;
  final TranscriptFrameRouter  _router;

  // How watch and unwatch reach the server. It is a function, not the service:
  // `WebSocketService` is a singleton with private state, and this bloc needs one verb,
  // `sendMessage`. Injecting the verb is the same seam `lifecycleStream` and
  // `isMeteredConnection` use, because a hard singleton cannot be faked. The "enhanced"
  // service is legacy and stays untouched.
  final Future<void> Function( Map<String, dynamic> frame ) _send;

  /// The ring buffer's cap in bytes.
  ///
  /// It is read from config, never hard-coded, and provisional. It is a constructor
  /// parameter so a test can assert the eviction rule against a small cap. Building 256 KB
  /// of fixture instead tends to assert the fixture.
  final int ringBytes;

  StreamSubscription<TranscriptAppend>? _appendSub;
  StreamSubscription<TranscriptStateFrame>? _stateSub;
  StreamSubscription<void>? _reconnectSub;

  // Set synchronously on the first line of [close], before any controller is touched.
  // `isClosed` goes true too late to be useful (see [_addUnlessGone]). `close()` runs before
  // `super.close()`, so a flag set here is the earliest truthful answer to "is this bloc
  // still taking events", with no await in front of it.
  bool _closing = false;

  // True when this bloc can no longer receive an event: the flag above or the framework's
  // own late-arriving signal, never `isClosed` alone.
  bool get _gone => _closing || isClosed;

  /// Creates the console bloc for one seat; call [start] to begin.
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

  /// Subscribes to this seat's frames and starts the visibility machine.
  ///
  /// The subscription is separate from the watch, and both are separate from
  /// `startVisibility()`. Subscribing to the router is free and must happen before the first
  /// watch, or a chunk arriving between the two is lost. The watch itself is sent by
  /// `onActiveChanged` once the route says the screen is on view.
  void start() {
    _appendSub ??= _router.appendsFor( ccSessionId )
        .listen( ( f ) => add( TranscriptAppendReceived( f ) ) );
    _stateSub  ??= _router.statesFor( ccSessionId )
        .listen( ( f ) => add( TranscriptStateReceived( f ) ) );
    // The `auth_success` seam goes through the app-root router, because the dispatcher
    // cannot reach a route-scoped bloc. [onReconnected] stays public and tests call it
    // directly; this only gives it a producer in the running app.
    _reconnectSub ??= _router.reconnects.listen( ( _ ) => onReconnected() );
    startVisibility();
  }

  /// The visibility hook: catch up over REST, then re-watch.
  ///
  /// The catch-up lives here and not in `start()`. A catch-up in the subscribe-time verb
  /// fires once and would pass a test that returns to the foreground once. `_reconcile`
  /// calls this on every transition, so the catch-up runs on every return from the
  /// background, and a test must return twice in one test.
  @override
  void onActiveChanged( { required bool active, required bool refreshNow } ) {
    if ( !active ) {
      // The mixin has already cancelled the in-flight fetch. What is left is telling the
      // server to stop sending, on screen close and when the app goes to the background.
      _sendUnwatch();
      return;
    }
    if ( refreshNow ) _catchUpThenWatch();
  }

  /// On reconnect, watches the open screen again from its last offset and epoch.
  ///
  /// This is the stale-epoch path, and a phone is the client most likely to hit it. If the
  /// seat cleared while the phone was away, the watch names an epoch that is no longer
  /// current. The server then answers `epoch_mismatch` instead of silently rebasing.
  void onReconnected() {
    if ( state.refused ) {
      // No further watch after a refusal, including across a reconnect.
      debugPrint( '[Transcript] auth_success ignored — this console was refused' );
      return;
    }
    if ( !isPaneActive ) return;
    _catchUpThenWatch();
  }

  // Adds an event only if this bloc can still receive one. `isClosed` is not a safe guard
  // for `add()`: it reports the state controller, while `add()` throws on the event
  // controller, and `Bloc.close()` closes the event controller first and the state
  // controller only after pending handlers settle. In that window `isClosed` is still false
  // and `add()` throws anyway; a gated fetch that returned after the route popped threw `Bad
  // state: Cannot add new events after calling close` past the guard. The honest signal is
  // the token. `PaneVisibilityMixin.close()` cancels the in-flight token synchronously before
  // any controller closes, and `_reconcile` cancels it when the pane hides, so a cancelled
  // token means the surface this answer was for is gone. `isClosed` stays as a second belt,
  // because a token is cancelled per request while the bloc can close with none outstanding.
  void _addUnlessGone( CancelToken token, TranscriptEvent event ) {
    if ( token.isCancelled || _gone ) return;
    add( event );
  }

  /// Fetches a page backwards from the oldest block held, for "Load earlier".
  ///
  /// Does nothing after a refusal, at the start of the epoch, while one is loading, or
  /// before any block is held.
  Future<void> loadEarlier() async {
    if ( state.refused || state.atEpochStart || state.loadingEarlier ) return;

    final from = state.oldestOffset;
    if ( from == null ) return;

    final token = claimRequest();
    if ( token == null ) return;

    _addUnlessGone( token, const TranscriptLoadingChanged( loadingEarlier: true ) );
    try {
      final page = await _repo.fetchBefore(
        ccSessionId  : ccSessionId,
        beforeOffset : from,
        cancelToken  : token,
      );
      if ( token.isCancelled || _gone ) return;
      add( TranscriptEarlierLoaded( page ) );
    } on TranscriptRefused catch ( e ) {
      _addUnlessGone( token, TranscriptRefusalReceived( e.reason ) );
    } on DioException catch ( e ) {
      if ( e.type != DioExceptionType.cancel ) rethrow;
      // The route closed mid-page: nothing to say and nobody to say it to.
    } on TranscriptApiException catch ( e ) {
      _addUnlessGone( token, TranscriptFailed( e.message ) );
    } finally {
      releaseRequest( token );
      _addUnlessGone( token, const TranscriptLoadingChanged() );
    }
  }

  /// Fetches one server-truncated block's full text and replaces the block with it.
  ///
  /// It makes exactly one REST fetch. Expanding from memory would re-show the truncated
  /// prefix and call it the full text, so the test stub returns text that differs from the
  /// prefix.
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
      if ( token.isCancelled || _gone ) return;

      final replacement = full.blocks.isNotEmpty ? full.blocks.first : null;
      if ( replacement == null ) return;

      // The full text is merged onto the original block, not substituted for it. A REST read
      // for one block's full text answers with the text and need not repeat that block's
      // `offset` or tool `name`. Taking the response's block wholesale lost the offset, so
      // the screen's offset-keyed element was rebuilt, the block re-collapsed and the text
      // the operator had just waited for was hidden. Identity comes from the block already
      // held and only the text and truncation flag come from the server. `truncated: false`
      // removes the marker, so a second tap does not re-fetch.
      add( TranscriptBlockFilled(
        index,
        block.withText( replacement.text, truncated: false ),
      ) );
    } on DioException catch ( e ) {
      if ( e.type != DioExceptionType.cancel ) rethrow;
    } on TranscriptRefused catch ( e ) {
      _addUnlessGone( token, TranscriptRefusalReceived( e.reason ) );
    } on TranscriptApiException catch ( e ) {
      _addUnlessGone( token, TranscriptFailed( e.message ) );
    } finally {
      releaseRequest( token );
    }
  }

  // -------------------------------------------------------------------------
  // The wire
  // -------------------------------------------------------------------------

  // REST catch-up, then watch from where that response ended.
  //
  // - On a first open it reads `tail_bytes`, the last ~64 KB, never `since_offset=0`, which
  //   returns the first 64 KB and would open the screen at the top of the transcript.
  // - On a resume it reads `since_offset` from [TranscriptViewState.lastNextOffset].
  // - The watch's `from_offset` is the response's `next_offset`, so the server starts exactly
  //   where the backlog stopped and never silently at the current end of the file.
  // - A refusal is terminal and no watch is sent.
  // - `forceTail` overrides the resume branch for the one case where `state` cannot be
  //   trusted to answer it.
  // Design: src/docs/decisions/README.md (R-TR-open-tail)
  Future<void> _catchUpThenWatch( { bool forceTail = false } ) async {
    if ( state.refused ) return;

    final token = claimRequest();
    if ( token == null ) return;

    // `forceTail` exists because a reducer's `add()` has not landed when the next microtask
    // runs. An epoch change adds `TranscriptCleared`, which drops `lastNextOffset`, and then
    // schedules this. The event queue processes `TranscriptCleared` asynchronously, so
    // reading `state.lastNextOffset` here still sees the old epoch's cursor and takes the
    // resume branch: a `since_offset` read against a file that no longer exists. The caller
    // knows it cleared and the state does not yet, so the caller says so.
    final resuming = !forceTail && state.lastNextOffset != null;
    if ( !resuming ) _addUnlessGone( token, const TranscriptLoadingChanged( loading: true ) );

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

      if ( token.isCancelled || _gone ) return;
      add( TranscriptBacklogLoaded( backlog, replace: !resuming ) );

      await _sendWatch(
        fromOffset : backlog.nextOffset ?? state.lastNextOffset,
        fileEpoch  : backlog.fileEpoch ?? state.fileEpoch,
      );
    } on TranscriptRefused catch ( e ) {
      _addUnlessGone( token, TranscriptRefusalReceived( e.reason ) );
    } on DioException catch ( e ) {
      if ( e.type != DioExceptionType.cancel ) rethrow;
      debugPrint( '[Transcript] catch-up cancelled — the route went away' );
    } on TranscriptApiException catch ( e ) {
      _addUnlessGone( token, TranscriptFailed( e.message ) );
    } finally {
      releaseRequest( token );
      if ( !resuming ) _addUnlessGone( token, const TranscriptLoadingChanged() );
    }
  }

  // Repairs a gap: if `chunk.offset != last_next_offset`, the chunk is dropped and the
  // missing range is fetched over REST from `last_next_offset` and appended.
  Future<void> _repairGap( int from ) async {
    final token = claimRequest();
    if ( token == null ) return;

    try {
      final repair = await _repo.fetchSince(
        ccSessionId : ccSessionId,
        sinceOffset : from,
        cancelToken : token,
      );
      _addUnlessGone( token, TranscriptBacklogLoaded( repair ) );
    } on DioException catch ( e ) {
      if ( e.type != DioExceptionType.cancel ) rethrow;
    } on TranscriptRefused catch ( e ) {
      _addUnlessGone( token, TranscriptRefusalReceived( e.reason ) );
    } on TranscriptApiException catch ( e ) {
      _addUnlessGone( token, TranscriptFailed( e.message ) );
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
        // `file_epoch` is nullable: null means whatever file is current, and the server
        // answers with the epoch it chose. A first watch therefore needs no prior REST call.
        "file_epoch"    : fileEpoch,
      } );
      // Only a frame the socket accepted earns an unwatch: if the watch never left, there is
      // no server-side watcher to retire.
      _watching = true;
    } on Object catch ( e ) {
      // A disconnected socket is not a refusal and not a reason to blank the backlog we
      // just fetched. `auth_success` will bring us back through `onReconnected`.
      debugPrint( '[Transcript] watch not sent (${ e.runtimeType }) — awaiting reconnect' );
    }
  }

  // True from the moment a watch frame goes out until the unwatch that retires it, so each
  // watch gets one unwatch. Popping the route runs both `onActiveChanged( active: false )`
  // and `close()`, which each sent an unwatch, so one pop sent two frames; a console closed
  // before it was ever active sent one for a seat never watched. The server drops an unknown
  // watcher, so neither is fatal, but a client that says "stop" twice for one "start" cannot
  // be read from a log.
  bool _watching = false;

  void _sendUnwatch() {
    if ( !_watching ) return;
    _watching = false;

    _send( {
      "type"          : AppConstants.eventTranscriptUnwatch,
      "cc_session_id" : ccSessionId,
    } ).catchError( ( Object e ) {
      // Unwatching a socket that is already gone is a no-op: the server drops the watcher
      // when the connection closes.
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

  // A backwards page goes on the front and the cursor does not move. `lastNextOffset` is
  // the live end's cursor, and a page of older content must not rewind it, or the next chunk
  // would look like a gap and fire a repair for content already held.
  void _onEarlier( TranscriptEarlierLoaded e, Emitter<TranscriptViewState> emit ) {
    final b = e.backlog;

    emit( state.copyWith(
      // The older page is trimmed here, unlike every other path: a "Load earlier" that
      // evicted the newest blocks to make room would scroll the live end out of the buffer
      // the operator is following.
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

    // The epoch is checked before the gap. A `/clear` on the watched seat changes the epoch
    // while `cc_session_id` stays put, and the new file's offsets are unrelated to ours, so
    // an offset comparison across an epoch boundary is meaningless and treating it as a gap
    // would repair against the wrong file.
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
      // The gap rule: the chunk is dropped, not appended and then repaired, which would
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
        // Clear and re-fetch, never append. The server refuses a stale epoch instead of
        // rebasing so the client can tell the difference, and appending would splice a
        // different file onto this one.
        debugPrint( '[Transcript] ${ f.rawState } — clearing and re-fetching' );
        add( TranscriptCleared( f.fileEpoch ) );
        _catchUpAfterEpochChange();

      case TranscriptStreamState.live:
        emit( state.copyWith(
          fileEpoch  : f.fileEpoch ?? state.fileEpoch,
          clearError : true,
        ) );

      case TranscriptStreamState.ended:
        // The seat is gone. Keep what we have, because the operator may still be reading it,
        // and say nothing, because "ended" is not an error.
        debugPrint( '[Transcript] seat ended; buffer kept' );

      case TranscriptStreamState.unknown:
        // A state this client does not know. Do not retry, do not clear, do not guess.
        debugPrint( '[Transcript] unknown state "${ f.rawState }" — ignored' );
    }
  }

  // After a clear, re-fetches the backlog from the live end of the new epoch. The
  // `TranscriptCleared` event has already dropped `lastNextOffset`, so [_catchUpThenWatch]
  // takes its first-open branch, a `tail_bytes` read, which is right: a new epoch has a new
  // live end.
  void _catchUpAfterEpochChange() {
    // The in-flight token belongs to a fetch against the old epoch, and its answer must not
    // land in the new buffer.
    cancelInFlight( 'epoch changed' );
    scheduleMicrotask( () {
      // `forceTail: true`, not a read of `state`; see `_catchUpThenWatch`. A new epoch has a
      // new live end, so the right read is a tail read whatever cursor the old epoch left.
      if ( !_gone ) _catchUpThenWatch( forceTail: true );
    } );
  }

  // -------------------------------------------------------------------------
  // The ring
  // -------------------------------------------------------------------------

  // Trims to [ringBytes], oldest first. The cap is in bytes and the eviction is by count,
  // the app's existing idiom plus byte accounting: `quick_ask_bloc.dart` already evicts
  // with `removeAt( 0 )` past a limit, and this adds [TranscriptBlock.sizeBytes], the UTF-8
  // length after server truncation, so "never exceeds its cap" means the same thing here as
  // on the server. One block larger than the whole ring is kept, not dropped, because
  // evicting it would leave an empty console while the server had sent something. It is the
  // one case where the buffer can exceed [ringBytes].
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
    _closing = true;

    // The unwatch goes out before the subscriptions die, or the server keeps streaming to a
    // client that has stopped listening. A test asserts the fake socket recorded an unwatch.
    _sendUnwatch();

    _appendSub?.cancel();
    _stateSub?.cancel();
    _reconnectSub?.cancel();
    _appendSub    = null;
    _stateSub     = null;
    _reconnectSub = null;
    _router.release( ccSessionId );

    // `super.close()` reaches PaneVisibilityMixin, which cancels the in-flight fetch and the
    // lifecycle subscription.
    return super.close();
  }
}
