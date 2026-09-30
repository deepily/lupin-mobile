/// Shared job-lifecycle vocabulary — a VERBATIM mirror of the server's own
/// `STATE_TO_UI_CONTAINER` map (`src/cosa/rest/job_state.py:74`), not a
/// hand-rolled re-derivation.
///
/// Two things a hand-rolled map gets wrong and this one does not:
///   * `stalled → todo`, NOT dead. A stalled job is resumable.
///   * `interrupted → dead`. It is terminal even though nothing emits it
///     over the wire (server-restart sweep only — `job_persistence.py`).
///
/// Lives in the *queue* feature's domain layer so both `QueueDashboardScreen`
/// and Quick Ask import it without either depending on the other.
library;

/// The four UI containers the server groups job states into.
enum JobLane { todo, run, done, dead }

/// Every `JobState` the server can name in a `job_state_transition` frame.
enum JobLifecycleState {
  pending,
  queued,
  scheduled,
  paused,
  running,
  completed,
  failed,
  interrupted,
  cancelled,
  stalled;

  /// Wire name → enum. Returns null for anything unrecognized so the caller
  /// can DROP the frame rather than guess a lane for a state the server grew
  /// after this build shipped.
  static JobLifecycleState? parse( String? raw ) {
    if ( raw == null ) return null;
    for ( final s in JobLifecycleState.values ) {
      if ( s.name == raw ) return s;
    }
    return null;
  }

  /// Verbatim `STATE_TO_UI_CONTAINER`.
  JobLane get lane {
    switch ( this ) {
      case JobLifecycleState.pending:
      case JobLifecycleState.queued:
      case JobLifecycleState.scheduled:
      case JobLifecycleState.paused:
      case JobLifecycleState.stalled:      // resumable, NOT dead
        return JobLane.todo;
      case JobLifecycleState.running:
        return JobLane.run;
      case JobLifecycleState.completed:
        return JobLane.done;
      case JobLifecycleState.failed:
      case JobLifecycleState.cancelled:
      case JobLifecycleState.interrupted:
        return JobLane.dead;
    }
  }

  /// Monotonic ordering for the fold in `QuickAskBloc`: a frame is applied
  /// only when its rank EXCEEDS the current state's, so duplicates and
  /// out-of-order deliveries become no-ops. Terminals bypass the comparison
  /// (see `QuickAskBloc`), so their relative ranks only order them against
  /// non-terminals.
  ///
  /// `stalled` outranks `running` deliberately: it is later in time than the
  /// running state it replaces, even though its lane walks back to `todo`.
  int get rank {
    switch ( this ) {
      case JobLifecycleState.pending:     return 0;
      case JobLifecycleState.scheduled:   return 1;
      case JobLifecycleState.queued:      return 2;
      case JobLifecycleState.paused:      return 3;
      case JobLifecycleState.running:     return 4;
      case JobLifecycleState.stalled:     return 5;
      case JobLifecycleState.completed:   return 6;
      case JobLifecycleState.failed:      return 6;
      case JobLifecycleState.cancelled:   return 6;
      case JobLifecycleState.interrupted: return 6;
    }
  }

  /// Mirrors the server's `TERMINAL_STATES` frozenset (`job_state.py:65`).
  bool get isTerminal =>
      this == JobLifecycleState.completed ||
      this == JobLifecycleState.failed    ||
      this == JobLifecycleState.cancelled ||
      this == JobLifecycleState.interrupted;
}
