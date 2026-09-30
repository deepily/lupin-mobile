/// Which inbound items the user is EXPECTED TO ACT ON — AC-S3.6, AC-S3.6b,
/// AC-S3.8 (plan 2026.08.29 §6).
///
/// The rule generalises rather than growing a special case per surface.
/// Audibility keys on *"something is waiting on the user"*, which covers
/// exactly two things: an **answer they deliberately asked for** (Rick's
/// ruling 4), and a **question the system is blocked on** — the latter more
/// strongly, since a Door C confirm holds the server for up to ~210s and
/// then defaults to "no" if nobody replies.
///
/// 🔴 **One predicate, TWO enforcement points, and that is the whole
/// design.** The same "expected to act on" test decides (a) whether speech
/// is `verbatim` in `TtsOrchestrator`, and (b) whether the item survives
/// `FocusChatBloc`'s bloc-level stop-list drop (AC-S3.8 item 2). Rick ruled
/// the same principle at both — *"show the answer… mute it and mark it"* —
/// and the second point was invisible until someone read the ingest path.
/// Two copies of this test would drift; there is one.
library;

/// The persona-less sender every `/api/v2/flow` question is sent from.
/// `TtsSender.isPersona` is false for it, so `_systemSenderMuted` drops it
/// whenever `speakSystemSenders` is off — the configuration that loses the
/// question silently today.
const String askFlowSenderId = 'ask.flow@lupin.deepily.ai';

/// True when the item is a QUESTION the system is waiting on.
///
/// Two arms, and the second is not redundant:
///
/// 1. **`response_requested == true`** — Door B, and Door C's near-match
///    confirm, which blocks the ask.
/// 2. **`ask.flow` sender AND no `job_id`** — Door A, the in-place argument
///    interview ("which city?"). `_speak()` dispatches an
///    `AsyncNotificationRequest`, documented fire-and-forget, which does
///    **not** carry `response_requested` — so arm 1 alone cannot see it,
///    and an implementation keyed only on `response_requested` passes the
///    Door C case while losing every turn of Rick's ruling-5 interview.
///
/// The `job_id` half of arm 2 is what keeps it tight: every flow QUESTION
/// calls `_speak( job_id: None )` while the ANSWER path passes a real
/// `job_id`, so this selects questions without sweeping in answers or the
/// "New … job" acknowledgement.
///
/// ⚠️ Deliberate widening, named so it is not discovered later: arm 2 also
/// catches the receptionist degrade line, which is likewise sent with no
/// `job_id`. That is user-facing speech the user is meant to hear, so it is
/// acceptable — but it is a decision, not an accident.
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

/// True when the item should be spoken with `verbatim: true` — skipping
/// the system-sender mute and the preview-fraction cut (Rick's ruling 4).
///
/// [isLiveAskAnswer] is the answer arm: the host passes a predicate over
/// the item's `job_id` (Quick Ask exposes one), keeping the enqueue in one
/// place rather than teaching this file about blocs.
///
/// 🔴 This does **not** decide whether the item is spoken at all — the
/// stop-list (gate 1) still holds, and `verbatim` never bypasses it
/// (OSQ3, closed by Rick's direct keypress).
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
