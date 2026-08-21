import 'package:equatable/equatable.dart';

import '../../notifications/data/notification_models.dart';

/// Hydration phase of the focus surface (single flag — the surface
/// re-renders wholesale on any change, S2 §3.1).
enum FocusHydration { idle, loading, ready, error }

/// Rail filter (2026.06.25 plan §4.1, ratified by Rick 2026-08-21):
/// `live` = sessions active in the last hour and not exited;
/// `history` = everything active in the last 24h (exited included).
enum FocusFilter { live, history }

/// Rail SENDER SCOPE (Rick 2026-08-21, voice): `personas` = only senders
/// carrying a voice-persona glyph; `all` = personas + system senders.
/// Default `personas`, resets each launch. RAIL ONLY — the focused
/// sender is always visible, and TTS/pane are untouched (the stop-list
/// governs what is spoken).
enum FocusSenderScope { personas, all }

/// Recency band of a sender at `asOf` — mirrors the web clients' pure
/// client-side math (🟢 <1h, 🟡 <24h, ⚪ dropped).
enum FocusBand { live, history, stale }

/// Thin view-model wrapping [NotificationItem] with answered-state — the
/// OPERATIVE §3.1 mapping branch (F-S2-S2-2; Phase-0 2026-06-12 ruled
/// raw-passthrough OUT: the conversation wire is a fixed 19-field dict
/// with no `response_options` / `voice_persona`, so backfilled items ride
/// `NotificationItem.fromJson( msg.raw )` + an explicit answered flag).
///
/// `answered` truth table:
///   - backfill: `state == "responded"` OR non-null `response_value`
///     (discriminator fields ARE wire-present, Phase-0 fixture)
///   - live: false on arrival; flipped true by a successful
///     `FocusRespondRequested` targeting this item's id
///
/// Persona badges for BACKFILLED bubbles: `item.voicePersona` is always
/// null on this path (not on the wire) — renderers fall back to
/// [FocusChatState.personasBySender] (the registry), per Phase-0.
class FocusMessage extends Equatable {
  final NotificationItem item;
  final bool             answered;

  const FocusMessage( {
    required this.item,
    this.answered = false,
  } );

  factory FocusMessage.fromConversation( ConversationMessage msg ) {
    return FocusMessage(
      item     : NotificationItem.fromJson( msg.raw ),
      answered : msg.state == 'responded' || msg.responseValue != null,
    );
  }

  FocusMessage copyWith( { bool? answered } ) =>
      FocusMessage( item: item, answered: answered ?? this.answered );

  @override
  List<Object?> get props => [ item.id, answered ];
}

/// State contract for the focus surface (S2 §3.1; consumed by S3).
///
/// `senderOrder` is establishment order (Q7): append-only within an app
/// run; first-seen first. Cold start seeds it from a one-time
/// `lastActivity` DESC snapshot (OSQ-3 as amended) — the rail NEVER
/// re-sorts thereafter, not even on reconnect refresh.
class FocusChatState extends Equatable {
  /// Live band — mirrors web `notifications.js` / multiplexer (3.6e6 ms).
  static const Duration liveWindow    = Duration( hours: 1 );
  /// History band — mirrors web (8.64e7 ms); also the server fetch bound.
  static const Duration historyWindow = Duration( hours: 24 );

  final List<String>                     senderOrder;
  final Map<String, VoicePersona?>       personasBySender;
  final Map<String, List<FocusMessage>>  windows;          // capped at 7 per sender (Q8)
  final Map<String, int>                 unreadBySender;   // 0 for focused sender (Q4)
  final String?                          focusedSender;
  final FocusHydration                   hydration;
  // ── visibility lens (filter = VISIBILITY, not deletion — Rick 2026.06.25) ──
  final Map<String, DateTime>            lastActivityBySender;
  final Set<String>                      exitedSenders;    // persona released + debounce elapsed, or reaped
  final FocusFilter                      filter;
  final FocusSenderScope                 senderScope;
  final DateTime?                        asOf;             // evaluation clock; null ⇒ not yet evaluated
  /// Messages the user's stop-list suppressed at ingest, per sender
  /// (plan 2026.08.21 §3) — never stored in the window, never spoken,
  /// never counted unread; surfaced only as a "N hidden" caption.
  final Map<String, int>                 hiddenCountBySender;

  const FocusChatState( {
    required this.senderOrder,
    required this.personasBySender,
    required this.windows,
    required this.unreadBySender,
    required this.focusedSender,
    required this.hydration,
    this.lastActivityBySender = const {},
    this.exitedSenders        = const {},
    this.filter               = FocusFilter.live,
    this.senderScope          = FocusSenderScope.personas,
    this.asOf,
    this.hiddenCountBySender  = const {},
  } );

  const FocusChatState.initial()
      : senderOrder          = const [],
        personasBySender     = const {},
        windows              = const {},
        unreadBySender       = const {},
        focusedSender        = null,
        hydration            = FocusHydration.idle,
        lastActivityBySender = const {},
        exitedSenders        = const {},
        filter               = FocusFilter.live,
        senderScope          = FocusSenderScope.personas,
        asOf                 = null,
        hiddenCountBySender  = const {};

  /// Recency band of [senderId] evaluated at [asOf]. Unknown activity or a
  /// null clock ⇒ `live` (pre-hydration: never blank the rail on a guess).
  FocusBand bandFor( String senderId ) {
    final at = asOf;
    final la = lastActivityBySender[ senderId ];
    if ( at == null || la == null ) return FocusBand.live;
    final age = at.difference( la );
    if ( age < liveWindow )    return FocusBand.live;
    if ( age < historyWindow ) return FocusBand.history;
    return FocusBand.stale;
  }

  /// Does [senderId] carry a persona GLYPH (the rail's persona group)?
  /// Same test `SessionRail._badgeFor` uses to pick PersonaBadge over the
  /// initial fallback — a persona without an icon renders as system.
  bool isPersona( String senderId ) {
    final p = personasBySender[ senderId ];
    return p != null && ( p.icon ?? '' ).isNotEmpty;
  }

  /// Recency/exit lens only (Live/24h) — independent of [senderScope].
  bool _passesBand( String senderId ) {
    final band = bandFor( senderId );
    switch ( filter ) {
      case FocusFilter.live:
        return band == FocusBand.live && !exitedSenders.contains( senderId );
      case FocusFilter.history:
        return band != FocusBand.stale;
    }
  }

  /// Is [senderId] rendered under the current [filter] + [senderScope]?
  /// The focused sender is ALWAYS visible (never blank the pane mid-read —
  /// plan §4.6; Rick 2026-08-21: also through a Personas-only scope).
  bool isVisible( String senderId ) {
    if ( senderId == focusedSender ) return true;
    if ( !_passesBand( senderId ) ) return false;
    switch ( senderScope ) {
      case FocusSenderScope.personas:
        return isPersona( senderId );
      case FocusSenderScope.all:
        return true;
    }
  }

  /// Persona group, OLDEST SESSION FIRST (Rick 2026-08-21): sorted by
  /// `voice_persona.assigned_at` ascending; senders with no timestamp
  /// follow in establishment order; ties keep establishment order (stable).
  List<String> get visiblePersonas {
    final indexed = <MapEntry<int, String>>[];
    for ( var i = 0; i < senderOrder.length; i++ ) {
      final sid = senderOrder[ i ];
      if ( isPersona( sid ) && isVisible( sid ) ) indexed.add( MapEntry( i, sid ) );
    }
    indexed.sort( ( a, b ) {
      final ta = personasBySender[ a.value ]?.assignedAt;
      final tb = personasBySender[ b.value ]?.assignedAt;
      if ( ta == null && tb == null ) return a.key.compareTo( b.key );
      if ( ta == null ) return 1;
      if ( tb == null ) return -1;
      final c = ta.compareTo( tb );
      return c != 0 ? c : a.key.compareTo( b.key );
    } );
    return indexed.map( ( e ) => e.value ).toList( growable: false );
  }

  /// System group (no persona glyph), establishment order — Rick ruled
  /// 2026-08-21: arrival order, never re-sorted.
  List<String> get visibleSystem =>
      senderOrder.where( ( s ) => !isPersona( s ) && isVisible( s ) ).toList( growable: false );

  /// Derived, pure: the senders the rail shows — persona group (oldest
  /// session first) then system group (establishment order). `senderOrder`
  /// / `windows` are never pruned — this is a render lens.
  List<String> get visibleOrder =>
      [ ...visiblePersonas, ...visibleSystem ];

  /// Toolbar counts for the Personas / All segments — under the current
  /// Live/24h lens, independent of [senderScope].
  int get personaCount => senderOrder.where( ( s ) => isPersona( s ) && _passesBand( s ) ).length;
  int get allCount     => senderOrder.where( _passesBand ).length;

  /// Count the toolbar shows for each segment (independent of [filter]).
  int get liveCount => senderOrder
      .where( ( s ) => bandFor( s ) == FocusBand.live && !exitedSenders.contains( s ) )
      .length;
  int get historyCount => senderOrder
      .where( ( s ) => bandFor( s ) != FocusBand.stale )
      .length;

  /// The pinned contract-signal selector (F-S2-S2-3): the sender's NEWEST
  /// item with `responseRequested && !answered`, or null (⇒ no unanswered
  /// ask). ONE selector, TWO consumers: the voice-reply fallback inside
  /// [FocusRespondRequested] resolution, and S3's buried-ask bubble
  /// rendering / composer gating. Pure derivation over the window — no
  /// side effects.
  FocusMessage? pendingPromptFor( String senderId ) {
    final window = windows[ senderId ];
    if ( window == null ) return null;
    for ( var i = window.length - 1; i >= 0; i-- ) {
      final m = window[ i ];
      if ( m.item.responseRequested && !m.answered ) return m;
    }
    return null;
  }

  FocusChatState copyWith( {
    List<String>?                    senderOrder,
    Map<String, VoicePersona?>?      personasBySender,
    Map<String, List<FocusMessage>>? windows,
    Map<String, int>?                unreadBySender,
    String?                          focusedSender,
    bool                             clearFocusedSender = false,
    FocusHydration?                  hydration,
    Map<String, DateTime>?           lastActivityBySender,
    Set<String>?                     exitedSenders,
    FocusFilter?                     filter,
    FocusSenderScope?                senderScope,
    DateTime?                        asOf,
    Map<String, int>?                hiddenCountBySender,
  } ) {
    return FocusChatState(
      senderOrder          : senderOrder          ?? this.senderOrder,
      personasBySender     : personasBySender     ?? this.personasBySender,
      windows              : windows              ?? this.windows,
      unreadBySender       : unreadBySender       ?? this.unreadBySender,
      focusedSender        : clearFocusedSender ? null : ( focusedSender ?? this.focusedSender ),
      hydration            : hydration            ?? this.hydration,
      lastActivityBySender : lastActivityBySender ?? this.lastActivityBySender,
      exitedSenders        : exitedSenders        ?? this.exitedSenders,
      filter               : filter               ?? this.filter,
      senderScope          : senderScope          ?? this.senderScope,
      asOf                 : asOf                 ?? this.asOf,
      hiddenCountBySender  : hiddenCountBySender  ?? this.hiddenCountBySender,
    );
  }

  @override
  List<Object?> get props => [
    senderOrder,
    personasBySender,
    windows,
    unreadBySender,
    focusedSender,
    hydration,
    lastActivityBySender,
    exitedSenders,
    filter,
    senderScope,
    asOf,
    hiddenCountBySender,
  ];
}
