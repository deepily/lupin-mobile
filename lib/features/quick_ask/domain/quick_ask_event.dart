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

/// The user pressed and held the record button.
class QuickAskRecordPressed extends QuickAskEvent {
  const QuickAskRecordPressed();
}

/// The user released the button — stop the capture, transcribe, submit.
class QuickAskRecordReleased extends QuickAskEvent {
  const QuickAskRecordReleased();
}

/// The gesture was cancelled mid-press (drag-off, system interruption). Any
/// in-flight transcription result is discarded rather than submitted.
class QuickAskRecordCancelled extends QuickAskEvent {
  const QuickAskRecordCancelled();
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

/// The user dismissed the inline error.
class QuickAskErrorDismissed extends QuickAskEvent {
  const QuickAskErrorDismissed();
}

/// Internal — the silence watchdog fired. Not dispatched by the UI.
class QuickAskWatchdogFired extends QuickAskEvent {
  const QuickAskWatchdogFired();
}
