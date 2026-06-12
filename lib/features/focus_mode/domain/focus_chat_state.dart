import 'package:equatable/equatable.dart';

import '../../notifications/data/notification_models.dart';

/// Hydration phase of the focus surface (single flag — the surface
/// re-renders wholesale on any change, S2 §3.1).
enum FocusHydration { idle, loading, ready, error }

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
  final List<String>                     senderOrder;
  final Map<String, VoicePersona?>       personasBySender;
  final Map<String, List<FocusMessage>>  windows;          // capped at 7 per sender (Q8)
  final Map<String, int>                 unreadBySender;   // 0 for focused sender (Q4)
  final String?                          focusedSender;
  final FocusHydration                   hydration;

  const FocusChatState( {
    required this.senderOrder,
    required this.personasBySender,
    required this.windows,
    required this.unreadBySender,
    required this.focusedSender,
    required this.hydration,
  } );

  const FocusChatState.initial()
      : senderOrder      = const [],
        personasBySender = const {},
        windows          = const {},
        unreadBySender   = const {},
        focusedSender    = null,
        hydration        = FocusHydration.idle;

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
  } ) {
    return FocusChatState(
      senderOrder      : senderOrder      ?? this.senderOrder,
      personasBySender : personasBySender ?? this.personasBySender,
      windows          : windows          ?? this.windows,
      unreadBySender   : unreadBySender   ?? this.unreadBySender,
      focusedSender    : clearFocusedSender ? null : ( focusedSender ?? this.focusedSender ),
      hydration        : hydration        ?? this.hydration,
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
  ];
}
