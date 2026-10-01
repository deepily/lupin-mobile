import 'package:equatable/equatable.dart';

import '../data/notification_models.dart';

/// Base class of every state of the notification bloc.
abstract class NotificationState extends Equatable {
  /// Creates a state.
  const NotificationState();

  @override
  List<Object?> get props => [];
}

/// Persona snapshot that every loaded state carries for header rendering.
///
/// Speech does not read this map; it takes the persona from each notification.
mixin PersonaSnapshotMixin {
  /// Voice persona per sender id.
  Map<String, VoicePersona> get personasBySender;

  /// Persona of [senderId], or null when none is allocated.
  VoicePersona? personaFor( String senderId ) => personasBySender[ senderId ];
}

/// Speakerphone snapshot that every loaded state carries.
///
/// Diagnostic only; no screen reads it yet.
mixin SpeakerphoneSnapshotMixin {
  /// Speakerphone record per session id.
  Map<String, SpeakerphoneRecord> get speakerphoneBySession;

  /// Speakerphone record of [sessionId], or null when none is known.
  SpeakerphoneRecord? speakerphoneFor( String sessionId ) =>
      speakerphoneBySession[ sessionId ];
}

/// Nothing has been loaded yet.
class NotificationsInitial extends NotificationState {
  /// Creates the initial state.
  const NotificationsInitial();
}

/// A load is in flight.
class NotificationsLoading extends NotificationState {
  /// Creates the loading state.
  const NotificationsLoading();
}

/// The inbox of senders is loaded.
class NotificationsInboxLoaded extends NotificationState
    with PersonaSnapshotMixin, SpeakerphoneSnapshotMixin {
  /// Senders to list in the inbox.
  final List<SenderSummary> senders;

  /// Account the inbox belongs to.
  final String userEmail;

  @override
  final Map<String, VoicePersona> personasBySender;

  @override
  final Map<String, SpeakerphoneRecord> speakerphoneBySession;

  /// Creates the loaded inbox state.
  const NotificationsInboxLoaded( {
    required this.senders,
    required this.userEmail,
    this.personasBySender      = const {},
    this.speakerphoneBySession = const {},
  } );

  @override
  List<Object?> get props => [ senders, userEmail, personasBySender, speakerphoneBySession ];
}

/// One sender's conversation is loaded.
class NotificationsConversationLoaded extends NotificationState
    with PersonaSnapshotMixin, SpeakerphoneSnapshotMixin {
  /// Sender whose conversation this is.
  final String                            senderId;

  /// Account that owns the conversation.
  final String                            userEmail;

  /// Messages of the conversation.
  final List<ConversationMessage>         messages;

  @override
  final Map<String, VoicePersona>         personasBySender;

  @override
  final Map<String, SpeakerphoneRecord>   speakerphoneBySession;

  /// Creates the loaded conversation state.
  const NotificationsConversationLoaded( {
    required this.senderId,
    required this.userEmail,
    required this.messages,
    this.personasBySender      = const {},
    this.speakerphoneBySession = const {},
  } );

  @override
  List<Object?> get props => [ senderId, userEmail, messages, personasBySender, speakerphoneBySession ];
}

/// A response to a notification is being sent.
class NotificationsResponding extends NotificationState {
  /// Notification being answered.
  final String notificationId;

  /// Creates the sending state for [notificationId].
  const NotificationsResponding( this.notificationId );

  @override
  List<Object?> get props => [ notificationId ];
}

/// The server acknowledged a response.
class NotificationsResponseAcked extends NotificationState {
  /// Server acknowledgement of the response.
  final NotificationResponseAck ack;

  /// Creates the acknowledged state from [ack].
  const NotificationsResponseAcked( this.ack );

  @override
  List<Object?> get props => [ ack.notificationId, ack.status ];
}

/// A request failed.
class NotificationsError extends NotificationState {
  /// Message to show the user.
  final String message;

  /// Creates an error state with [message].
  const NotificationsError( this.message );

  @override
  List<Object?> get props => [ message ];
}

/// Gist generation is in flight.
///
/// The bloc restores the loaded conversation afterwards. The UI reacts with a
/// listener rather than a builder, so the conversation list stays visible.
class NotificationsGistLoading extends NotificationState {
  /// Creates the gist-loading state.
  const NotificationsGistLoading();
}

/// A generated gist is ready; the UI shows it in a bottom sheet.
class NotificationsGistReady extends NotificationState {
  /// Summary text of the conversation.
  final String gist;

  /// Creates the ready state with [gist].
  const NotificationsGistReady( this.gist );

  @override
  List<Object?> get props => [ gist ];
}

/// The dates of one sender's conversation are loaded, each with a count.
class NotificationsSenderDatesLoaded extends NotificationState
    with PersonaSnapshotMixin, SpeakerphoneSnapshotMixin {
  /// Sender whose dates are listed.
  final String            senderId;

  /// Account that owns the conversation.
  final String            userEmail;

  /// One summary per date, keyed YYYY-MM-DD.
  final List<DateSummary> dates;

  @override
  final Map<String, VoicePersona> personasBySender;

  @override
  final Map<String, SpeakerphoneRecord> speakerphoneBySession;

  /// Creates the loaded dates state.
  const NotificationsSenderDatesLoaded( {
    required this.senderId,
    required this.userEmail,
    required this.dates,
    this.personasBySender      = const {},
    this.speakerphoneBySession = const {},
  } );

  @override
  List<Object?> get props => [
    senderId, userEmail,
    dates.length,
    dates.fold<int>( 0, ( s, d ) => s + d.count ),
    personasBySender,
    speakerphoneBySession,
  ];
}

/// One sender's conversation is loaded and grouped by date.
class NotificationsConversationByDateLoaded extends NotificationState
    with PersonaSnapshotMixin, SpeakerphoneSnapshotMixin {
  /// Sender whose conversation this is.
  final String                              senderId;

  /// Account that owns the conversation.
  final String                              userEmail;

  /// Notifications per date, keyed YYYY-MM-DD.
  final Map<String, List<NotificationItem>> byDate;

  @override
  final Map<String, VoicePersona>           personasBySender;

  @override
  final Map<String, SpeakerphoneRecord>     speakerphoneBySession;

  /// Creates the loaded by-date state.
  const NotificationsConversationByDateLoaded( {
    required this.senderId,
    required this.userEmail,
    required this.byDate,
    this.personasBySender      = const {},
    this.speakerphoneBySession = const {},
  } );

  @override
  List<Object?> get props => [
    senderId, userEmail,
    byDate.keys.length,
    byDate.values.fold<int>( 0, ( s, l ) => s + l.length ),
    personasBySender,
    speakerphoneBySession,
  ];
}
