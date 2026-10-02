import 'package:equatable/equatable.dart';

import '../../notifications/data/notification_models.dart';
import 'focus_chat_state.dart' show FocusFilter, FocusSenderScope;

/// Typed prompt context for [FocusRespondRequested].
///
/// Inline prompts pass the target notification id explicitly. Voice replies omit it, and
/// the bloc falls back to `pendingPromptFor( senderId )`.
class FocusPromptContext extends Equatable {
  /// The notification the reply answers.
  final String  notificationId;

  /// The prompt kind: `yes_no`, `open_ended` or `multiple_choice`.
  final String? promptType;

  /// Creates the context.
  const FocusPromptContext( {
    required this.notificationId,
    this.promptType,
  } );

  @override
  List<Object?> get props => [ notificationId, promptType ];
}

/// An input to the focus chat bloc.
abstract class FocusChatEvent extends Equatable {
  /// Creates an event.
  const FocusChatEvent();
  @override
  List<Object?> get props => [];
}

/// An inbound notification from the WebSocket bridge, for every user-facing inner type.
///
/// The bloc upserts the sender, appends the item to the window (evicting beyond 7) and
/// bumps unread when the sender is not focused. It then enqueues the item for speech: every
/// item, every priority.
class FocusInboundNotification extends FocusChatEvent {
  /// The notification.
  final NotificationItem item;

  /// Creates the event.
  const FocusInboundNotification( this.item );
  @override
  List<Object?> get props => [ item.id ];
}

/// "Speak it anyway" on a stop-list-muted item.
///
/// It carries only the notification id. The bloc holds the orchestrator's own suppression
/// record and hands that back, so the UI never constructs one.
class FocusSpeakAnywayRequested extends FocusChatEvent {
  /// The muted notification to speak.
  final String notificationId;

  /// Creates the event.
  const FocusSpeakAnywayRequested( this.notificationId );
  @override
  List<Object?> get props => [ notificationId ];
}

/// The ask timed out: `notification_expired`.
///
/// The server has already substituted [defaultUsed], so nothing is left to answer, and the
/// card says so instead of sitting pending forever.
class FocusAskExpired extends FocusChatEvent {
  /// The expired notification.
  final String  notificationId;

  /// The default the server used on the user's behalf, when it said.
  final String? defaultUsed;

  /// Creates the event.
  const FocusAskExpired( { required this.notificationId, this.defaultUsed } );
  @override
  List<Object?> get props => [ notificationId, defaultUsed ];
}

/// Someone else answered: `notification_responded`.
///
/// That may be another device, a proxy or the browser. The card retires as answered; it is
/// not an error and it is not our answer.
class FocusAskResponded extends FocusChatEvent {
  /// The answered notification.
  final String  notificationId;

  /// The answer given, when the server said.
  final String? responseValue;

  /// Creates the event.
  const FocusAskResponded( { required this.notificationId, this.responseValue } );
  @override
  List<Object?> get props => [ notificationId, responseValue ];
}

/// A rail tap: focus the sender, zero its unread count, backfill if not hydrated.
class FocusSenderSelected extends FocusChatEvent {
  /// The selected sender.
  final String senderId;

  /// Creates the event.
  const FocusSenderSelected( this.senderId );
  @override
  List<Object?> get props => [ senderId ];
}

/// A notification tap: select [senderId] and mark [notificationId] to bring into view.
///
/// It is one event, not `FocusSenderSelected` plus a second one, so the two halves of one
/// gesture cannot half-apply. Handlers of different event types run concurrently under
/// bloc's default transformer, so a pair could interleave with each other and with the
/// cold-start handler. That would leave a sender selected with no reveal target, or a target
/// in a conversation no longer focused.
/// It also carries the email. Backfill needs the authenticated email, which the bloc
/// normally learns from [FocusColdStartRequested] on `auth_success`.
/// A tap is drained at `AuthAuthenticated`, which happens earlier by a different path.
/// On a swiped-away cold start, relying on cold start would select the sender and skip the
/// backfill. The screen would then show "No messages yet in this window" wrongly.
/// `_backfilled` keeps the two paths from fetching twice.
class FocusMessageRevealRequested extends FocusChatEvent {
  /// The sender to select.
  final String senderId;

  /// The message to bring into view.
  final String notificationId;

  /// The authenticated email, needed for backfill.
  final String userEmail;

  /// Creates the event.
  const FocusMessageRevealRequested( {
    required this.senderId,
    required this.notificationId,
    required this.userEmail,
  } );

  @override
  List<Object?> get props => [ senderId, notificationId, userEmail ];
}

/// The reveal has been honoured, because the pane scrolled to it or it was not in the window.
///
/// The target is cleared so a later rebuild does not scroll again while the user reads
/// something else.
class FocusRevealConsumed extends FocusChatEvent {
  /// Creates the event.
  const FocusRevealConsumed();
}

/// Screen init and WebSocket reconnect; the behaviour depends on the mode.
///
/// A cold start (`senderOrder` empty) builds the one-time `lastActivity` descending
/// snapshot. A reconnect refresh merges instead.
class FocusColdStartRequested extends FocusChatEvent {
  /// The authenticated email, needed for backfill.
  final String userEmail;

  /// Creates the event.
  const FocusColdStartRequested( { required this.userEmail } );
  @override
  List<Object?> get props => [ userEmail ];
}

/// Toolbar refresh tap: re-read the sender roster and the live seats from the bridges.
///
/// A seat that has never notified this user can then still be reached from the phone.
/// Design: src/docs/decisions/README.md (R-FM-roster-refresh)
class FocusRosterRefreshRequested extends FocusChatEvent {
  /// Creates the event.
  const FocusRosterRefreshRequested();
  @override
  List<Object?> get props => const [];
}

/// The WebSocket `voice_persona_assigned` or `voice_persona_released` bridge.
///
/// A null `persona` means the persona was released.
class FocusPersonaUpdated extends FocusChatEvent {
  /// The sender whose persona changed.
  final String        senderId;

  /// The new persona, or null when released.
  final VoicePersona? persona;

  /// Creates the event.
  const FocusPersonaUpdated( { required this.senderId, this.persona } );
  @override
  List<Object?> get props => [ senderId, persona ];
}

/// A toolbar `SegmentedButton` tap that switches the rail's visibility lens.
class FocusFilterChanged extends FocusChatEvent {
  /// The new filter.
  final FocusFilter filter;

  /// Creates the event.
  const FocusFilterChanged( this.filter );
  @override
  List<Object?> get props => [ filter ];
}

/// A toolbar Personas or All tap that switches the rail's sender-scope lens; rail only.
class FocusSenderScopeChanged extends FocusChatEvent {
  /// The new scope.
  final FocusSenderScope scope;

  /// Creates the event.
  const FocusSenderScopeChanged( this.scope );
  @override
  List<Object?> get props => [ scope ];
}

/// Periodic or on-resume re-evaluation of the recency bands, with `asOf = now`.
///
/// It refetches nothing; aged-out senders simply leave `visibleOrder`.
class FocusActivityTick extends FocusChatEvent {
  /// Creates the event.
  const FocusActivityTick();
}

/// A confirmed session exit.
///
/// It is `session_reaped` (unambiguous, for workers) or the `voice_persona_released`
/// debounce elapsing with no re-assign. In Live the sender's icon and card go invisible;
/// History still shows them.
class FocusSenderExited extends FocusChatEvent {
  /// The sender that exited.
  final String senderId;

  /// Creates the event.
  const FocusSenderExited( this.senderId );
  @override
  List<Object?> get props => [ senderId ];
}

/// The one response-dispatch shape.
///
/// Inline-prompt taps pass a typed [FocusPromptContext]; `VoiceReplyField` omits it. `text`
/// is a single String end to end. Batch open-ended asks are out of the focus inline path in
/// v1 and route to the legacy sheet, so this event never carries a Map.
class FocusRespondRequested extends FocusChatEvent {
  /// The sender being answered.
  final String              senderId;

  /// The reply text.
  final String              text;

  /// The prompt being answered, or null for a voice reply.
  final FocusPromptContext? promptContext;

  /// Creates the event.
  const FocusRespondRequested( {
    required this.senderId,
    required this.text,
    this.promptContext,
  } );

  @override
  List<Object?> get props => [ senderId, text, promptContext ];
}
