import 'package:equatable/equatable.dart';

import '../data/quick_ask_models.dart';

/// What the capture pipeline is doing right now. Distinct from the JOB's
/// lifecycle state, which lives on the entry.
enum QuickAskPhase { idle, recording, transcribing, submitting, waiting }

/// Which clause of [QuickAskState.canRecord] is false. Exposed as an enum
/// rather than a bare string so a test can assert THAT CLAUSE and no other
/// went false — AC-S2.2a's whole discrimination rests on this.
enum QuickAskBlockReason {
  /// A question is already in flight. Round 1 allows exactly one.
  liveJobInFlight,
  /// A question the server is waiting on has not been answered.
  unansweredPrompt,
  /// The WebSocket is down, so no status could reach us.
  socketDisconnected,
  /// A capture is already running — possibly one started on ANOTHER screen,
  /// since the recorder is a singleton (AC-S2.2c).
  captureInFlight,
}

extension QuickAskBlockReasonText on QuickAskBlockReason {
  /// The stated reason the button shows. One sentence, no jargon — a user
  /// reads this, not an engineer.
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

/// A live Door-A interview turn: the server parked the ask because it needs an
/// argument, and is holding a `pending_id` open for the answer.
///
/// 🔴 The interview is RE-ENTRANT. `flow.py` comments it verbatim — *"Interview
/// continues — re-ask the next arg on the SAME pending_id"* — so a
/// three-argument question is three round trips on ONE id, and a client that
/// treats the first `resume` as terminal renders the answer card after turn one
/// and never asks the second question. That is Rick's ruling 5 silently
/// half-implemented (AC-S4.12).
class QuickAskInterview extends Equatable {
  /// Held open by the server across every turn. Re-posted verbatim.
  final String       pendingId;

  /// The server's question for THIS turn — carried in the response's `answer`.
  final String       question;

  /// What the server still lacks. It shrinks by one each turn; that shrinking
  /// is how a caller can tell a genuine second turn from a repeat.
  final List<String> argsMissing;

  /// 1-based, for "question N" affordances. Round 1 shows no wizard chrome.
  final int          turn;

  const QuickAskInterview( {
    required this.pendingId,
    required this.question,
    this.argsMissing = const [],
    this.turn        = 1,
  } );

  @override
  List<Object?> get props => [ pendingId, question, argsMissing, turn ];
}

class QuickAskState extends Equatable {
  /// Oldest first. The screen renders `.reversed` (AC-S2.3) — newest at the
  /// top, matching `focus_chat_pane.dart:172-178`. Storing newest-first here
  /// instead would put the ordering decision in two places.
  final List<QuickAskEntry> entries;

  final QuickAskPhase phase;

  /// The job we are currently correlating frames to. Null in the
  /// pre-attribution window and whenever nothing is in flight.
  final String? liveJobId;

  /// The transcript of the live question — the buffer's insert-time text key,
  /// and the question bubble the screen renders before any answer exists.
  final String? liveQuestion;

  /// Id of a `response_requested` prompt the user has not answered.
  final String? pendingPromptId;

  /// The live Door-A interview turn, if the ask parked (AC-S4.12). Null
  /// whenever the server is not waiting on an argument.
  final QuickAskInterview? interview;

  final bool connected;

  /// True while the shared recorder is busy — including a capture started by
  /// focus mode's `VoiceReplyField` on the same singleton.
  final bool capturing;

  /// Inline error text (empty transcript, mic denied, submit failure).
  final String? errorMessage;

  /// Set when the watchdog gave up: three consecutive found-nowhere probes
  /// spanning more than the server's own stall threshold.
  final bool lost;

  const QuickAskState( {
    this.entries         = const [],
    this.phase           = QuickAskPhase.idle,
    this.liveJobId,
    this.liveQuestion,
    this.pendingPromptId,
    this.interview,
    this.connected       = false,
    this.capturing       = false,
    this.errorMessage,
    this.lost            = false,
  } );

  /// The four clauses, evaluated in a FIXED order so the exposed reason is
  /// deterministic when more than one is false.
  QuickAskBlockReason? get blockReason {
    if ( liveJobId != null || phase == QuickAskPhase.waiting ) return QuickAskBlockReason.liveJobInFlight;
    if ( pendingPromptId != null || interview != null )        return QuickAskBlockReason.unansweredPrompt;
    if ( !connected )                                          return QuickAskBlockReason.socketDisconnected;
    final busy = capturing
        || phase == QuickAskPhase.transcribing
        || phase == QuickAskPhase.submitting;
    if ( busy ) return QuickAskBlockReason.captureInFlight;
    return null;
  }

  /// The one-live-question guard, as a single predicate — lifting it in round
  /// 2 is one clause, not a redesign.
  bool get canRecord => blockReason == null || phase == QuickAskPhase.recording;

  /// What the button shows when it is disabled. Null when it is enabled.
  String? get blockedMessage => canRecord ? null : blockReason?.message;

  QuickAskEntry? get liveEntry {
    for ( final e in entries.reversed ) {
      if ( e.jobId != null && e.jobId == liveJobId ) return e;
    }
    return null;
  }

  QuickAskState copyWith( {
    List<QuickAskEntry>? entries,
    QuickAskPhase?       phase,
    String?              liveJobId,
    String?              liveQuestion,
    String?              pendingPromptId,
    QuickAskInterview?   interview,
    bool?                connected,
    bool?                capturing,
    String?              errorMessage,
    bool?                lost,
    bool clearLiveJobId       = false,
    bool clearLiveQuestion    = false,
    bool clearPendingPromptId = false,
    bool clearInterview       = false,
    bool clearError           = false,
  } ) => QuickAskState(
    entries         : entries         ?? this.entries,
    phase           : phase           ?? this.phase,
    liveJobId       : clearLiveJobId       ? null : ( liveJobId       ?? this.liveJobId ),
    liveQuestion    : clearLiveQuestion    ? null : ( liveQuestion    ?? this.liveQuestion ),
    pendingPromptId : clearPendingPromptId ? null : ( pendingPromptId ?? this.pendingPromptId ),
    interview       : clearInterview       ? null : ( interview       ?? this.interview ),
    connected       : connected       ?? this.connected,
    capturing       : capturing       ?? this.capturing,
    errorMessage    : clearError           ? null : ( errorMessage    ?? this.errorMessage ),
    lost            : lost            ?? this.lost,
  );

  @override
  List<Object?> get props => [
    entries, phase, liveJobId, liveQuestion, pendingPromptId, interview,
    connected, capturing, errorMessage, lost,
  ];
}
