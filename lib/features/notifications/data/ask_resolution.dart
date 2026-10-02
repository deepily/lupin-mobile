/// Classification of asks that ended without this device's answer.
library;

/// How an ask ended without this device's answer.
///
/// The notification door and the resume door report the same two events differently.
/// The notification door sends 400s saying "already responded" or "grace period exceeded".
/// The resume door sends `already_resumed` and `pending_expired`.
/// Both doors classify through this enum.
/// The two outcomes mean different things to the user, so they never collapse into one error card.
enum AskResolution {
  /// The ask timed out and the server already used its `response_default`.
  expired,

  /// Someone already answered, such as this user on another device.
  ///
  /// Not an error, because the ask is finished.
  answeredElsewhere,

  /// Any other failure; the caller keeps its own failure handling.
  failed;

  /// True when the ask reached a legitimate end rather than an error.
  ///
  /// Both resolved values close the card instead of raising.
  bool get isResolved => this != AskResolution.failed;

  /// Short text to show the user inside the ask card.
  String get userMessage {
    switch ( this ) {
      case AskResolution.expired           : return 'Expired — the question timed out. Ask again.';
      case AskResolution.answeredElsewhere : return 'Already answered — here or on another device.';
      case AskResolution.failed            : return 'Could not send your answer.';
    }
  }
}

/// Classifies a failure message from `POST /api/notify/response`.
///
/// Both outcomes arrive as 400s, so the message body decides, not the status code.
/// Matching ignores case and looks for a substring, because the server embeds the phrases in longer sentences.
AskResolution classifyRespondFailure( String message ) {
  final m = message.toLowerCase();
  if ( m.contains( 'already responded' ) )      return AskResolution.answeredElsewhere;
  if ( m.contains( 'grace period exceeded' ) )  return AskResolution.expired;
  return AskResolution.failed;
}

/// Classifies the `status` string from `POST /api/v2/resume`.
///
/// It maps to the same two outcomes as the 400 messages, delivered on a 200 instead.
AskResolution classifyResumeStatus( String? status ) {
  switch ( status ) {
    case 'pending_expired'  : return AskResolution.expired;
    case 'already_resumed'  : return AskResolution.answeredElsewhere;
    default                 : return AskResolution.failed;
  }
}
