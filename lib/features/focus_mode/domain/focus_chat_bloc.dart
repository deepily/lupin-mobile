import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../services/tts/tts_orchestrator.dart';
import '../../notifications/data/notification_models.dart';
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

  /// Cached from the last [FocusColdStartRequested] — backfill on
  /// [FocusSenderSelected] needs it (the event carries only the senderId).
  String? _userEmail;

  /// Senders whose windows have been hydrated from the backfill endpoint.
  /// A window created by live arrivals alone is NOT hydrated — first
  /// selection still backfills and merges (OSQ-4).
  final Set<String> _backfilled = {};

  FocusChatBloc( this._repo, { required TtsOrchestrator tts } )
      : _tts = tts,
        super( const FocusChatState.initial() ) {
    on<FocusInboundNotification>( _onInbound );
    on<FocusSenderSelected>( _onSenderSelected );
    on<FocusColdStartRequested>( _onColdStart );
    on<FocusPersonaUpdated>( _onPersonaUpdated );
    on<FocusRespondRequested>( _onRespondRequested );
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

    final windows = _copyWindows();
    final window  = List<FocusMessage>.from( windows[ sid ] ?? const [] )
      ..add( FocusMessage( item: item ) );
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
      senderOrder    : order,
      windows        : windows,
      unreadBySender : unread,
    ) );

    // EVERY item, EVERY priority (Q6) — the ungated S1 path (F-S1-1).
    _tts.enqueueAlways(
      priority : item.priority,
      message  : item.message,
      title    : item.title,
      voiceId  : item.voicePersona?.voiceId,
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
          .where( ( m ) => !m.isHidden )
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

  /// COLD START (OSQ-3 as amended, F-S2-S2-1): ONE `senders()` fetch
  /// (omitted hours = FULL history), registry ordered `lastActivity` DESC —
  /// a one-time recency snapshot. Establishment order governs every live
  /// arrival thereafter; the rail never re-sorts.
  Future<void> _coldStartBuild( Emitter<FocusChatState> emit ) async {
    emit( state.copyWith( hydration: FocusHydration.loading ) );
    try {
      // Phase 1 — the await, into a local (F-S2-IMPL-1: never emit a copy
      // captured before an await; a live arrival during the fetch would be
      // clobbered out of the registry, orphaning its window).
      final senders = await _repo.senders( _userEmail! );

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
        senderOrder : order,
        hydration   : FocusHydration.ready,
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
      final senders = await _repo.senders( _userEmail! );
      final fetchedBySender = <String, List<FocusMessage>>{};
      for ( final sid in _backfilled.toList() ) {
        final msgs = await _repo.conversation( sid, _userEmail!, hours: backfillHours );
        fetchedBySender[ sid ] = msgs
            .where( ( m ) => !m.isHidden )
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
        senderOrder    : order,
        windows        : windows,
        unreadBySender : unread,
        hydration      : FocusHydration.ready,
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
    final personas = Map<String, VoicePersona?>.from( state.personasBySender );
    personas[ event.senderId ] = event.persona;   // null ⇒ released (no badge)
    emit( state.copyWith( personasBySender: personas ) );
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
      // Defined non-crash outcome: S3 disables the composer off the same
      // selector, so this path is defensive.
      print( '[FocusChat] respond for ${event.senderId} with no pending prompt — dropped' );
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
      print( '[FocusChat] respond failed for $targetId: $e' );
      emit( state.copyWith( hydration: FocusHydration.error ) );
    }
  }

  // ---------- private ----------

  Map<String, List<FocusMessage>> _copyWindows() =>
      Map<String, List<FocusMessage>>.from( state.windows );

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
