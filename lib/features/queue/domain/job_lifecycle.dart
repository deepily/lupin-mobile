/// Shared job-lifecycle vocabulary, a verbatim mirror of the server's state-to-lane map.
///
/// A hand-rolled map would get two states wrong:
///   - `stalled` belongs in the todo lane, not dead, because a stalled job is resumable.
///   - `interrupted` belongs in the dead lane. It is terminal even though only the
///     server-restart sweep produces it and nothing emits it over the wire.
///
/// It lives in the queue feature's domain layer so `QueueDashboardScreen` and Quick Ask
/// can both import it without either depending on the other.
library;

/// The four UI containers the server groups job states into.
enum JobLane {
  /// Waiting or resumable work.
  todo,

  /// Work that is running now.
  run,

  /// Work that finished successfully.
  done,

  /// Work that ended without success.
  dead
}

/// Every `JobState` the server can name in a `job_state_transition` frame.
enum JobLifecycleState {
  /// Created and not yet queued.
  pending,

  /// Waiting in the queue.
  queued,

  /// Waiting for its scheduled time.
  scheduled,

  /// Held by the user.
  paused,

  /// Running now.
  running,

  /// Finished successfully.
  completed,

  /// Ended with an error.
  failed,

  /// Ended by a server restart.
  interrupted,

  /// Cancelled by the user.
  cancelled,

  /// Stopped making progress; resumable.
  stalled;

  /// Parses a wire name, returning null for anything unrecognized.
  ///
  /// The caller can then drop the frame instead of guessing a lane for a state
  /// the server grew after this build shipped.
  static JobLifecycleState? parse( String? raw ) {
    if ( raw == null ) return null;
    for ( final s in JobLifecycleState.values ) {
      if ( s.name == raw ) return s;
    }
    return null;
  }

  /// The lane this state belongs to, as the server maps it.
  JobLane get lane {
    switch ( this ) {
      case JobLifecycleState.pending:
      case JobLifecycleState.queued:
      case JobLifecycleState.scheduled:
      case JobLifecycleState.paused:
      case JobLifecycleState.stalled:      // resumable, so not dead
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

  /// Monotonic ordering used by the fold in `QuickAskBloc`.
  ///
  /// A frame is applied only when its rank exceeds the current state's,
  /// so duplicate and out-of-order deliveries become no-ops.
  /// Terminal states bypass the comparison, so their ranks only order them against non-terminals.
  /// `stalled` outranks `running` because it is later in time than the state it replaces,
  /// even though its lane goes back to todo.
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

  /// True for the four states the server treats as terminal.
  bool get isTerminal =>
      this == JobLifecycleState.completed ||
      this == JobLifecycleState.failed    ||
      this == JobLifecycleState.cancelled ||
      this == JobLifecycleState.interrupted;
}
