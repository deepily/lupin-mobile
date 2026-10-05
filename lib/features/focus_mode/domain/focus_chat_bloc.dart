import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/logging/error_summary.dart';
import '../../../core/logging/logger.dart';
import '../../../services/notification_filter/notification_stop_list.dart';
import '../../../services/push/notification_sender_label.dart';
import '../../../services/tts/speech_intent.dart';
import '../../../services/tts/tts_orchestrator.dart';
import '../../notifications/data/notification_models.dart';
import '../../notifications/data/ask_resolution.dart';
import '../../notifications/data/notification_repository.dart';
import 'focus_chat_event.dart';
import 'focus_chat_state.dart';

/// The state engine for the focus surface, separate from the legacy `NotificationBloc`.
///
/// It holds an insertion-ordered session registry, per-sender windows of the last seven
/// messages, unread counts, the focused sender and the `pendingPromptFor` signal.
/// It is the sole TTS dispatcher: every inbound notification, at every priority, goes to
/// `TtsOrchestrator.enqueueAlways()`, the ungated entry point.
/// The legacy bloc's TTS dispatch is withdrawn at the dependency-injection seam, because
/// `service_locator` no longer injects its optional `tts` dependency.
/// The legacy bloc file is untouched.
class FocusChatBloc extends Bloc<FocusChatEvent, FocusChatState> {
  final NotificationRepository _repo;
  final TtsOrchestrator        _tts;

  /// Window cap per sender: the last seven messages.
  static const int windowCap = 7;

  /// Backfill depth, in hours, passed to `conversation()`: one week.
  ///
  /// It is passed explicitly because the server defaults to a 24-hour window when `hours`
  /// is omitted, unlike `senders()`, where omitted means full history. One week fills a
  /// seven-item window for any recently active sender without unbounded payloads from
  /// chatty ones. The window cap is the real limiter.
  static const int backfillHours = 24 * 7;

  /// Server-side history bound, in hours, for the senders fetch.
  ///
  /// Stale senders (inactive over 24 hours) never arrive. The one-hour Live band is the
  /// client predicate on top ([FocusChatState.isVisible]).
  static const int sendersHours = 24;

  /// Default debounce before a released voice persona counts as an exit.
  ///
  /// `voice_persona_released` carries no `reason`, so a benign seat hand-back and a true
  /// exit look the same on the wire. The release arms this debounce and a re-`assigned`
  /// cancels it.
  static const Duration defaultExitDebounce = Duration( seconds: 4 );

  /// Email cached from the last [FocusColdStartRequested].
  ///
  /// Backfill on [FocusSenderSelected] needs it, since that event carries only the sender id.
  String? _userEmail;

  /// Senders whose windows have been hydrated from the backfill endpoint.
  ///
  /// A window built from live arrivals alone is not hydrated, so first selection still
  /// backfills and merges.
  final Set<String> _backfilled = {};

  /// Senders on the rail only because the live-seat roster listed them.
  ///
  /// Nothing has arrived from them yet. The roster's sender id can disagree with the one
  /// the seat's own notifications carry. The server resolves the project inside a
  /// container that cannot see the host path, so a worktree seat comes back as
  /// `claude.code@seat-…`. When the real id turns up, it takes over the alias's place on
  /// the rail.
  final Set<String> _rosterOnly = {};

  /// Injectable clock (for deterministic band tests) and timers.
  final DateTime Function() _now;
  final Duration?           _tickInterval;   // null ⇒ no periodic tick (tests / DI decides)
  final Duration            _exitDebounce;
  Timer?                    _activityTimer;
  final Map<String, Timer>  _exitTimers = {};

  /// User stop-list: matched inbound messages are not stored, counted unread or spoken.
  ///
  /// A matched message still establishes or bumps its sender, because it is activity.
  /// Backfill and refresh fetches are filtered by the same predicate.
  /// Null means no filtering.
  final NotificationStopList? _stopList;

  /// Whether a `job_id` belongs to a live Quick Ask question, the first `verbatim` setter.
  ///
  /// It is injected rather than imported so the enqueue stays in one place and this bloc
  /// does not learn about Quick Ask's internals. Null means no live ask surface (focus
  /// mode alone), and only the question arms of [shouldSpeakVerbatim] apply.
  final bool Function( String jobId )? _isQuickAskJob;

  /// Whether the Quick Ask probe was wired, for a dependency-injection test.
  ///
  /// The probe went uninjected in production while `actionable_speech_test` stayed green,
  /// because that test supplies the dependency it exercises.
  /// A test that hands in the thing under test cannot fail on its absence.
  /// This exposes the seam so a DI-level test can assert production wired it.
  @visibleForTesting
  bool get hasQuickAskProbe => _isQuickAskJob != null;

  /// Creates the bloc; every collaborator except the repository and orchestrator is optional.
  FocusChatBloc(
    this._repo, {
    required TtsOrchestrator tts,
    DateTime Function()? now,
    Duration?            tickInterval,
    Duration             exitDebounce = defaultExitDebounce,
    NotificationStopList? stopList,
    bool Function( String jobId )? isQuickAskJob,
  } )  : _tts            = tts,
         _isQuickAskJob  = isQuickAskJob,
         _now            = now ?? DateTime.now,
         _tickInterval   = tickInterval,
         _exitDebounce   = exitDebounce,
         _stopList       = stopList,
         super( const FocusChatState.initial() ) {
    on<FocusInboundNotification>( _onInbound );
    on<FocusSenderSelected>( _onSenderSelected );
    on<FocusColdStartRequested>( _onColdStart );
    on<FocusPersonaUpdated>( _onPersonaUpdated );
    on<FocusRespondRequested>( _onRespondRequested );
    on<FocusAskExpired>( _onAskExpired );
    on<FocusAskResponded>( _onAskResponded );
    on<FocusSpeakAnywayRequested>( _onSpeakAnyway );
    on<FocusFilterChanged>( _onFilterChanged );
    on<FocusSenderScopeChanged>( _onSenderScopeChanged );
    on<FocusActivityTick>( _onActivityTick );
    on<FocusSenderExited>( _onSenderExited );
    on<FocusRosterRefreshRequested>( _onRosterRefresh );
    on<FocusMessageRevealRequested>( _onRevealRequested );
    on<FocusRevealConsumed>( _onRevealConsumed );

    final interval = _tickInterval;
    if ( interval != null ) {
      _activityTimer = Timer.periodic( interval, ( _ ) => add( const FocusActivityTick() ) );
    }
  }

  @override
  Future<void> close() {
    _activityTimer?.cancel();
    for ( final t in _exitTimers.values ) {
      t.cancel();
    }
    _exitTimers.clear();
    return super.close();
  }

  // ---------- handlers ----------

  void _onInbound(
    FocusInboundNotification event,
    Emitter<FocusChatState> emit,
  ) {
    final item = event.item;
    final sid  = item.senderId;
    if ( sid == null ) {
      Logger.warning( 'Inbound notification without a sender id dropped', tag: 'FocusChat', context: LogContext( metadata: { 'notificationId': item.id } ) );
      return;
    }

    _rosterOnly.remove( sid );
    _adoptRosterAlias( sid, emit );                   // before `order` is read

    final order = List<String>.from( state.senderOrder );
    if ( !order.contains( sid ) ) order.add( sid );   // establishment order

    // A speaking sender is alive: bump its activity, re-enter Live, drop any
    // pending exit — and refresh the clock so the band re-derives now.
    final now      = _now();
    final activity = Map<String, DateTime>.from( state.lastActivityBySender )
      ..[ sid ] = now;
    final exited   = Set<String>.from( state.exitedSenders )..remove( sid );
    _exitTimers.remove( sid )?.cancel();

    // Is this something the user must act on? One predicate, used twice below: it decides
    // the stop-list exemption and whether speech is verbatim.
    final actionable = isActionableQuestion(
      responseRequested : item.responseRequested,
      senderId          : item.senderId,
      jobId             : item.jobId,
    );
    final rule = _suppressionRule( item );

    // Stop-list: a suppressed message is not stored, not unread and not spoken. It is
    // counted so the pane can say "N hidden". The sender still establishes or bumps above,
    // because the chatter proves the session is alive.
    //
    // One exemption: an item the user is expected to act on is not dropped here. It falls
    // through to be stored and rendered with the matched rule named, and the speech call
    // below is skipped. Dropping it at ingest would leave the prompt widget with no text
    // to render and no card to show its answer controls on.
    // Design: src/docs/decisions/README.md (R-FM-show-suppressed-ask)
    if ( rule != null && !actionable ) {
      final hidden = Map<String, int>.from( state.hiddenCountBySender )
        ..[ sid ] = ( state.hiddenCountBySender[ sid ] ?? 0 ) + 1;
      emit( state.copyWith(
        senderOrder          : order,
        lastActivityBySender : activity,
        exitedSenders        : exited,
        asOf                 : now,
        hiddenCountBySender  : hidden,
      ) );
      return;
    }

    final windows = _copyWindows();
    final window  = List<FocusMessage>.from( windows[ sid ] ?? const [] )
      ..add( FocusMessage( item: item ) );
    while ( window.length > windowCap ) {
      window.removeAt( 0 );                            // evict oldest
    }
    windows[ sid ] = window;

    final unread = Map<String, int>.from( state.unreadBySender );
    if ( state.focusedSender == sid ) {
      unread[ sid ] = 0;                               // focused stays read
    } else {
      unread[ sid ] = ( unread[ sid ] ?? 0 ) + 1;
    }

    emit( state.copyWith(
      senderOrder          : order,
      windows              : windows,
      unreadBySender       : unread,
      lastActivityBySender : activity,
      exitedSenders        : exited,
      asOf                 : now,
    ) );

    // Shown and marked, but not spoken: the user kept the mute half of the stop-list ruling.
    //
    // The muting is done by gate 1 inside the orchestrator, so this call is made rather than
    // skipped. An early return here would mute the item just as well, but the orchestrator
    // would never be invoked, gate 1 would never fire and no `TtsSuppression` would be
    // emitted. Speak-anyway would then have no object to act on.
    //
    // Letting the call through changes nothing the user hears: gate 1 fires first, before
    // `verbatim` is consulted, and returns without speaking. It only makes the suppression
    // reported.
    //
    // This relies on the orchestrator and this bloc sharing one `NotificationStopList`.
    // `service_locator.dart` resolves the same registered singleton for both, and a test
    // pins that shared instance.

    // Every item, at every priority, takes the ungated path.
    final persona = item.voicePersona ?? state.personasBySender[ sid ];
    final suppression = _tts.enqueueAlways(
      priority : item.priority,
      message  : item.message,
      title    : item.title,
      voiceId  : item.voicePersona?.voiceId,
      sender   : TtsSender( senderId: sid, name: persona?.displayName ?? persona?.name, icon: persona?.icon ),
      // Sender mute needs the same key the mute was stored under.
      senderKey: notificationSenderKey( {
        if ( persona?.name != null ) 'voice_persona': { 'name': persona!.name },
        'sender_id': item.senderId,
      } ),
      // An answer the user asked for, or a question something is blocked on, speaks in full
      // and is not muted.
      verbatim : shouldSpeakVerbatim(
        responseRequested : item.responseRequested,
        senderId          : item.senderId,
        jobId             : item.jobId,
        isLiveAskAnswer   : _isQuickAskJob,
      ),
    );

    // Gate 1 refused it: retain the orchestrator's own record against this message, so
    // speak-anyway later hands back the very object that was refused.
    if ( suppression != null ) {
      final marked = List<FocusMessage>.from( windows[ sid ]! );
      for ( var i = marked.length - 1; i >= 0; i-- ) {
        if ( marked[ i ].item.id == item.id ) {
          marked[ i ] = marked[ i ].copyWith( suppression: suppression );
          break;
        }
      }
      final withMark = _copyWindows()..[ sid ] = marked;
      emit( state.copyWith( windows: withMark ) );
    }
  }

  /// Handles a "speak it anyway" tap on a muted item.
  ///
  /// Hands the orchestrator back its own suppression object, with no reconstruction:
  /// whatever gate 1 refused is what plays.
  void _onSpeakAnyway( FocusSpeakAnywayRequested event, Emitter<FocusChatState> emit ) {
    for ( final window in state.windows.values ) {
      for ( final m in window ) {
        if ( m.item.id == event.notificationId ) {
          final s = m.suppression;
          if ( s != null ) _tts.speakAnyway( s );
          return;
        }
      }
    }
  }

  Future<void> _onSenderSelected(
    FocusSenderSelected event,
    Emitter<FocusChatState> emit,
  ) async {
    // A rail tap is a plain selection with no message to reveal. Clearing any
    // stale target here matters: without it, tapping away from a tap-routed
    // conversation and back would scroll to the old message again.
    await _selectSender( event.senderId, emit, clearReveal: true );
  }

  /// A notification tap: the rail's selection plus a message to bring into view.
  ///
  /// Both are applied as one state change.
  ///
  /// Ensures:
  ///   - focusedSender is the tap's sender and revealMessageId its notification, both set
  ///     before the first await, so a UI rebuild never observes one without the other
  ///   - the conversation is backfilled even when cold start has not run yet, since the
  ///     event carries the email for that case
  Future<void> _onRevealRequested(
    FocusMessageRevealRequested event,
    Emitter<FocusChatState> emit,
  ) async {
    // Seed the email the backfill needs. `??=` and not `=`: cold start may
    // already have set it, and this event's copy is the fallback, not the
    // authority.
    _userEmail ??= event.userEmail;
    await _selectSender( event.senderId, emit, reveal: event.notificationId );
  }

  void _onRevealConsumed( FocusRevealConsumed event, Emitter<FocusChatState> emit ) {
    if ( state.revealMessageId == null ) return;
    emit( state.copyWith( clearRevealMessageId: true ) );
  }

  /// The one selection path, shared by rail tap and notification tap.
  ///
  /// Unread-zeroing and backfill therefore cannot drift between them.
  ///
  /// [reveal] is the notification id to scroll to (notification tap). [clearReveal] drops
  /// any target already set (rail tap). Passing neither leaves the existing target alone.
  Future<void> _selectSender(
    String sid,
    Emitter<FocusChatState> emit, {
    String? reveal,
    bool    clearReveal = false,
  } ) async {
    final unread = Map<String, int>.from( state.unreadBySender );
    unread[ sid ] = 0;

    emit( state.copyWith(
      focusedSender        : sid,
      unreadBySender       : unread,
      revealMessageId      : reveal,
      clearRevealMessageId : clearReveal,
    ) );

    if ( _backfilled.contains( sid ) ) return;
    final email = _userEmail;
    if ( email == null ) return;   // no cold start yet — nothing to backfill against

    emit( state.copyWith( hydration: FocusHydration.loading ) );
    try {
      final msgs = await _repo.conversation( sid, email, hours: backfillHours );
      final fetched = msgs
          .where( ( m ) => !m.isHidden && !( _stopList?.matches( m.message ) ?? false ) )
          .map( FocusMessage.fromConversation )
          .toList();

      final windows  = _copyWindows();
      final existing = windows[ sid ] ?? const <FocusMessage>[];
      windows[ sid ] = _hydrateMerge( existing, fetched );
      _backfilled.add( sid );

      emit( state.copyWith(
        windows   : windows,
        hydration : FocusHydration.ready,
      ) );
    } on NotificationApiException catch ( e, st ) {
      _logFailure( 'Conversation backfill failed', e, st, senderId: sid );
      emit( state.copyWith( hydration: FocusHydration.error ) );
    }
  }

  /// Lets a real sender id take over a roster-only alias of the same session.
  ///
  /// [realSid] has just been seen from a real source: a message or the written-senders list.
  /// If an alias of the same session is on the rail, [realSid] takes over its place, focus,
  /// persona, activity and counts, and the alias disappears. Otherwise it does nothing.
  void _adoptRosterAlias( String realSid, Emitter<FocusChatState> emit ) {
    if ( state.senderOrder.contains( realSid ) ) return;
    final hash = sessionHashOf( realSid );
    if ( hash == null ) return;
    String? alias;
    for ( final s in _rosterOnly ) {
      if ( s != realSid && sessionHashOf( s ) == hash ) { alias = s; break; }
    }
    if ( alias == null ) return;
    final from = alias;

    _rosterOnly.remove( from );
    // A backfill under the alias fetched nothing (the server files the seat's
    // messages under the real id), so the real id is NOT marked backfilled.
    _backfilled.remove( from );
    final timer = _exitTimers.remove( from );
    if ( timer != null ) _exitTimers[ realSid ] = timer;

    Map<String, T> rekey<T>( Map<String, T> m ) {
      if ( !m.containsKey( from ) ) return m;
      final copy = Map<String, T>.from( m );
      copy[ realSid ] = copy.remove( from ) as T;
      return copy;
    }

    emit( state.copyWith(
      senderOrder          : [ for ( final s in state.senderOrder ) s == from ? realSid : s ],
      personasBySender     : rekey( state.personasBySender ),
      windows              : rekey( state.windows ),
      unreadBySender       : rekey( state.unreadBySender ),
      lastActivityBySender : rekey( state.lastActivityBySender ),
      hiddenCountBySender  : rekey( state.hiddenCountBySender ),
      exitedSenders        : state.exitedSenders.contains( from )
          ? ( Set<String>.from( state.exitedSenders )..remove( from )..add( realSid ) )
          : state.exitedSenders,
      focusedSender        : state.focusedSender == from ? realSid : null,
    ) );
  }

  Future<void> _onColdStart(
    FocusColdStartRequested event,
    Emitter<FocusChatState> emit,
  ) async {
    _userEmail = event.userEmail;

    if ( state.senderOrder.isEmpty ) {
      await _coldStartBuild( emit );
    } else {
      await _reconnectRefresh( emit );
      _resendUnsentAnswers();   // after the refresh has marked what closed meanwhile
    }
    // The live seats join on every cold start, not only the first: a reconnect is when a
    // newly spawned seat should appear.
    await _mergeLiveSeats( emit );
  }

  /// Handles the toolbar refresh: the same merge cold start does, on demand.
  ///
  /// It needs the user email that cold start recorded. Without it there is nothing to
  /// fetch, and the tap is a no-op rather than an error.
  /// Design: src/docs/decisions/README.md (R-FM-roster-refresh)
  Future<void> _onRosterRefresh(
    FocusRosterRefreshRequested event,
    Emitter<FocusChatState> emit,
  ) async {
    if ( _userEmail == null ) return;
    await _reconnectRefresh( emit );
    await _mergeLiveSeats( emit );
  }

  /// Merges the live-seat roster (`/api/commons/active-sessions`) into the rail.
  ///
  /// The notification-derived list only knows senders who have written to this user.
  /// A running seat the user had never heard from was therefore unreachable on the phone.
  /// A seat appears here with an empty window. Tapping it focuses it, and the ungated
  /// composer writes to it.
  ///
  /// Only seats the server addresses with a full `sender_id` can join. The rail is keyed
  /// by it, and guessing one from `session_id` would invent a sender. A roster failure is
  /// not fatal, because the written-senders rail still stands, so it logs and leaves state
  /// alone.
  /// Design: src/docs/decisions/README.md (R-FM-roster-refresh)
  Future<void> _mergeLiveSeats( Emitter<FocusChatState> emit ) async {
    final List<ActiveSession> seats;
    try {
      seats = await _repo.activeSessions();
    } catch ( e, st ) {
      // Catch everything, not just NotificationApiException: this roster is an addition to
      // a rail that already works. A server that does not serve the endpoint, or an
      // unexpected shape, must leave the written-senders rail untouched.
      _logFailure( 'Live-seat roster unavailable', e, st, level: LogLevel.warning );
      return;
    }

    final order    = List<String>.from( state.senderOrder );
    final personas = Map<String, VoicePersona?>.from( state.personasBySender );
    final activity = Map<String, DateTime>.from( state.lastActivityBySender );
    var   changed  = false;

    for ( final seat in seats ) {
      var sid = seat.senderId;
      // A seat joins only if its sender id is addressable, not merely present. A sentinel
      // such as "none" or "unknown" is neither null nor empty, would match no known session
      // hash, and would be appended to the rail as its own sender, collapsing every
      // unidentifiable seat onto one row. `sessionHashOf` subsumes null, "", "unknown",
      // "none" and anything else without a `#<hash>`.
      //
      // This assumes every legitimate roster seat carries a session hash. That holds because
      // the roster is `/api/commons/active-sessions`, which lists Claude Code seats only.
      // If it ever stops being true, this guard silently drops a real seat.
      //
      // The server contract is that the wire shape is absent-or-null, with no sentinel string
      // in the payload. This guard hardens against a contract violation, because the phone
      // cannot tell a sentinel from a seat and a wrong merge would quietly join strangers.
      //
      // The `sid == null` arm is redundant for correctness but required by the compiler:
      // `sessionHashOf( null )` already returns null, but Dart promotes `sid` to non-null only
      // from an explicit null test, and everything below uses it as a non-nullable String.
      // Do not simplify it away.
      if ( sid == null || sessionHashOf( sid ) == null ) continue;
      // The same session under a different project segment is the same seat. Merge into
      // the sender already on the rail rather than adding a second row for it.
      if ( !order.contains( sid ) ) {
        final known = senderWithSessionHash( order, sessionHashOf( sid ) );
        if ( known != null ) {
          sid = known;
        } else {
          order.add( sid );
          _rosterOnly.add( sid );
          changed = true;
        }
      }
      // A live bridge is the freshest persona there is, and `last_seen_iso`
      // is what the band needs; neither overwrites a value we already have
      // from a real message or a live persona event.
      if ( !personas.containsKey( sid ) ) {
        personas[ sid ] = seat.persona;
        changed = true;
      }
      final seen = seat.lastSeen;
      if ( seen != null && ( activity[ sid ] == null || activity[ sid ]!.isBefore( seen ) ) ) {
        activity[ sid ] = seen;
        changed = true;
      }
    }
    if ( !changed ) return;   // no churn when the roster says nothing new

    emit( state.copyWith(
      senderOrder          : order,
      personasBySender     : personas,
      lastActivityBySender : activity,
      asOf                 : _now(),
    ) );
  }

  /// Builds the rail from one `sendersVisible()` fetch bounded to [sendersHours].
  ///
  /// The registry is ordered by last activity, most recent first, as a one-time recency
  /// snapshot. Establishment order governs every live arrival thereafter, and the rail
  /// never re-sorts. `senders()` is not used because, with hours omitted, it returns the
  /// full history and carries no persona; `senders-visible` stamps `voice_persona` from
  /// the session bridge. It seeds `lastActivityBySender` and `personasBySender`, and a
  /// live `FocusPersonaUpdated` still overrides them.
  Future<void> _coldStartBuild( Emitter<FocusChatState> emit ) async {
    emit( state.copyWith( hydration: FocusHydration.loading ) );
    try {
      // Phase 1: the await, into a local. Never emit a copy captured before an await; a live
      // arrival during the fetch would be clobbered out of the registry, orphaning its window.
      final senders = await _repo.sendersVisible( _userEmail!, hours: sendersHours );

      // Phase 2: synchronous re-read, merge and emit, with no await between.
      final ordered = List<SenderSummary>.from( senders )
        ..sort( ( a, b ) {
          final la = a.lastActivity;
          final lb = b.lastActivity;
          if ( la == null && lb == null ) return 0;
          if ( la == null ) return 1;    // null activity sorts last
          if ( lb == null ) return -1;
          return lb.compareTo( la );     // DESC — most recent first
        } );
      final order = ordered.map( ( s ) => s.senderId ).toList();
      for ( final sid in state.senderOrder ) {
        // Arrivals that established themselves mid-fetch append after the snapshot. The
        // snapshot governs the initial rail; establishment order governs everything after.
        if ( !order.contains( sid ) ) order.add( sid );
      }

      emit( state.copyWith(
        senderOrder          : order,
        lastActivityBySender : _seedActivity( senders ),
        personasBySender     : _seedPersonas( senders ),
        asOf                 : _now(),
        hydration            : FocusHydration.ready,
      ) );
    } on NotificationApiException catch ( e, st ) {
      _logFailure( 'Cold start failed', e, st );
      emit( state.copyWith( hydration: FocusHydration.error ) );
    }
  }

  /// Refreshes after a reconnect, merging fetched data into the existing rail and windows.
  ///
  /// Existing senders keep their positions and new senders append in fetch order.
  /// Hydrated windows re-fetch and merge, deduplicated by notification id, capped at seven
  /// newest-last. Unread counts are preserved for existing senders, since a refresh is not
  /// a read, and increment per newly merged message for non-focused senders. Those badges
  /// are the signal the no-auto-re-speak pickup relies on. `focusedSender` is unchanged.
  Future<void> _reconnectRefresh( Emitter<FocusChatState> emit ) async {
    try {
      // Phase 1: all awaits go into locals. An inbound processed during these awaits mutates
      // state, and copies captured before them would clobber its append, unread count and
      // rail entry on emit: the audio would speak it and the UI would lose it.
      final senders = await _repo.sendersVisible( _userEmail!, hours: sendersHours );
      final fetchedBySender = <String, List<FocusMessage>>{};
      for ( final sid in _backfilled.toList() ) {
        final msgs = await _repo.conversation( sid, _userEmail!, hours: backfillHours );
        fetchedBySender[ sid ] = msgs
            .where( ( m ) => !m.isHidden && !( _stopList?.matches( m.message ) ?? false ) )
            .map( FocusMessage.fromConversation )
            .toList();
      }

      // Phase 2: one synchronous re-read, merge and emit, with no await between the state
      // read and the emit.
      for ( final s in senders ) {
        _rosterOnly.remove( s.senderId );
        _adoptRosterAlias( s.senderId, emit );
      }
      final order = List<String>.from( state.senderOrder );
      for ( final s in senders ) {
        if ( !order.contains( s.senderId ) ) order.add( s.senderId );
      }

      final windows = _copyWindows();
      final unread  = Map<String, int>.from( state.unreadBySender );

      fetchedBySender.forEach( ( sid, fetched ) {
        final existing    = windows[ sid ] ?? const <FocusMessage>[];
        final existingIds = existing.map( ( m ) => m.item.id ).toSet();
        final merged      = _contractMerge( existing, fetched );
        windows[ sid ]    = merged;

        if ( sid != state.focusedSender ) {
          final newCount = merged
              .where( ( m ) => !existingIds.contains( m.item.id ) )
              .length;
          if ( newCount > 0 ) unread[ sid ] = ( unread[ sid ] ?? 0 ) + newCount;
        }
      } );

      emit( state.copyWith(
        senderOrder          : order,
        windows              : windows,
        unreadBySender       : unread,
        lastActivityBySender : _seedActivity( senders ),
        personasBySender     : _seedPersonas( senders ),
        asOf                 : _now(),
        hydration            : FocusHydration.ready,
      ) );
    } on NotificationApiException catch ( e, st ) {
      _logFailure( 'Reconnect refresh failed', e, st );
      emit( state.copyWith( hydration: FocusHydration.error ) );
    }
  }

  void _onPersonaUpdated(
    FocusPersonaUpdated event,
    Emitter<FocusChatState> emit,
  ) {
    final sid      = event.senderId;
    final personas = Map<String, VoicePersona?>.from( state.personasBySender );
    personas[ sid ] = event.persona;   // null ⇒ released (no badge)

    if ( event.persona == null ) {
      // Released: arm the exit debounce. A re-assign for
      // the same sender before it fires means the seat was merely handed
      // back (reassignment / `/clear` / borrowed-return) — not an exit.
      _exitTimers.remove( sid )?.cancel();
      _exitTimers[ sid ] = Timer( _exitDebounce, () {
        _exitTimers.remove( sid );
        if ( !isClosed ) add( FocusSenderExited( sid ) );
      } );
      emit( state.copyWith( personasBySender: personas ) );
    } else {
      _exitTimers.remove( sid )?.cancel();
      final exited = Set<String>.from( state.exitedSenders )..remove( sid );
      emit( state.copyWith( personasBySender: personas, exitedSenders: exited ) );
    }
  }

  void _onFilterChanged(
    FocusFilterChanged event,
    Emitter<FocusChatState> emit,
  ) {
    emit( state.copyWith( filter: event.filter, asOf: _now() ) );
  }

  void _onSenderScopeChanged(
    FocusSenderScopeChanged event,
    Emitter<FocusChatState> emit,
  ) {
    emit( state.copyWith( senderScope: event.scope, asOf: _now() ) );
  }

  void _onActivityTick(
    FocusActivityTick event,
    Emitter<FocusChatState> emit,
  ) {
    // `asOf` is in props ⇒ Equatable fires a rebuild and `visibleOrder`
    // re-derives; aged-out senders drop with no refetch.
    emit( state.copyWith( asOf: _now() ) );
  }

  void _onSenderExited(
    FocusSenderExited event,
    Emitter<FocusChatState> emit,
  ) {
    _exitTimers.remove( event.senderId )?.cancel();
    final exited = Set<String>.from( state.exitedSenders )..add( event.senderId );
    emit( state.copyWith( exitedSenders: exited, asOf: _now() ) );
  }

  Future<void> _onRespondRequested(
    FocusRespondRequested event,
    Emitter<FocusChatState> emit,
  ) async {
    // Resolve the target notification id: explicit typed context wins; voice replies fall
    // back to the pinned selector.
    final targetId = event.promptContext?.notificationId
        ?? state.pendingPromptFor( event.senderId )?.item.id;

    if ( targetId == null ) {
      // No unanswered ask means this is a direct message to the session: the composer is
      // ungated, and a reply with nothing to reply to is a DM. Same event, same bubble, a
      // different door: the browsers' `POST /api/notify` user_initiated_message.
      await _sendDirectMessage( event.senderId, event.text, emit );
      return;
    }

    try {
      await _repo.respond( NotificationResponsePayload(
        notificationId : targetId,
        responseValue  : event.text,
      ) );

      final windows = _copyWindows();
      final window  = List<FocusMessage>.from( windows[ event.senderId ] ?? const [] );

      // Flip the answered ask so pendingPromptFor stops returning it, and clear any earlier
      // unsent copy: this one got through.
      for ( var i = 0; i < window.length; i++ ) {
        if ( window[ i ].item.id == targetId ) {
          window[ i ] = window[ i ].copyWith( answered: true, clearUnsentAnswer: true );
          break;
        }
      }

      // Append the user reply. The direction-styling discriminator is the pinned
      // `user_initiated_message` type.
      final now = DateTime.now();
      window.add( FocusMessage(
        item: NotificationItem(
          id                     : 'local-reply-${now.microsecondsSinceEpoch}',
          message                : event.text,
          type                   : 'user_initiated_message',
          priority               : 'low',
          senderId               : event.senderId,
          timestamp              : now,
          played                 : true,
          playCount              : 0,
          responseRequested      : false,
          suppressDing           : true,
          displayQualifierWidget : false,
        ),
        answered: true,
      ) );
      while ( window.length > windowCap ) {
        window.removeAt( 0 );
      }
      windows[ event.senderId ] = window;

      emit( state.copyWith(
        windows              : windows,
        lastActivityBySender : _activityBumped( event.senderId, _now() ),
        asOf                 : _now(),
      ) );
    } on NotificationApiException catch ( e, st ) {
      // Two of these 400s are not errors but endings: "already responded" and "grace period
      // exceeded" both mean the ask is finished. Raising a generic error would leave the card
      // pending forever and tell the user nothing they can act on.
      final resolution = classifyRespondFailure( e.message );
      if ( resolution.isResolved ) {
        emit( state.copyWith(
          windows: _windowsWithResolved( event.senderId, targetId, resolution ) ) );
        return;
      }
      _logFailure( 'Response to an ask failed', e, st, senderId: event.senderId, notificationId: targetId );
      // Keep the unsent answer on the card, so it reads "not sent", can be resent with a tap,
      // and is resent automatically on reconnect (see [_resendUnsentAnswers]).
      emit( state.copyWith(
        windows   : _windowsWithUnsent( event.senderId, targetId, event.text ),
        hydration : FocusHydration.error,
      ) );
    }
  }

  Map<String, List<FocusMessage>> _windowsWithUnsent( String senderId, String targetId, String text ) {
    final windows = _copyWindows();
    final window  = List<FocusMessage>.from( windows[ senderId ] ?? const [] );
    for ( var i = 0; i < window.length; i++ ) {
      if ( window[ i ].item.id == targetId ) {
        window[ i ] = window[ i ].copyWith( unsentAnswer: text );
        break;
      }
    }
    windows[ senderId ] = window;
    return windows;
  }

  /// Resends, on reconnect, every answer that never left the phone, if its ask is still open.
  ///
  /// One the server closed meanwhile (expired, or answered elsewhere) keeps its unsent
  /// text, and the card says it was not sent.
  void _resendUnsentAnswers() {
    state.windows.forEach( ( sid, window ) {
      for ( final m in window ) {
        final text = m.unsentAnswer;
        if ( text == null || m.answered ) continue;
        add( FocusRespondRequested(
          senderId      : sid,
          text          : text,
          promptContext : FocusPromptContext( notificationId: m.item.id, promptType: m.item.responseType ),
        ) );
      }
    } );
  }

  /// Handles `notification_expired`: the ask timed out and the server used its default.
  ///
  /// The ask is marked finished and carries which default was used.
  /// The card can then say what happened on the user's behalf rather than going quiet.
  void _onAskExpired( FocusAskExpired event, Emitter<FocusChatState> emit ) {
    emit( state.copyWith( windows: _resolveEverywhere(
      event.notificationId, AskResolution.expired, event.defaultUsed ) ) );
  }

  /// Handles `notification_responded`: another device, a proxy or the browser answered it.
  ///
  /// The card is retired. That is not an error, and not this phone's answer.
  void _onAskResponded( FocusAskResponded event, Emitter<FocusChatState> emit ) {
    emit( state.copyWith( windows: _resolveEverywhere(
      event.notificationId, AskResolution.answeredElsewhere, event.responseValue ) ) );
  }

  /// Resolves a notification id without knowing its sender.
  ///
  /// The lifecycle frames carry `notification_id` and no `sender_id`, so the id is looked
  /// up across every window rather than in one. Guessing a sender would be worse.
  Map<String, List<FocusMessage>> _resolveEverywhere(
    String        notificationId,
    AskResolution resolution,
    String?       detail,
  ) {
    final windows = _copyWindows();
    for ( final entry in windows.entries ) {
      final window = List<FocusMessage>.from( entry.value );
      var touched  = false;
      for ( var i = 0; i < window.length; i++ ) {
        if ( window[ i ].item.id == notificationId ) {
          window[ i ] = window[ i ].copyWith(
            answered         : true,
            resolution       : resolution,
            resolutionDetail : detail,
          );
          touched = true;
          break;
        }
      }
      if ( touched ) windows[ entry.key ] = window;
    }
    return windows;
  }

  /// Marks [targetId] finished with [resolution].
  ///
  /// The ask stops being pending, so the composer stops aiming at it.
  /// It carries what actually happened, which is not the same as "you answered it".
  Map<String, List<FocusMessage>> _windowsWithResolved(
    String senderId,
    String targetId,
    AskResolution resolution,
  ) {
    final windows = _copyWindows();
    final window  = List<FocusMessage>.from( windows[ senderId ] ?? const [] );
    for ( var i = 0; i < window.length; i++ ) {
      if ( window[ i ].item.id == targetId ) {
        window[ i ] = window[ i ].copyWith( answered: true, resolution: resolution );
        break;
      }
    }
    windows[ senderId ] = window;
    return windows;
  }

  /// Returns [sid] for a log entry, or a placeholder when it is the signed-in user's own address.
  String _loggableSender( String sid ) => sid == _userEmail ? '<user>' : sid;

  /// Logs a failed call at [level] under the FocusChat tag.
  ///
  /// The server's detail text can quote stored content, so only the exception type and the HTTP status are recorded.
  void _logFailure(
    String message,
    Object error,
    StackTrace stackTrace, {
    LogLevel level = LogLevel.error,
    String?  senderId,
    String?  notificationId,
  } ) {
    Logger.log(
      level,
      message,
      tag        : 'FocusChat',
      error      : describeFailure( error ),
      stackTrace : stackTrace,
      context    : LogContext( metadata: {
        if ( senderId != null )                           'senderId'       : _loggableSender( senderId ),
        if ( notificationId != null )                     'notificationId' : notificationId,
        if ( error is NotificationApiException && error.statusCode != null ) 'statusCode' : error.statusCode,
      } ),
    );
  }

  /// Builds the query a browser sends when the user types into a session's box.
  ///
  /// It is `POST /api/notify` as a `user_initiated_message`, `direction=human_to_ai`.
  /// It is addressed to the listener email (the sender id before `#`), with the session
  /// hash (after `#`) as `job_id`.
  /// The phone uses the exact endpoint the legacy and mux clients use, not `/api/dm/send`.
  /// That endpoint framed the phone as a peer session nobody could reply to.
  /// Returns null when the message cannot be addressed: no signed-in email, or a sender id
  /// without an `email#hash` shape, which the browsers refuse too.
  /// Design: src/docs/decisions/README.md (R-FM-direct-message-endpoint)
  NotifyRequest? sessionMessageFor( String senderId, String text ) {
    final email   = _userEmail;
    final hashIdx = senderId.indexOf( '#' );
    if ( email == null || email.isEmpty ) return null;
    if ( hashIdx <= 0 || hashIdx == senderId.length - 1 ) return null;
    return NotifyRequest(
      message    : text,
      type       : 'user_initiated_message',
      direction  : 'human_to_ai',
      priority   : 'medium',
      targetUser : senderId.substring( 0, hashIdx ),
      senderId   : email,
      jobId      : senderId.substring( hashIdx + 1 ),
    );
  }

  Future<void> _sendDirectMessage(
    String senderId,
    String text,
    Emitter<FocusChatState> emit,
  ) async {
    final request = sessionMessageFor( senderId, text );
    if ( request == null ) {
      Logger.warning( 'Cannot address a direct message to this sender', tag: 'FocusChat', context: LogContext( metadata: { 'senderId': _loggableSender( senderId ), 'hasUserEmail': _userEmail != null && _userEmail!.isNotEmpty } ) );
      emit( state.copyWith( hydration: FocusHydration.error ) );
      return;
    }
    try {
      await _repo.notify( request );
      final windows = _copyWindows();
      final window  = List<FocusMessage>.from( windows[ senderId ] ?? const [] );
      final now     = DateTime.now();
      window.add( FocusMessage(
        item: NotificationItem(
          id                     : 'local-msg-${now.microsecondsSinceEpoch}',
          message                : text,
          type                   : 'user_initiated_message',
          priority               : 'low',
          senderId               : senderId,
          timestamp              : now,
          played                 : true,
          playCount              : 0,
          responseRequested      : false,
          suppressDing           : true,
          displayQualifierWidget : false,
        ),
        answered: true,
      ) );
      while ( window.length > windowCap ) {
        window.removeAt( 0 );
      }
      windows[ senderId ] = window;
      emit( state.copyWith(
        windows              : windows,
        lastActivityBySender : _activityBumped( senderId, _now() ),
        asOf                 : _now(),
      ) );
    } on NotificationApiException catch ( e, st ) {
      _logFailure( 'Direct message failed', e, st, senderId: senderId );
      emit( state.copyWith( hydration: FocusHydration.error ) );
    }
  }

  // ---------- private ----------

  Map<String, List<FocusMessage>> _copyWindows() =>
      Map<String, List<FocusMessage>>.from( state.windows );

  /// The stop-list rule that mutes [item], or null.
  ///
  /// The pattern is stored on the message so an exempted question can name what muted it.
  /// The user's own replies are never suppressed, because they are not notifications.
  StopPattern? _suppressionRule( NotificationItem item ) =>
      item.type == 'user_initiated_message' ? null : _stopList?.matchFor( item.message );

  /// Returns last-activity with [senderId] bumped to [now] after a successful send.
  ///
  /// The Live lens counts notifications in both directions, sent or received in the last
  /// hour. A session the user just wrote to is live by that fact alone.
  /// A send therefore bumps its activity, and refreshes the clock the band re-derives from,
  /// as an arrival does.
  /// Design: src/docs/decisions/README.md (R-FM-live-both-directions)
  Map<String, DateTime> _activityBumped( String senderId, DateTime now ) =>
      Map<String, DateTime>.from( state.lastActivityBySender )..[ senderId ] = now;

  /// Merges fetched `lastActivity` into the registry; the fetched value wins.
  ///
  /// It is the server's view, and a live arrival after this emit bumps it again.
  Map<String, DateTime> _seedActivity( List<SenderSummary> senders ) {
    final activity = Map<String, DateTime>.from( state.lastActivityBySender );
    for ( final s in senders ) {
      final la = s.lastActivity;
      if ( la != null ) activity[ s.senderId ] = la;
    }
    return activity;
  }

  /// Seeds persona badges from `senders-visible` for senders no live event has covered.
  ///
  /// A live assignment or release already recorded wins. The bridge stamp is the
  /// cold-start fallback, not an override.
  Map<String, VoicePersona?> _seedPersonas( List<SenderSummary> senders ) {
    final personas = Map<String, VoicePersona?>.from( state.personasBySender );
    for ( final s in senders ) {
      final p = s.voicePersona;
      if ( p != null && !personas.containsKey( s.senderId ) ) personas[ s.senderId ] = p;
    }
    return personas;
  }

  /// Merges a first-hydration backfill into a window built from live arrivals.
  ///
  /// It is a union deduplicated by id that prefers the existing entry, because live items
  /// carry `responseOptions` and answered flips that the backfill wire cannot.
  /// Answered is ORed in from the fetched twin, then the result is sorted by timestamp
  /// ascending and capped to the newest [windowCap].
  List<FocusMessage> _hydrateMerge(
    List<FocusMessage> existing,
    List<FocusMessage> fetched,
  ) {
    final byId = <String, FocusMessage>{};
    for ( final m in fetched ) {
      byId[ m.item.id ] = m;
    }
    for ( final m in existing ) {
      final twin = byId[ m.item.id ];
      byId[ m.item.id ] = ( twin != null && twin.answered && !m.answered )
          ? m.copyWith( answered: true )
          : m;
    }
    final merged = byId.values.toList()
      ..sort( ( a, b ) => a.item.timestamp.compareTo( b.item.timestamp ) );
    return merged.length > windowCap
        ? merged.sublist( merged.length - windowCap )
        : merged;
  }

  /// Merges a reconnect-refresh fetch: existing entries keep their order.
  ///
  /// Fetched items not already present append in timestamp order, deduplicated by id,
  /// capped at [windowCap] newest-last by dropping from the front.
  List<FocusMessage> _contractMerge(
    List<FocusMessage> existing,
    List<FocusMessage> fetched,
  ) {
    final existingIds = existing.map( ( m ) => m.item.id ).toSet();
    final additions   = fetched
        .where( ( m ) => !existingIds.contains( m.item.id ) )
        .toList()
      ..sort( ( a, b ) => a.item.timestamp.compareTo( b.item.timestamp ) );

    final merged = <FocusMessage>[ ...existing, ...additions ];
    return merged.length > windowCap
        ? merged.sublist( merged.length - windowCap )
        : merged;
  }
}

/// The 8-hex session hash after the `#` of a Claude Code sender id, or null.
///
/// Two sender ids with the same hash are the same session.
String? sessionHashOf( String? senderId ) {
  if ( senderId == null ) return null;
  final i = senderId.lastIndexOf( '#' );
  if ( i < 0 || i == senderId.length - 1 ) return null;
  return senderId.substring( i + 1 );
}

/// The first sender in [order] whose session hash is [hash], or null.
String? senderWithSessionHash( List<String> order, String? hash ) {
  if ( hash == null ) return null;
  for ( final s in order ) {
    if ( sessionHashOf( s ) == hash ) return s;
  }
  return null;
}
