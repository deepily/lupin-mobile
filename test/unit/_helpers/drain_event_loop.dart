import 'package:flutter_test/flutter_test.dart' show fail;

/// Event-loop turns that [drainEventLoop] gives to pending work.
///
/// A stubbed request, its bloc handler and the state it emits need a few dozen turns.
const int kDrainTurns = 200;

/// How long [waitUntil] waits before it fails the test.
///
/// Only a real hang can reach it. A fixed wait of a few tens of milliseconds is not
/// enough on a loaded machine, and this bound costs nothing when the condition holds.
const Duration kWaitUntilDeadline = Duration( seconds: 10 );

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

/// Waits until [condition] holds, letting real time pass between looks.
///
/// Use it when the awaited work needs a real timer to fire, such as a timeout or a
/// sampling interval, so [drainEventLoop] cannot finish it. A fixed wait bets the timer
/// fires within the wait; this waits for the outcome itself.
///
/// Requires:
///   - condition has no side effects
///
/// Ensures:
///   - returns as soon as condition is true, however slow the machine is
///   - fails the test with [what] if it is still false after [deadline]
Future<void> waitUntil(
  bool Function() condition,
  String what, {
  Duration deadline = kWaitUntilDeadline,
} ) async {
  final stopAt = DateTime.now().add( deadline );
  while ( !condition() ) {
    if ( DateTime.now().isAfter( stopAt ) ) fail( "timed out waiting for: $what" );
    await Future<void>.delayed( const Duration( milliseconds: 2 ) );
  }
}
