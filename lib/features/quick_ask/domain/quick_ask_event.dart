import 'package:equatable/equatable.dart';

import '../../notifications/data/notification_models.dart';
import '../../queue/data/queue_models.dart';

/// Events driving [QuickAskBloc].
///
/// There is one live question at a time. The guard is a single predicate clause,
/// so allowing several live questions later is a one-line change.
sealed class QuickAskEvent extends Equatable {
  /// Creates an event.
  const QuickAskEvent();
  @override
  List<Object?> get props => const [];
}

/// First tap on the record button: start capturing.
///
/// The name predates the tap-to-toggle button. It means "start", not "a finger is down".
class QuickAskRecordPressed extends QuickAskEvent {
  /// Creates the event.
  const QuickAskRecordPressed();
}

/// Second tap: stop the capture, transcribe, then hold the result.
///
/// This does not submit. The transcript lands in `draftTranscript` and waits for
/// [QuickAskDraftSent], so a stumble cannot fire a half-finished question at the server.
class QuickAskRecordReleased extends QuickAskEvent {
  /// Creates the event.
  const QuickAskRecordReleased();
}

/// The capture was abandoned, by a system interruption or by leaving the screen.
///
/// Any in-flight transcription result is discarded rather than held.
class QuickAskRecordCancelled extends QuickAskEvent {
  /// Creates the event.
  const QuickAskRecordCancelled();
}

/// The user tapped Send on the held draft.
///
/// It is the only path from a captured transcript to the server.
class QuickAskDraftSent extends QuickAskEvent {
  /// Creates the event.
  const QuickAskDraftSent();
}

/// The user tapped Clear on the held draft: throw it away and return to idle.
class QuickAskDraftCleared extends QuickAskEvent {
  /// Creates the event.
  const QuickAskDraftCleared();
}

/// A `job_state_transition` frame, verbatim off the wire.
class QuickAskTransitionReceived extends QuickAskEvent {
  /// The raw frame.
  final Map<String, dynamic> frame;

  /// Creates the event from a raw frame.
  const QuickAskTransitionReceived( this.frame );
  @override
  List<Object?> get props => [ frame ];
}

/// A `notification_queue_update` notification.
///
/// It does two jobs:
/// - A notification whose `jobId` matches the live job is independent completion evidence,
///   and its `message` is the answer.
/// - A `response_requested` notification resets the watchdog, because in the window before a
///   job id exists a reconcile has nothing to look up and this is the only proof of life.
class QuickAskNotificationReceived extends QuickAskEvent {
  /// The notification.
  final NotificationItem notification;

  /// Creates the event from a notification.
  const QuickAskNotificationReceived( this.notification );
  @override
  List<Object?> get props => [ notification.id ];
}

/// The WebSocket connection state changed.
class QuickAskConnectionChanged extends QuickAskEvent {
  /// Whether the socket is now connected.
  final bool connected;

  /// Creates the event.
  const QuickAskConnectionChanged( this.connected );
  @override
  List<Object?> get props => [ connected ];
}

/// The user answered the server's interview question.
///
/// The bloc re-posts the same `pending_id` rather than starting a new ask.
class QuickAskInterviewAnswered extends QuickAskEvent {
  /// The answer text.
  final String answer;

  /// Creates the event.
  const QuickAskInterviewAnswered( this.answer );
  @override
  List<Object?> get props => [ answer ];
}

/// The user abandoned the interview without answering.
class QuickAskInterviewCancelled extends QuickAskEvent {
  /// Creates the event.
  const QuickAskInterviewCancelled();
}

/// The user tapped the X on a question card: take it off the list.
///
/// If that card's job is still running this also cancels it server-side.
/// Hiding a live card locally would leave the job working, holding the record button
/// and speaking its answer when it finished.
///
/// [jobId] is null for the one card with no id yet: the question submitted but not yet
/// attributed to a job.
class QuickAskEntryDismissed extends QuickAskEvent {
  /// The dismissed card's job id, or null before attribution.
  final String? jobId;

  /// Creates the event.
  const QuickAskEntryDismissed( this.jobId );
  @override
  List<Object?> get props => [ jobId ];
}

/// The user dismissed the inline error.
class QuickAskErrorDismissed extends QuickAskEvent {
  /// Creates the event.
  const QuickAskErrorDismissed();
}

/// Internal: the silence watchdog fired. The UI never dispatches it.
class QuickAskWatchdogFired extends QuickAskEvent {
  /// Creates the event.
  const QuickAskWatchdogFired();
}

/// The user answered a `response_requested` prompt from the second or third channel.
///
/// It posts to `POST /api/notify/response`, a different endpoint from the interview's
/// `/api/v2/resume`, and it leaves the in-flight ask alone.
class QuickAskPromptAnswered extends QuickAskEvent {
  /// The answer text.
  final String answer;

  /// Creates the event.
  const QuickAskPromptAnswered( this.answer );
  @override
  List<Object?> get props => [ answer ];
}

/// Internal: one event read off a send-immediately stream, re-entering the bloc.
///
/// Re-entry keeps every state change inside a handler.
/// [epoch] is the capture's `_opEpoch` at release. A cancel, a clear or a new press bumps the
/// live epoch, so an arrival whose [epoch] no longer matches is stale.
/// A stale result carrying a job id is cancelled, and anything else is dropped.
///
/// It is public and declared here because [QuickAskEvent] is sealed.
/// The UI never dispatches it.
class QuickAskSpokenEventArrived extends QuickAskEvent {
  /// The capture epoch the event belongs to.
  final int            epoch;

  /// The event read off the stream.
  final SpokenAskEvent event;

  /// Creates the event.
  const QuickAskSpokenEventArrived( this.epoch, this.event );
  @override
  List<Object?> get props => [ epoch, event ];
}

/// The user picked Review first or Send immediately on the screen's control.
///
/// This is the only writer of the send mode. The bloc writes `QuickAskPreferences` first,
/// then emits `QuickAskState.sendImmediately` so the control re-renders.
/// It is public and declared here because [QuickAskEvent] is sealed.
class QuickAskSendModeChanged extends QuickAskEvent {
  /// Whether a finished capture is sent without review.
  final bool sendImmediately;

  /// Creates the event.
  const QuickAskSendModeChanged( this.sendImmediately );
  @override
  List<Object?> get props => [ sendImmediately ];
}

/// The user dismissed the prompt.
///
/// This is not a local hide. It posts the server's own `response_default`, `no` for the
/// third channel, so the blocked ask stops waiting instead of running out its retry ladder.
class QuickAskPromptDismissed extends QuickAskEvent {
  /// Creates the event.
  const QuickAskPromptDismissed();
  @override
  List<Object?> get props => [];
}
