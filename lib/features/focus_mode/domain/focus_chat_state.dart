import 'package:equatable/equatable.dart';

import '../../../services/tts/tts_orchestrator.dart';
import '../../notifications/data/ask_resolution.dart';
import '../../notifications/data/notification_models.dart';

/// Hydration phase of the focus surface.
///
/// It is a single flag, because the surface re-renders wholesale on any change.
enum FocusHydration {
  /// Nothing has been requested.
  idle,

  /// A fetch is in flight.
  loading,

  /// The data is loaded.
  ready,

  /// The fetch failed.
  error
}

/// Rail filter: live shows recent sessions not exited, history shows the last 24 hours.
///
/// Live is sessions active in the last hour and not exited. History is everything active in
/// the last 24 hours, exited ones included.
/// Design: src/docs/decisions/README.md (R-FM-filter-scope)
enum FocusFilter {
  /// Sessions active in the last hour and not exited.
  live,

  /// Everything active in the last 24 hours, exited included.
  history
}

/// Rail sender scope: `personas` shows persona senders only, `all` adds system senders.
///
/// Persona senders are the ones carrying a voice-persona glyph.
/// The default is `personas` and it resets each launch. It affects the rail only: the
/// focused sender is always visible, and speech and the pane are untouched, since the
/// stop-list governs what is spoken.
/// Design: src/docs/decisions/README.md (R-FM-filter-scope)
enum FocusSenderScope {
  /// Only senders with a voice-persona glyph.
  personas,

  /// Personas and system senders.
  all
}

/// Recency band of a sender at `asOf`, matching the web clients' client-side math.
enum FocusBand {
  /// Active in the last hour.
  live,

  /// Active in the last 24 hours.
  history,

  /// Older than 24 hours, so dropped from the rail.
  stale
}

/// A thin view-model wrapping [NotificationItem] with its answered state.
///
/// The conversation wire is a fixed 19-field dict with no `response_options` or
/// `voice_persona`, so backfilled items ride `NotificationItem.fromJson( msg.raw )` plus an
/// explicit answered flag. A backfilled item is answered when `state == "responded"` or
/// `response_value` is non-null. A live item is unanswered on arrival and flips to answered
/// when a successful `FocusRespondRequested` targets its id. Backfilled bubbles carry no
/// `item.voicePersona`, so renderers fall back to [FocusChatState.personasBySender].
class FocusMessage extends Equatable {
  /// The notification this message wraps.
  final NotificationItem item;

  /// True when the ask is finished: answered here, answered elsewhere or expired.
  final bool             answered;

  /// The orchestrator's own suppression record, retained so the user can still hear the item.
  ///
  /// A question the user is expected to act on is not dropped at ingest as ordinary
  /// stop-listed chatter is. It is stored, rendered with the matched rule named, and left
  /// with its answer affordance, but it is still not spoken. This is the object the first
  /// gate produced, kept verbatim and not reconstructed.
  /// Speak-anyway hands it straight back to `TtsOrchestrator.speakAnyway()`, so the item
  /// that plays is the item that was refused.
  /// It is kept here and not in the orchestrator, which keeps that stream stateless and
  /// keys the record by the message it belongs to.
  /// Design: src/docs/decisions/README.md (R-FM-show-suppressed-ask)
  final TtsSuppression?  suppression;

  /// The matched pattern, for a UI that only needs to name the rule.
  ///
  /// It is a projection, so it can never disagree with [suppression].
  String? get suppressedRule => suppression?.rule;

  /// How this ask ended, when it ended without our answer; null for the ordinary case.
  ///
  /// "Expired" and "already answered elsewhere" are different facts, and the card says which.
  final AskResolution?   resolution;

  /// What the ending carried, when it carried something.
  ///
  /// It is the `default_used` on an expiry or the `response_value` on someone else's answer.
  /// "Expired" alone is thin; "expired, default used: no" tells the user what the server did
  /// on their behalf.
  final String?          resolutionDetail;

  /// The answer the user gave that never reached the server, such as one tapped while offline.
  ///
  /// It is kept so the card can say "not sent" and resend it, never dropped quietly. It is
  /// null once delivered.
  final String?          unsentAnswer;

  /// Creates a message.
  const FocusMessage( {
    required this.item,
    this.answered = false,
    this.suppression,
    this.resolution,
    this.resolutionDetail,
    this.unsentAnswer,
  } );

  /// Builds a message from a backfilled conversation entry.
  factory FocusMessage.fromConversation( ConversationMessage msg ) {
    return FocusMessage(
      item     : NotificationItem.fromJson( msg.raw ),
      // `expired` counts as answered. An expired ask is dead, because the server already
      // substituted its `response_default`. Counting it as pending left it forever at the
      // head of `pendingPromptFor`, so the composer aimed every voice reply at a dead ask
      // and took a 400 the user never saw. Answered here means finished, not answered by
      // us.
      answered : msg.state == 'responded'
              || msg.state == 'expired'
              || msg.responseValue != null,
    );
  }

  /// Copies the message with changes; [clearUnsentAnswer] drops the unsent answer.
  FocusMessage copyWith( {
    bool?           answered,
    TtsSuppression? suppression,
    AskResolution?  resolution,
    String?         resolutionDetail,
    String?         unsentAnswer,
    bool            clearUnsentAnswer = false,
  } ) => FocusMessage(
        item             : item,
        answered         : answered ?? this.answered,
        suppression      : suppression ?? this.suppression,
        resolution       : resolution ?? this.resolution,
        resolutionDetail : resolutionDetail ?? this.resolutionDetail,
        unsentAnswer     : clearUnsentAnswer ? null : ( unsentAnswer ?? this.unsentAnswer ),
      );

  @override
  List<Object?> get props =>
      [ item.id, answered, suppressedRule, resolution, resolutionDetail, unsentAnswer ];
}

/// State contract for the focus surface.
///
/// `senderOrder` is establishment order: append-only within an app run, first seen first.
/// Cold start seeds it from a one-time `lastActivity` descending snapshot, and the rail
/// never re-sorts afterwards, not even on a reconnect refresh.
class FocusChatState extends Equatable {
  /// The live band's width, matching the web clients: one hour.
  static const Duration liveWindow    = Duration( hours: 1 );

  /// The history band's width, matching the web clients: 24 hours; also the server fetch bound.
  static const Duration historyWindow = Duration( hours: 24 );

  /// Senders in establishment order.
  final List<String>                     senderOrder;

  /// The voice persona of each sender, or null when none is assigned.
  final Map<String, VoicePersona?>       personasBySender;

  /// Each sender's recent messages, capped at 7.
  final Map<String, List<FocusMessage>>  windows;

  /// Unread counts per sender; always 0 for the focused sender.
  final Map<String, int>                 unreadBySender;

  /// The sender whose conversation is open, or null.
  final String?                          focusedSender;

  /// Whether the data is loaded.
  final FocusHydration                   hydration;

  // The next fields form the visibility lens. A filter is visibility, not deletion.

  /// When each sender was last active.
  final Map<String, DateTime>            lastActivityBySender;

  /// Senders that exited: persona released and debounce elapsed, or reaped.
  final Set<String>                      exitedSenders;

  /// The rail's recency filter.
  final FocusFilter                      filter;

  /// The rail's sender scope.
  final FocusSenderScope                 senderScope;

  /// The evaluation clock; null means not yet evaluated.
  final DateTime?                        asOf;

  /// Messages the user's stop-list suppressed at ingest, per sender.
  ///
  /// They are never stored in the window, spoken or counted unread, and surface only as a
  /// "N hidden" caption.
  final Map<String, int>                 hiddenCountBySender;

  /// The notification id a notification tap asked to bring into view, or null.
  ///
  /// One event sets it together with [focusedSender], so the two cannot disagree, and it is
  /// cleared once the pane has acted on it. It is a one-shot instruction, not a selection:
  /// it means "scroll to this message, once". Leaving it set would re-scroll on every
  /// unrelated rebuild, yanking the list from under a user who has scrolled elsewhere.
  final String?                          revealMessageId;

  /// Creates the state.
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
    this.revealMessageId,
  } );

  /// The empty state before any data arrives.
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
        hiddenCountBySender  = const {},
        revealMessageId      = null;

  /// The recency band of [senderId] evaluated at [asOf].
  ///
  /// Unknown activity or a null clock gives `live`, so the rail is never blanked on a guess
  /// before hydration.
  FocusBand bandFor( String senderId ) {
    final at = asOf;
    final la = lastActivityBySender[ senderId ];
    if ( at == null || la == null ) return FocusBand.live;
    final age = at.difference( la );
    if ( age < liveWindow )    return FocusBand.live;
    if ( age < historyWindow ) return FocusBand.history;
    return FocusBand.stale;
  }

  /// Whether [senderId] carries a persona glyph, which puts it in the rail's persona group.
  ///
  /// It is the same test `SessionRail._badgeFor` uses to pick PersonaBadge over the initial
  /// fallback, so a persona without an icon renders as system.
  bool isPersona( String senderId ) {
    final p = personasBySender[ senderId ];
    return p != null && ( p.icon ?? '' ).isNotEmpty;
  }

  // The recency and exit lens only (Live or 24h), independent of [senderScope].
  bool _passesBand( String senderId ) {
    final band = bandFor( senderId );
    switch ( filter ) {
      case FocusFilter.live:
        return band == FocusBand.live && !exitedSenders.contains( senderId );
      case FocusFilter.history:
        return band != FocusBand.stale;
    }
  }

  /// Whether [senderId] is rendered under the current [filter] and [senderScope].
  ///
  /// The focused sender is always visible, even through a Personas-only scope, so the pane
  /// is never blanked mid-read.
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

  /// The persona group, oldest session first.
  ///
  /// It is sorted by `voice_persona.assigned_at` ascending. Senders with no timestamp follow
  /// in establishment order, and ties keep establishment order, so the sort is stable.
  /// Design: src/docs/decisions/README.md (R-FM-rail-order)
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

  /// The system group: senders with no persona glyph, in arrival order, never re-sorted.
  List<String> get visibleSystem =>
      senderOrder.where( ( s ) => !isPersona( s ) && isVisible( s ) ).toList( growable: false );

  /// The senders the rail shows: the persona group, then the system group.
  ///
  /// It is a pure render lens; `senderOrder` and `windows` are never pruned.
  List<String> get visibleOrder =>
      [ ...visiblePersonas, ...visibleSystem ];

  /// The Personas segment's count under the current Live or 24h lens.
  ///
  /// It is independent of [senderScope].
  int get personaCount => senderOrder.where( ( s ) => isPersona( s ) && _passesBand( s ) ).length;
  /// The All segment's count, under the current Live or 24h lens.
  int get allCount     => senderOrder.where( _passesBand ).length;

  /// The Live segment's count, independent of [filter].
  int get liveCount => senderOrder
      .where( ( s ) => bandFor( s ) == FocusBand.live && !exitedSenders.contains( s ) )
      .length;
  /// The 24h segment's count, independent of [filter].
  int get historyCount => senderOrder
      .where( ( s ) => bandFor( s ) != FocusBand.stale )
      .length;

  /// The sender's newest item with `responseRequested && !answered`, or null for none.
  ///
  /// It is the one selector for two consumers: the voice-reply fallback inside
  /// [FocusRespondRequested] resolution, and the buried-ask bubble rendering and composer
  /// gating. It is a pure derivation over the window with no side effects.
  FocusMessage? pendingPromptFor( String senderId ) {
    final window = windows[ senderId ];
    if ( window == null ) return null;
    for ( var i = window.length - 1; i >= 0; i-- ) {
      final m = window[ i ];
      if ( m.item.responseRequested && !m.answered ) return m;
    }
    return null;
  }

  /// Copies the state with changes; the `clear...` flags drop a field to null.
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
    String?                          revealMessageId,
    bool                             clearRevealMessageId = false,
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
      // An explicit clear, like `clearFocusedSender`: a null-coalescing copyWith cannot
      // express "set this back to null", and the reveal target must be clearable or it
      // fires forever.
      revealMessageId      : clearRevealMessageId
          ? null
          : ( revealMessageId ?? this.revealMessageId ),
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
    revealMessageId,
  ];
}
