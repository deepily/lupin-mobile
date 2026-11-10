/// Event-loop turns that [drainEventLoop] gives to pending work.
///
/// A stubbed request, its bloc handler and the state it emits need a few dozen turns.
const int kDrainTurns = 200;

/// Lets pending futures run by counting event-loop turns instead of watching the clock.
///
/// A wait of 60 milliseconds bets the work ends before a timer fires. On a busy
/// machine the process stalls. The timer then comes due first and jumps ahead of the
/// queued work, so the test reads state too early. A turn count cannot be overtaken.
///
/// Requires:
///   - the awaited work needs no real elapsed time (no timer, no debounce)
///
/// Ensures:
///   - returns after [turns] event-loop turns, however slowly the machine runs them
Future<void> drainEventLoop( { int turns = kDrainTurns } ) async {
  for ( var i = 0; i < turns; i++ ) {
    await Future<void>.delayed( Duration.zero );
  }
}
