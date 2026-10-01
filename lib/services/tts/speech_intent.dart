/// Which inbound items the user is expected to act on, and so must be heard.
///
/// Audibility keys on "something is waiting on the user": an answer they asked for, or a question
/// the system is blocked on. A question matters more, because a confirm holds the server for up to
/// about 210 seconds and then defaults to "no" if nobody replies.
/// Design: src/docs/decisions/README.md (R-TTS-actionable)
///
/// One predicate has two enforcement points. The same test decides whether speech is `verbatim` in
/// `TtsOrchestrator` and whether the item survives `FocusChatBloc`'s stop-list drop. Two copies would drift.
library;

/// Persona-less sender that every `/api/v2/flow` question is sent from.
///
/// `TtsSender.isPersona` is false for it, so `_systemSenderMuted` drops it whenever `speakSystemSenders`
/// is off. That setting would lose the question silently.
const String askFlowSenderId = 'ask.flow@lupin.deepily.ai';

/// True when the item is a question the system is waiting on.
///
/// Two arms, and the second is not redundant:
///   1. `response_requested == true`: a question that blocks the ask, such as a near-match confirm.
///   2. the `ask.flow` sender with no `job_id`: the in-place argument interview ("which city?").
///      `_speak()` dispatches a fire-and-forget `AsyncNotificationRequest` that does not carry
///      `response_requested`, so arm 1 alone cannot see it.
///
/// The `job_id` test keeps arm 2 tight. Every flow question speaks with no `job_id`.
/// The answer path passes a real one, so arm 2 skips answers and the "New ... job" acknowledgement.
/// Arm 2 also catches the receptionist degrade line, which is likewise sent with no `job_id`.
/// That line is speech the user should hear, so the widening is accepted.
bool isActionableQuestion( {
  required bool responseRequested,
  String?       senderId,
  String?       jobId,
} ) {
  if ( responseRequested ) return true;
  final fromFlow = senderId == askFlowSenderId;
  final noJob    = ( jobId ?? '' ).isEmpty;
  return fromFlow && noJob;
}

/// True when the item should be spoken with `verbatim: true`.
///
/// Verbatim skips the system-sender mute and the preview-fraction cut.
/// [isLiveAskAnswer] is the answer arm. The host passes a predicate over the `job_id`
/// (Quick Ask exposes one). The enqueue stays in one place, and this file knows nothing about blocs.
///
/// This does not decide whether the item is spoken at all. The stop-list still holds, and `verbatim`
/// never bypasses it.
bool shouldSpeakVerbatim( {
  required bool responseRequested,
  String?       senderId,
  String?       jobId,
  bool Function( String jobId )? isLiveAskAnswer,
} ) {
  if ( isActionableQuestion(
    responseRequested : responseRequested,
    senderId          : senderId,
    jobId             : jobId,
  ) ) {
    return true;
  }
  final id = jobId ?? '';
  if ( id.isEmpty || isLiveAskAnswer == null ) return false;
  return isLiveAskAnswer( id );
}
