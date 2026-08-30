import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../services/notification_filter/notification_stop_list.dart';
import '../../../services/tts/speech_intent.dart';
import '../../../services/tts/tts_orchestrator.dart';
import '../../notifications/data/notification_models.dart';
import '../../notifications/data/ask_resolution.dart';
import '../../notifications/data/notification_repository.dart';
import 'focus_chat_event.dart';
import 'focus_chat_state.dart';

/// The slim, purpose-built state engine for the focus surface (Q2 — NOT an
/// extension of the legacy NotificationBloc). Holds exactly what the 5%
/// needs: insertion-ordered session registry (Q7), per-sender last-7
/// message windows (Q8), unread counts (Q4), focused sender, and the
/// `pendingPromptFor` contract-signal (F-S2-S2-3).
///
/// SOLE TTS dispatcher (F-S1-1 user ruling): every inbound notification —
/// every priority — goes to `TtsOrchestrator.enqueueAlways()` (S1's
/// ungated entry point). The legacy NotificationBloc's TTS dispatch is
/// withdrawn at the DI seam (`service_locator` no longer injects its
/// Optional `tts` dependency, F-S2-1) — the legacy bloc FILE is untouched.
class FocusChatBloc extends Bloc<FocusChatEvent, FocusChatState> {
  final NotificationRepository _repo;
  final TtsOrchestrator        _tts;

  /// Window cap per sender (Q8 — last 7 messages).
  static const int windowCap = 7;

  /// Backfill depth passed EXPLICITLY to `conversation()`: the server
  /// defaults to a 24-HOUR window when `hours` is omitted
  /// (Phase-0 2026-06-12, `notifications.py:1854`) — unlike `senders()`,
  /// where omitted means full history. One week fills a 7-item window for
  /// any recently active sender without unbounded payloads from chatty
  /// ones; the window cap is the real limiter.
  static const int backfillHours = 24 * 7;

  /// Server-side history bound for the senders fetch (plan 2026.06.25 §4.4
  /// G4): stale (⚪ >24h) senders never arrive; the 1h Live band is the
  /// client predicate on top ([FocusChatState.isVisible]).
  static const int sendersHours = 24;

  /// `voice_persona_released` carries no `reason` (parent task 69edd619 adds
  /// one); a benign seat hand-back and a true exit are wire-identical, so
  /// the release arms this debounce and a re-`assigned` cancels it.
  static const Duration defaultExitDebounce = Duration( seconds: 4 );

  /// Cached from the last [FocusColdStartRequested] — backfill on
  /// [FocusSenderSelected] needs it (the event carries only the senderId).
  String? _userEmail;

  /// Senders whose windows have been hydrated from the backfill endpoint.
  /// A window created by live arrivals alone is NOT hydrated — first
  /// selection still backfills and merges (OSQ-4).
  final Set<String> _backfilled = {};

  /// Injectable clock (deterministic band tests) + timers.
  final DateTime Function() _now;
  final Duration?           _tickInterval;   // null ⇒ no periodic tick (tests / DI decides)
  final Duration            _exitDebounce;
  Timer?                    _activityTimer;
  final Map<String, Timer>  _exitTimers = {};

  /// User stop-list (plan 2026.08.21 §3). A matched inbound message still
  /// ESTABLISHES / bumps its sender (it is activity) but is not stored,
  /// not counted unread and not spoken; backfill/refresh fetches are
  /// filtered by the same predicate. Null ⇒ no filtering.
  final NotificationStopList? _stopList;

  /// Setter 1 of the `verbatim` flag (plan §6): does this `job_id` belong
  /// to a live Quick Ask question? Injected rather than imported so the
  /// enqueue stays in ONE place and this bloc does not learn about Quick
  /// Ask's internals. Null ⇒ no live ask surface (focus mode alone), and
  /// only the QUESTION arms of [shouldSpeakVerbatim] apply.
  final bool Function( String jobId )? _isQuickAskJob;

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
    on<FocusFilterChanged>( _onFilterChanged );
    on<FocusSenderScopeChanged>( _onSenderScopeChanged );
    on<FocusActivityTick>( _onActivityTick );
    on<FocusSenderExited>( _onSenderExited );

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
      print( '[FocusChat] inbound without sender_id dropped (id=${item.id})' );
      return;
    }

    final order = List<String>.from( state.senderOrder );
    if ( !order.contains( sid ) ) order.add( sid );   // establishment order (Q7)

    // A speaking sender is alive: bump its activity, re-enter Live, drop any
    // pending exit — and refresh the clock so the band re-derives now.
    final now      = _now();
    final activity = Map<String, DateTime>.from( state.lastActivityBySender )
      ..[ sid ] = now;
    final exited   = Set<String>.from( state.exitedSenders )..remove( sid );
    _exitTimers.remove( sid )?.cancel();

    // Is this something the user must ACT ON? One predicate, used twice
    // below: it decides the stop-list exemption AND whether speech is
    // verbatim (AC-S3.6 / AC-S3.6b / AC-S3.8).
    final actionable = isActionableQuestion(
      responseRequested : item.responseRequested,
      senderId          : item.senderId,
      jobId             : item.jobId,
    );
    final rule = _suppressionRule( item );

    // Stop-list (plan 2026.08.21 §3): suppressed = not stored, not unread,
    // not spoken — counted so the pane can say "N hidden". Sender still
    // establishes/bumps above (the chatter proves the session is alive).
    //
    // 🔴 AC-S3.8(2), Rick 2026-08-29 — ONE exemption: an item the user is
    // expected to act on is NOT dropped here. *"yes of course you should
    // show the answer. And of course you should mute it and mark it. That
    // way I can play it if I want."* ⇒ it falls through to be stored and
    // rendered with the rule NAMED, and the speech call below is skipped.
    // Without this the item is discarded at ingest, and AC-S4.14 — which
    // asks the prompt widget to show that question WITH its answer
    // controls — has no text to render and no card to render it on.
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
      ..add( FocusMessage( item: item, suppressedRule: rule?.pattern ) );
    while ( window.length > windowCap ) {
      window.removeAt( 0 );                            // evict oldest (Q8)
    }
    windows[ sid ] = window;

    final unread = Map<String, int>.from( state.unreadBySender );
    if ( state.focusedSender == sid ) {
      unread[ sid ] = 0;                               // focused stays read (Q4)
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

    // 🔴 Shown, marked — and still NOT spoken (AC-S3.8(2)). Rick kept the
    // mute half of his stop-list ruling explicitly.
    //
    // The muting is done BY GATE 1, inside the orchestrator, and this call
    // is made deliberately rather than skipped (Arnold's finding,
    // 2026-08-29). An early return here muted the item just as well — and
    // meant the orchestrator was never invoked, so gate 1 never fired and
    // NO `TtsSuppression` was ever emitted. That left AC-S4.14's
    // speak-anyway with no object to act on and AC-S4.15's seam spanning a
    // wire that did not exist: "orchestrator suppression → prompt-widget
    // notice" cannot be tested end to end when the first half never
    // happens.
    //
    // Letting the call through changes nothing about what the user hears —
    // gate 1 fires first, before `verbatim` is ever consulted, and returns
    // without speaking. It changes only that the suppression is now
    // REPORTED, which is the whole point of AC-S3.7.
    //
    // ⚠️ This relies on the orchestrator and this bloc sharing ONE
    // `NotificationStopList` — they do (`service_locator.dart:268` and
    // `:321` both resolve the same registered singleton), and a test pins
    // that shared instance so it cannot become incidental.

    // EVERY item, EVERY priority (Q6) — the ungated S1 path (F-S1-1).
    final persona = item.voicePersona ?? state.personasBySender[ sid ];
    _tts.enqueueAlways(
      priority : item.priority,
      message  : item.message,
      title    : item.title,
      voiceId  : item.voicePersona?.voiceId,
      sender   : TtsSender( senderId: sid, name: persona?.displayName ?? persona?.name, icon: persona?.icon ),
      // Ruling 4 + AC-S3.6/S3.6b: an answer the user asked for, or a
      // question something is blocked on, speaks in full and is not muted.
      verbatim : shouldSpeakVerbatim(
        responseRequested : item.responseRequested,
        senderId          : item.senderId,
        jobId             : item.jobId,
        isLiveAskAnswer   : _isQuickAskJob,
      ),
    );
  }

  Future<void> _onSenderSelected(
    FocusSenderSelected event,
    Emitter<FocusChatState> emit,
  ) async {
    final sid    = event.senderId;
    final unread = Map<String, int>.from( state.unreadBySender );
    unread[ sid ] = 0;

    emit( state.copyWith(
      focusedSender  : sid,
      unreadBySender : unread,
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
    } on NotificationApiException catch ( e ) {
      print( '[FocusChat] backfill failed for $sid: $e' );
      emit( state.copyWith( hydration: FocusHydration.error ) );
    }
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
    }
  }

  /// COLD START (OSQ-3 as amended, F-S2-S2-1): ONE `sendersVisible()` fetch
  /// bounded to [sendersHours] (2026-08-21: `senders()` with hours omitted
  /// returned the FULL history — 146 senders on the dev box vs 6 in 24h —
  /// and carries no persona; `senders-visible` stamps `voice_persona` from
  /// the session bridge), registry ordered `lastActivity` DESC — a one-time
  /// recency snapshot. Establishment order governs every live arrival
  /// thereafter; the rail never re-sorts. Seeds `lastActivityBySender` and
  /// `personasBySender` (live `FocusPersonaUpdated` still overrides).
  Future<void> _coldStartBuild( Emitter<FocusChatState> emit ) async {
    emit( state.copyWith( hydration: FocusHydration.loading ) );
    try {
      // Phase 1 — the await, into a local (F-S2-IMPL-1: never emit a copy
      // captured before an await; a live arrival during the fetch would be
      // clobbered out of the registry, orphaning its window).
      final senders = await _repo.sendersVisible( _userEmail!, hours: sendersHours );

      // Phase 2 — synchronous re-read → merge → emit, no await between.
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
        // Arrivals that established themselves mid-fetch append after the
        // snapshot (snapshot governs the initial rail; establishment order
        // governs everything after — Q7).
        if ( !order.contains( sid ) ) order.add( sid );
      }

      emit( state.copyWith(
        senderOrder          : order,
        lastActivityBySender : _seedActivity( senders ),
        personasBySender     : _seedPersonas( senders ),
        asOf                 : _now(),
        hydration            : FocusHydration.ready,
      ) );
    } on NotificationApiException catch ( e ) {
      print( '[FocusChat] cold start failed: $e' );
      emit( state.copyWith( hydration: FocusHydration.error ) );
    }
  }

  /// RECONNECT-REFRESH (F-S2-S3-1 merge contract): existing senders KEEP
  /// their positions (Q7 anti-shuffle); new senders APPEND in fetch order;
  /// hydrated windows re-fetch + MERGE-DEDUPE by notification id (cap 7
  /// newest-last); unread counts are PRESERVED for existing senders — never
  /// zeroed (a refresh is not a read) — and INCREMENT per newly merged
  /// message for non-focused senders (implementer call, on the record in
  /// §8: the missed-message badges are the signal S5's no-auto-re-speak
  /// pickup behavior relies on); `focusedSender` unchanged.
  Future<void> _reconnectRefresh( Emitter<FocusChatState> emit ) async {
    try {
      // Phase 1 — ALL awaits into locals (F-S2-IMPL-1, same family as
      // F-S1-IMPL-1): an inbound processed during these awaits mutates
      // state; copies captured before the awaits would clobber its
      // append/unread/rail entry on emit (audio spoke it, UI lost it —
      // and the lost badge is the signal S5's pickup relies on).
      final senders = await _repo.sendersVisible( _userEmail!, hours: sendersHours );
      final fetchedBySender = <String, List<FocusMessage>>{};
      for ( final sid in _backfilled.toList() ) {
        final msgs = await _repo.conversation( sid, _userEmail!, hours: backfillHours );
        fetchedBySender[ sid ] = msgs
            .where( ( m ) => !m.isHidden && !( _stopList?.matches( m.message ) ?? false ) )
            .map( FocusMessage.fromConversation )
            .toList();
      }

      // Phase 2 — ONE synchronous re-read → merge → emit; no await between
      // the state read and the emit (the _onSenderSelected discipline).
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
    } on NotificationApiException catch ( e ) {
      print( '[FocusChat] reconnect refresh failed: $e' );
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
      // Released: arm the exit debounce (plan §4.8 item 4). A re-assign for
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
    // Resolve the target notification id (F-S2-S2-3): explicit typed
    // context wins; voice replies fall back to the pinned selector.
    final targetId = event.promptContext?.notificationId
        ?? state.pendingPromptFor( event.senderId )?.item.id;

    if ( targetId == null ) {
      // No unanswered ask ⇒ this is a DIRECT MESSAGE to the session (Rick
      // 2026-08-21: the composer is ungated; a reply with nothing to reply
      // to is a DM). Same event, same bubble — a different door.
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

      // Flip the answered ask so pendingPromptFor stops returning it.
      for ( var i = 0; i < window.length; i++ ) {
        if ( window[ i ].item.id == targetId ) {
          window[ i ] = window[ i ].copyWith( answered: true );
          break;
        }
      }

      // Append the user reply — S3's direction-styling discriminator is
      // the pinned `user_initiated_message` type (F-S2-S2-2).
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

      emit( state.copyWith( windows: windows ) );
    } on NotificationApiException catch ( e ) {
      // AC-S4.9 — two of these 400s are not errors, they are ENDINGS.
      // "already responded" and "grace period exceeded" both mean the ask
      // is finished; raising a generic error leaves the card pending
      // forever and tells the user nothing they can act on.
      final resolution = classifyRespondFailure( e.message );
      if ( resolution.isResolved ) {
        emit( state.copyWith(
          windows: _windowsWithResolved( event.senderId, targetId, resolution ) ) );
        return;
      }
      print( '[FocusChat] respond failed for $targetId: $e' );
      emit( state.copyWith( hydration: FocusHydration.error ) );
    }
  }

  /// `notification_expired` — AC-S4.3. The ask timed out and the server
  /// substituted its `response_default`. Marked finished, carrying WHICH
  /// default was used, so the card can say what happened on the user's
  /// behalf rather than going quiet.
  void _onAskExpired( FocusAskExpired event, Emitter<FocusChatState> emit ) {
    emit( state.copyWith( windows: _resolveEverywhere(
      event.notificationId, AskResolution.expired, event.defaultUsed ) ) );
  }

  /// `notification_responded` — AC-S4.3. Another device, a proxy, or the
  /// browser answered it. Retire the card: not an error, and not our
  /// answer.
  void _onAskResponded( FocusAskResponded event, Emitter<FocusChatState> emit ) {
    emit( state.copyWith( windows: _resolveEverywhere(
      event.notificationId, AskResolution.answeredElsewhere, event.responseValue ) ) );
  }

  /// Resolve a notification id WITHOUT knowing its sender.
  ///
  /// The lifecycle frames carry `notification_id` and nothing else
  /// identifying — no `sender_id` — so the id is looked up across every
  /// window rather than in one. Scanning all of them is honest about what
  /// the wire gives us; guessing a sender would be worse.
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

  /// Mark [targetId] finished with [resolution] — AC-S4.9. The ask stops
  /// being pending (so the composer stops aiming at it) and carries what
  /// actually happened, which is not the same as "you answered it".
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

  /// Sender identity stamped on outbound DMs (Rick 2026-08-21). The app
  /// has no display name — derive a readable one from the e-mail local
  /// part ("ricardo.felipe.ruiz@…" → "Ricardo"); icon marks the phone.
  static const String dmSenderIcon    = '📱';
  static const String dmSenderProject = 'lupin-mobile';

  static String dmSenderPersona( String? email ) {
    final local = ( email ?? '' ).split( '@' ).first.trim();
    if ( local.isEmpty ) return 'Mobile user';
    final first = local.split( RegExp( r'[._\-]' ) ).first;
    if ( first.isEmpty ) return 'Mobile user';
    return first[ 0 ].toUpperCase() + first.substring( 1 );
  }

  /// Address a chip: persona NAME when the registry has one (the server's
  /// preferred resolver), else the `#hash8` session suffix of the sender id
  /// (prefix-tolerant on the server), else the raw sender id.
  DmSendRequest dmRequestFor( String senderId, String text ) {
    final persona = state.personasBySender[ senderId ];
    final name    = ( persona?.name ?? '' ).trim();
    final hashIdx = senderId.lastIndexOf( '#' );
    final sessionSuffix = hashIdx >= 0 && hashIdx < senderId.length - 1
        ? senderId.substring( hashIdx + 1 )
        : null;
    return DmSendRequest(
      senderSessionId    : 'lupin-mobile:${_userEmail ?? 'anonymous'}',
      body               : text,
      recipientPersona   : name.isNotEmpty ? name : null,
      recipientSessionId : name.isNotEmpty ? null : ( sessionSuffix ?? senderId ),
      senderPersona      : dmSenderPersona( _userEmail ),
      senderIcon         : dmSenderIcon,
      senderProject      : dmSenderProject,
    );
  }

  Future<void> _sendDirectMessage(
    String senderId,
    String text,
    Emitter<FocusChatState> emit,
  ) async {
    try {
      await _repo.sendDm( dmRequestFor( senderId, text ) );
      final windows = _copyWindows();
      final window  = List<FocusMessage>.from( windows[ senderId ] ?? const [] );
      final now     = DateTime.now();
      window.add( FocusMessage(
        item: NotificationItem(
          id                     : 'local-dm-${now.microsecondsSinceEpoch}',
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
      emit( state.copyWith( windows: windows ) );
    } on NotificationApiException catch ( e ) {
      print( '[FocusChat] direct message to $senderId failed: $e' );
      emit( state.copyWith( hydration: FocusHydration.error ) );
    }
  }

  // ---------- private ----------

  Map<String, List<FocusMessage>> _copyWindows() =>
      Map<String, List<FocusMessage>>.from( state.windows );

  /// Stop-list predicate for live items. The user's own replies are never
  /// suppressed (they are not notifications).
  /// WHICH stop-list rule mutes [item], or null — AC-S3.8(2). The pattern
  /// is stored on the message so an exempted question can NAME what muted
  /// it. Replaces the old boolean `_suppressed`, which had exactly one
  /// caller: a predicate that could say THAT an item was muted but never
  /// WHICH rule did it cannot render the notice Rick asked for.
  StopPattern? _suppressionRule( NotificationItem item ) =>
      item.type == 'user_initiated_message' ? null : _stopList?.matchFor( item.message );

  /// Merge fetched `lastActivity` into the registry (fetched wins — it is
  /// the server's view; a live arrival after this emit bumps it again).
  Map<String, DateTime> _seedActivity( List<SenderSummary> senders ) {
    final activity = Map<String, DateTime>.from( state.lastActivityBySender );
    for ( final s in senders ) {
      final la = s.lastActivity;
      if ( la != null ) activity[ s.senderId ] = la;
    }
    return activity;
  }

  /// Seed persona badges from `senders-visible` for senders the live
  /// `FocusPersonaUpdated` stream has not (yet) told us about. A live
  /// assignment/release already recorded wins — the bridge stamp is the
  /// cold-start fallback, not an override.
  Map<String, VoicePersona?> _seedPersonas( List<SenderSummary> senders ) {
    final personas = Map<String, VoicePersona?>.from( state.personasBySender );
    for ( final s in senders ) {
      final p = s.voicePersona;
      if ( p != null && !personas.containsKey( s.senderId ) ) personas[ s.senderId ] = p;
    }
    return personas;
  }

  /// First-hydration merge (OSQ-4 backfill meeting a live-built window):
  /// union dedupe by id PREFERRING the existing entry (live items carry
  /// `responseOptions` / answered flips that the 19-field backfill wire
  /// cannot), answered ORed in from the fetched twin, then timestamp
  /// ascending, capped to the newest [windowCap].
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

  /// Reconnect-refresh merge (F-S2-S3-1, contract-literal): existing
  /// entries keep their order; fetched items not already present APPEND in
  /// timestamp order; dedupe by id; cap [windowCap] newest-last (drop from
  /// the front).
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
