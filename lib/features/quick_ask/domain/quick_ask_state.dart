import 'package:equatable/equatable.dart';

import '../data/quick_ask_models.dart';

/// What the capture pipeline is doing right now.
///
/// It is distinct from the job's lifecycle state, which lives on the entry.
/// [review] is the stop-and-hold step. The transcript lands in [QuickAskState.draftTranscript]
/// and waits there. Nothing leaves the phone until the user taps send.
enum QuickAskPhase {
  /// Nothing is happening.
  idle,

  /// The microphone is capturing.
  recording,

  /// The capture is being transcribed.
  transcribing,

  /// A transcript is held, unsent.
  review,

  /// The question is being posted.
  submitting,

  /// The question is posted and an answer is awaited.
  waiting
}

/// Which clause of [QuickAskState.canRecord] is false.
///
/// It is an enum rather than a bare string so a test can assert that exactly one clause went false.
enum QuickAskBlockReason {
  /// A question is already in flight; only one is allowed.
  liveJobInFlight,

  /// A question the server is waiting on has not been answered.
  unansweredPrompt,

  /// The WebSocket is down, so no status could reach the phone.
  socketDisconnected,

  /// A capture is already running, possibly on another screen.
  ///
  /// The recorder is a singleton.
  captureInFlight,
}

/// The user-facing text for a [QuickAskBlockReason].
extension QuickAskBlockReasonText on QuickAskBlockReason {
  /// The reason the record button shows: one plain sentence for the user.
  String get message {
    switch ( this ) {
      case QuickAskBlockReason.liveJobInFlight:
        return 'Waiting on your last question';
      case QuickAskBlockReason.unansweredPrompt:
        return 'Answer the question above first';
      case QuickAskBlockReason.socketDisconnected:
        return 'Not connected — reconnecting';
      case QuickAskBlockReason.captureInFlight:
        return 'Already recording somewhere else';
    }
  }
}

/// A live interview turn: the server parked the ask because it needs an argument.
///
/// The server holds a `pending_id` open for the answer.
/// The interview is re-entrant: a three-argument question is three round trips on one id.
/// A client that treats the first resume as final would show the answer card after turn one
/// and never ask the second question.
class QuickAskInterview extends Equatable {
  /// The id the server holds open across every turn; it is re-posted verbatim.
  final String       pendingId;

  /// The server's question for this turn, carried in the response's `answer`.
  final String       question;

  /// What the server still lacks.
  ///
  /// It shrinks by one each turn, which is how a caller tells a real second turn from a repeat.
  final List<String> argsMissing;

  /// The 1-based turn number.
  final int          turn;

  /// Creates a turn.
  const QuickAskInterview( {
    required this.pendingId,
    required this.question,
    this.argsMissing = const [],
    this.turn        = 1,
  } );

  @override
  List<Object?> get props => [ pendingId, question, argsMissing, turn ];
}

/// A `response_requested` notification the user has not answered yet, held in full.
///
/// The commonest case is the near-match confirm.
/// When a question scores close to a cached one, the server asks "Is that the same as: ...?".
/// It blocks the ask's own HTTP thread until the reply comes.
/// So the prompt arrives while the ask is in flight, and the ask is waiting on it.
/// Holding only the id meant the question could never be shown or answered.
/// The confirm then always timed out to its default of "no".
/// Answering it must leave the pending ask undisturbed.
class QuickAskPrompt extends Equatable {
  /// The `notification_id`, which `POST /api/notify/response` is keyed on.
  final String id;

  /// The question text as it arrived.
  ///
  /// For the near-match confirm this is the sentence naming the cached question.
  final String question;

  /// The response kind: `yes_no`, `multiple_choice`, `open_ended` or `open_ended_batch`.
  ///
  /// The near-match confirm is always `yes_no`; the others can arrive on the same channel.
  final String? responseType;

  /// What the server substitutes if nobody answers in time; the near-match confirm sends `no`.
  ///
  /// A deliberate dismissal posts this value, which turns a silent timeout into a stated answer.
  final String? responseDefault;

  /// The choices for a `multiple_choice` prompt, as sent.
  final Map<String, dynamic>? responseOptions;

  /// Creates a prompt.
  const QuickAskPrompt( {
    required this.id,
    required this.question,
    this.responseType,
    this.responseDefault,
    this.responseOptions,
  } );

  /// Whether this is a yes-or-no prompt; an absent type counts as yes-or-no.
  bool get isYesNo => responseType == null || responseType == 'yes_no';

  /// The answer a dismissal posts: the server's default, else `no` for yes-or-no, else empty.
  ///
  /// `no` is a floor, not a preference: the confirmer treats a timeout and an error alike as a no.
  /// Sending it explicitly makes the server stop waiting instead of running out its retry ladder.
  String get defaultAnswer => ( responseDefault != null && responseDefault!.isNotEmpty )
      ? responseDefault!
      : ( isYesNo ? 'no' : '' );

  @override
  List<Object?> get props => [ id, question, responseType, responseDefault, responseOptions ];
}

/// Everything the Quick Ask screen renders, and the guards on the record button.
class QuickAskState extends Equatable {
  /// The cards, oldest first.
  ///
  /// The screen renders them reversed, newest at the top.
  /// Storing newest-first here would put the ordering decision in two places.
  final List<QuickAskEntry> entries;

  /// What the capture pipeline is doing.
  final QuickAskPhase phase;

  /// The job that frames are being correlated to.
  ///
  /// Null before a job id exists and whenever nothing is in flight.
  final String? liveJobId;

  /// The transcript of the live question.
  ///
  /// It is the buffer's insert-time text key and the question bubble shown before any answer exists.
  final String? liveQuestion;

  /// A `response_requested` prompt the user has not answered.
  ///
  /// It is held whole, not as a bare id: the id alone blocks the record button and can never be answered.
  final QuickAskPrompt? pendingPrompt;

  /// The prompt's id alone, for callers that only gate on presence.
  String? get pendingPromptId => pendingPrompt?.id;

  /// The live interview turn, or null whenever the server is not waiting on an argument.
  final QuickAskInterview? interview;

  /// Whether the WebSocket is connected.
  final bool connected;

  /// Whether the shared recorder is busy.
  ///
  /// This includes a capture started by focus mode's `VoiceReplyField` on the same singleton.
  final bool capturing;

  /// The captured transcript being held, unsent.
  ///
  /// It is non-null exactly while [QuickAskPhase.review] shows.
  /// The user sends it or clears it, and nothing else moves it.
  final String? draftTranscript;

  /// Inline error text, such as an empty transcript, a denied microphone or a failed submit.
  final String? errorMessage;

  /// Whether the watchdog gave up.
  ///
  /// It gives up after three consecutive found-nowhere probes spanning more than the server's stall threshold.
  final bool lost;

  /// The screen's Review first or Send immediately control, as last written.
  ///
  /// It is for rendering only. The release path reads `QuickAskPreferences` at release time
  /// and never this field.
  /// So a flip made outside the bloc still takes effect on the next recording.
  /// The only writer is `QuickAskSendModeChanged`.
  final bool sendImmediately;

  /// Creates a state; every field has an idle default.
  const QuickAskState( {
    this.entries         = const [],
    this.phase           = QuickAskPhase.idle,
    this.liveJobId,
    this.liveQuestion,
    this.pendingPrompt,
    this.interview,
    this.connected       = false,
    this.capturing       = false,
    this.draftTranscript,
    this.errorMessage,
    this.lost            = false,
    this.sendImmediately = false,
  } );

  /// Whether a captured question is held, waiting to be sent.
  bool get hasDraft => draftTranscript != null && draftTranscript!.isNotEmpty;

  /// The first false clause of [canRecord], or null when recording is allowed.
  ///
  /// The four clauses are checked in a fixed order, so the reason is deterministic when several are false.
  QuickAskBlockReason? get blockReason {
    if ( liveJobId != null || phase == QuickAskPhase.waiting ) return QuickAskBlockReason.liveJobInFlight;
    if ( pendingPrompt != null || interview != null )          return QuickAskBlockReason.unansweredPrompt;
    if ( !connected )                                          return QuickAskBlockReason.socketDisconnected;
    final busy = capturing
        || phase == QuickAskPhase.transcribing
        || phase == QuickAskPhase.submitting;
    if ( busy ) return QuickAskBlockReason.captureInFlight;
    return null;
  }

  /// Whether the record button is live: the one-live-question guard as a single predicate.
  ///
  /// The microphone is inert while a draft is held. Clear and send are the only way out,
  /// so a stray tap cannot throw away a question the user already spoke.
  bool get canRecord =>
      ( blockReason == null || phase == QuickAskPhase.recording ) && !hasDraft;

  /// What the button shows when it is disabled. Null when it is enabled.
  String? get blockedMessage => canRecord ? null : blockReason?.message;

  /// The entry for [liveJobId], or null when there is none.
  QuickAskEntry? get liveEntry {
    for ( final e in entries.reversed ) {
      if ( e.jobId != null && e.jobId == liveJobId ) return e;
    }
    return null;
  }

  /// Returns a copy with the given fields replaced.
  ///
  /// The `clear` flags reset a nullable field to null, which a null argument cannot express.
  QuickAskState copyWith( {
    List<QuickAskEntry>? entries,
    QuickAskPhase?       phase,
    String?              liveJobId,
    String?              liveQuestion,
    QuickAskPrompt?      pendingPrompt,
    QuickAskInterview?   interview,
    bool?                connected,
    bool?                capturing,
    String?              draftTranscript,
    String?              errorMessage,
    bool?                lost,
    bool?                sendImmediately,
    bool clearLiveJobId       = false,
    bool clearLiveQuestion    = false,
    bool clearPendingPrompt   = false,
    bool clearInterview       = false,
    bool clearDraft           = false,
    bool clearError           = false,
  } ) => QuickAskState(
    entries         : entries         ?? this.entries,
    phase           : phase           ?? this.phase,
    liveJobId       : clearLiveJobId       ? null : ( liveJobId       ?? this.liveJobId ),
    liveQuestion    : clearLiveQuestion    ? null : ( liveQuestion    ?? this.liveQuestion ),
    pendingPrompt   : clearPendingPrompt   ? null : ( pendingPrompt   ?? this.pendingPrompt ),
    interview       : clearInterview       ? null : ( interview       ?? this.interview ),
    connected       : connected       ?? this.connected,
    capturing       : capturing       ?? this.capturing,
    draftTranscript : clearDraft            ? null : ( draftTranscript ?? this.draftTranscript ),
    errorMessage    : clearError           ? null : ( errorMessage    ?? this.errorMessage ),
    lost            : lost            ?? this.lost,
    sendImmediately : sendImmediately ?? this.sendImmediately,
  );

  @override
  List<Object?> get props => [
    entries, phase, liveJobId, liveQuestion, pendingPrompt, interview,
    connected, capturing, draftTranscript, errorMessage, lost, sendImmediately,
  ];
}
