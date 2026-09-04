import 'package:equatable/equatable.dart';

import '../../notifications/data/notification_models.dart';

/// Events driving [QuickAskBloc]. Round 1 is one live question at a time; the
/// one-live-question guard is a single predicate clause so lifting it in round
/// 2 is one line, not a redesign.
sealed class QuickAskEvent extends Equatable {
  const QuickAskEvent();
  @override
  List<Object?> get props => const [];
}

/// FIRST TAP on the record button — start capturing.
///
/// The name predates the tap-to-toggle button and is kept so the twenty-odd
/// existing tests still name the same thing; it means "start", not "a finger
/// is currently down".
class QuickAskRecordPressed extends QuickAskEvent {
  const QuickAskRecordPressed();
}

/// SECOND TAP — stop the capture and transcribe, then HOLD the result.
///
/// 🔴 This no longer submits. The transcript lands in `draftTranscript` and
/// waits for [QuickAskDraftSent]. Under the old hold-to-talk button, letting
/// go WAS the send, so any stumble that broke the press fired a half-finished
/// question at the server.
class QuickAskRecordReleased extends QuickAskEvent {
  const QuickAskRecordReleased();
}

/// The capture was abandoned (system interruption, screen left). Any in-flight
/// transcription result is discarded rather than held.
class QuickAskRecordCancelled extends QuickAskEvent {
  const QuickAskRecordCancelled();
}

/// The user tapped SEND on the held draft. This is the only path from a
/// captured transcript to the server.
class QuickAskDraftSent extends QuickAskEvent {
  const QuickAskDraftSent();
}

/// The user tapped CLEAR on the held draft — throw it away, back to idle.
class QuickAskDraftCleared extends QuickAskEvent {
  const QuickAskDraftCleared();
}

/// A `job_state_transition` frame, verbatim off the wire.
class QuickAskTransitionReceived extends QuickAskEvent {
  final Map<String, dynamic> frame;
  const QuickAskTransitionReceived( this.frame );
  @override
  List<Object?> get props => [ frame ];
}

/// A `notification_queue_update` notification. Two jobs here:
///   * the BELT channel — a notification whose `jobId` matches the live job is
///     independent completion evidence (its `message` IS the answer);
///   * the watchdog reset — a `response_requested` notification is proof of
///     life in the pre-job-id window, where a reconcile has nothing to look up
///     (AC-S1.4b).
class QuickAskNotificationReceived extends QuickAskEvent {
  final NotificationItem notification;
  const QuickAskNotificationReceived( this.notification );
  @override
  List<Object?> get props => [ notification.id ];
}

/// The WebSocket connection state changed (AC-S1.8's stream).
class QuickAskConnectionChanged extends QuickAskEvent {
  final bool connected;
  const QuickAskConnectionChanged( this.connected );
  @override
  List<Object?> get props => [ connected ];
}

/// The user answered the server's Door-A interview question. The bloc re-posts
/// the SAME `pending_id` (AC-S4.12) rather than starting a new ask.
class QuickAskInterviewAnswered extends QuickAskEvent {
  final String answer;
  const QuickAskInterviewAnswered( this.answer );
  @override
  List<Object?> get props => [ answer ];
}

/// The user abandoned the interview without answering.
class QuickAskInterviewCancelled extends QuickAskEvent {
  const QuickAskInterviewCancelled();
}

/// The user tapped the X on a question card — take it off the list.
///
/// 🔴 If that card's job is still RUNNING this also CANCELS it server-side.
/// Hiding a live card locally would leave the job working, still holding the
/// record button, and still speaking its answer when it finished — a card the
/// user deliberately dismissed talking back at them.
///
/// [jobId] is null for the one card that has no id yet: the question submitted
/// but not yet attributed to a job.
class QuickAskEntryDismissed extends QuickAskEvent {
  final String? jobId;
  const QuickAskEntryDismissed( this.jobId );
  @override
  List<Object?> get props => [ jobId ];
}

/// The user dismissed the inline error.
class QuickAskErrorDismissed extends QuickAskEvent {
  const QuickAskErrorDismissed();
}

/// Internal — the silence watchdog fired. Not dispatched by the UI.
class QuickAskWatchdogFired extends QuickAskEvent {
  const QuickAskWatchdogFired();
}

/// The user answered a `response_requested` prompt from the Door B/C channel
/// (AC-S4.6). It posts to `POST /api/notify/response` — a DIFFERENT door from
/// the interview's `/api/v2/resume` — and must leave the in-flight ask alone.
class QuickAskPromptAnswered extends QuickAskEvent {
  final String answer;
  const QuickAskPromptAnswered( this.answer );
  @override
  List<Object?> get props => [ answer ];
}

/// The user dismissed the prompt. This is NOT a local hide: it posts the
/// server's own `response_default` — `no` for Door C — so the blocked ask
/// stops waiting instead of running out its retry ladder in silence.
class QuickAskPromptDismissed extends QuickAskEvent {
  const QuickAskPromptDismissed();
  @override
  List<Object?> get props => [];
}
