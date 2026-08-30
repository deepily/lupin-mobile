import 'package:equatable/equatable.dart';

import '../../notifications/data/notification_models.dart';
import 'focus_chat_state.dart' show FocusFilter, FocusSenderScope;

/// Typed prompt-context for [FocusRespondRequested] (F-S2-S2-3): inline
/// prompts pass the target notification id explicitly; voice replies omit
/// it and the bloc falls back to `pendingPromptFor( senderId )`.
class FocusPromptContext extends Equatable {
  final String  notificationId;
  final String? promptType;     // yes_no | open_ended | multiple_choice

  const FocusPromptContext( {
    required this.notificationId,
    this.promptType,
  } );

  @override
  List<Object?> get props => [ notificationId, promptType ];
}

abstract class FocusChatEvent extends Equatable {
  const FocusChatEvent();
  @override
  List<Object?> get props => [];
}

/// WS bridge dispatch (`app.dart`) for every user-facing inner type on
/// `notification_queue_update`. Effect: upsert sender (append if new) →
/// append to window (evict >7) → unread++ if not focused → emit; then
/// `TtsOrchestrator.enqueueAlways(...)` — EVERY item, EVERY priority (Q6).
class FocusInboundNotification extends FocusChatEvent {
  final NotificationItem item;
  const FocusInboundNotification( this.item );
  @override
  List<Object?> get props => [ item.id ];
}

/// The ask TIMED OUT — `notification_expired` (AC-S4.3). The server has
/// already substituted [defaultUsed]; there is nothing left to answer, and
/// the card says so rather than sitting pending forever.
class FocusAskExpired extends FocusChatEvent {
  final String  notificationId;
  final String? defaultUsed;
  const FocusAskExpired( { required this.notificationId, this.defaultUsed } );
  @override
  List<Object?> get props => [ notificationId, defaultUsed ];
}

/// Somebody ELSE answered — `notification_responded` (AC-S4.3). Another
/// device, a proxy, or the browser. Retire the card as answered; it is not
/// an error and it is not our answer.
class FocusAskResponded extends FocusChatEvent {
  final String  notificationId;
  final String? responseValue;
  const FocusAskResponded( { required this.notificationId, this.responseValue } );
  @override
  List<Object?> get props => [ notificationId, responseValue ];
}

/// S3 rail tap: set focused, zero its unread, trigger backfill if the
/// window is not yet hydrated (OSQ-4).
class FocusSenderSelected extends FocusChatEvent {
  final String senderId;
  const FocusSenderSelected( this.senderId );
  @override
  List<Object?> get props => [ senderId ];
}

/// Screen init AND WS reconnect (S2 §3.3). MODE-DEPENDENT (F-S2-S3-1):
/// cold start (`senderOrder` empty) builds the one-time `lastActivity`
/// DESC snapshot; reconnect-refresh MERGES per the §3.1 contract.
class FocusColdStartRequested extends FocusChatEvent {
  final String userEmail;
  const FocusColdStartRequested( { required this.userEmail } );
  @override
  List<Object?> get props => [ userEmail ];
}

/// WS `voice_persona_assigned` / `voice_persona_released` bridge.
/// `persona == null` ⇒ released.
class FocusPersonaUpdated extends FocusChatEvent {
  final String        senderId;
  final VoicePersona? persona;
  const FocusPersonaUpdated( { required this.senderId, this.persona } );
  @override
  List<Object?> get props => [ senderId, persona ];
}

/// Toolbar `SegmentedButton` tap — switch the rail's visibility lens.
class FocusFilterChanged extends FocusChatEvent {
  final FocusFilter filter;
  const FocusFilterChanged( this.filter );
  @override
  List<Object?> get props => [ filter ];
}

/// Toolbar Personas / All tap — switch the rail's sender-scope lens
/// (rail only; Rick 2026-08-21).
class FocusSenderScopeChanged extends FocusChatEvent {
  final FocusSenderScope scope;
  const FocusSenderScopeChanged( this.scope );
  @override
  List<Object?> get props => [ scope ];
}

/// Periodic / on-resume re-evaluation of the recency bands (`asOf = now`).
/// No refetch — aged-out senders simply leave `visibleOrder`.
class FocusActivityTick extends FocusChatEvent {
  const FocusActivityTick();
}

/// Confirmed session exit: `session_reaped` (unambiguous, workers) or the
/// `voice_persona_released` debounce elapsing with no re-assign. In Live
/// the sender's icon + card go invisible; History still shows them.
class FocusSenderExited extends FocusChatEvent {
  final String senderId;
  const FocusSenderExited( this.senderId );
  @override
  List<Object?> get props => [ senderId ];
}

/// The ONE response-dispatch shape (F-S3-2): S3 inline-prompt taps pass a
/// typed [FocusPromptContext]; S4's `VoiceReplyField` (via S3-wired
/// `onSubmit`) omits it. `text` is a SINGLE String end-to-end — batch
/// open-ended asks are scoped OUT of the focus inline path in v1 and route
/// to the legacy sheet (F-S3-S2-2(d)); this event never carries a Map.
class FocusRespondRequested extends FocusChatEvent {
  final String              senderId;
  final String              text;
  final FocusPromptContext? promptContext;

  const FocusRespondRequested( {
    required this.senderId,
    required this.text,
    this.promptContext,
  } );

  @override
  List<Object?> get props => [ senderId, text, promptContext ];
}
