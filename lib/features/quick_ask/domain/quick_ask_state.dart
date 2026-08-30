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
    this.connected       = false,
    this.capturing       = false,
    this.errorMessage,
    this.lost            = false,
  } );

  /// The four clauses, evaluated in a FIXED order so the exposed reason is
  /// deterministic when more than one is false.
  QuickAskBlockReason? get blockReason {
    if ( liveJobId != null || phase == QuickAskPhase.waiting ) return QuickAskBlockReason.liveJobInFlight;
    if ( pendingPromptId != null )                             return QuickAskBlockReason.unansweredPrompt;
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
    bool?                connected,
    bool?                capturing,
    String?              errorMessage,
    bool?                lost,
    bool clearLiveJobId       = false,
    bool clearLiveQuestion    = false,
    bool clearPendingPromptId = false,
    bool clearError           = false,
  } ) => QuickAskState(
    entries         : entries         ?? this.entries,
    phase           : phase           ?? this.phase,
    liveJobId       : clearLiveJobId       ? null : ( liveJobId       ?? this.liveJobId ),
    liveQuestion    : clearLiveQuestion    ? null : ( liveQuestion    ?? this.liveQuestion ),
    pendingPromptId : clearPendingPromptId ? null : ( pendingPromptId ?? this.pendingPromptId ),
    connected       : connected       ?? this.connected,
    capturing       : capturing       ?? this.capturing,
    errorMessage    : clearError           ? null : ( errorMessage    ?? this.errorMessage ),
    lost            : lost            ?? this.lost,
  );

  @override
  List<Object?> get props => [
    entries, phase, liveJobId, liveQuestion, pendingPromptId,
    connected, capturing, errorMessage, lost,
  ];
}
