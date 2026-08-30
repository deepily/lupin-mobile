/// How an ask ENDED when it did not end with this device's answer —
/// AC-S4.9 (the notification door) and AC-S4.13 (the resume door).
///
/// 🔴 **One vocabulary, two doors, because they are the same two events.**
/// The notification door reports them as 400s carrying "already responded"
/// / "grace period exceeded"; the resume door reports them as
/// `already_resumed` (`flow.py:727`) and `pending_expired` (`:698`). The
/// plan handled the pair on one door and not the other, so they are named
/// once here and both doors classify through it.
///
/// They mean **different things to the user** and must never collapse into
/// one "something went wrong" card:
///   - expired            → the question timed out; ask again.
///   - answeredElsewhere  → you, or another device, already answered it.
///
/// A generic error card satisfies "routes correctly" while telling the user
/// nothing they can act on — which is what AC-S4.13 exists to prevent.
library;

enum AskResolution {
  /// The ask timed out. The server has already substituted its
  /// `response_default`, so there is nothing left to answer.
  expired,

  /// Someone answered it — this user on another device, a proxy, or an
  /// earlier turn of this same conversation. Not an error: the ask is
  /// simply finished.
  answeredElsewhere,

  /// Anything else. The caller keeps its existing failure handling.
  failed;

  /// True when the ask reached a legitimate END rather than an error. Both
  /// resolve the card instead of raising.
  bool get isResolved => this != AskResolution.failed;

  /// What to tell the user. Short, because it renders inside a card.
  String get userMessage {
    switch ( this ) {
      case AskResolution.expired           : return 'Expired — the question timed out. Ask again.';
      case AskResolution.answeredElsewhere : return 'Already answered — here or on another device.';
      case AskResolution.failed            : return 'Could not send your answer.';
    }
  }
}

/// Classify a FAILURE from `POST /api/notify/response` — AC-S4.9.
///
/// Keyed on the message body rather than the status code: both arrive as
/// 400s, so the code alone cannot separate "you already answered this" from
/// "the question is gone" from a genuine client error. Matching is
/// case-insensitive and substring-based because the server composes these
/// into longer sentences.
AskResolution classifyRespondFailure( String message ) {
  final m = message.toLowerCase();
  if ( m.contains( 'already responded' ) )      return AskResolution.answeredElsewhere;
  if ( m.contains( 'grace period exceeded' ) )  return AskResolution.expired;
  return AskResolution.failed;
}

/// Classify a `status` from `POST /api/v2/resume` — AC-S4.13.
///
/// The twins of the two 400s above, arriving as a status string on a 200
/// rather than as an error. Same two meanings, so the same two values.
AskResolution classifyResumeStatus( String? status ) {
  switch ( status ) {
    case 'pending_expired'  : return AskResolution.expired;
    case 'already_resumed'  : return AskResolution.answeredElsewhere;
    default                 : return AskResolution.failed;
  }
}
