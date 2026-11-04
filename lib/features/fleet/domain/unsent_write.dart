import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';

import '../data/task_write_repository.dart';

/// One write the operator made that never reached the server.
///
/// The row rolls back and wears a mark saying what has not been sent, so the operator
/// can tell "never pressed" from "pressed, not landed". Only a transport failure (no
/// response, or a timeout) becomes one of these. A 4xx is a refusal: it rolls back and
/// shows the server's words, because retrying only fails again.
///
/// This is not an offline queue: nothing is stored durably, nothing replays after a
/// restart, and two writes on one row have no ordering guarantee. It is a per-session
/// record, retried on each restored connection.
class UnsentWrite extends Equatable {
  /// The row this write was made against.
  final String taskId;

  /// What the operator did, in their words; the mark the row wears.
  final String label;

  /// The status verb when this was a transition; null for a field edit.
  final TaskVerb? verb;

  /// The new priority when this was a field edit.
  final String? priority;

  /// The new owner when this was a field edit.
  final String? ownerPersona;

  /// Creates the record of one unsent write.
  const UnsentWrite( {
    required this.taskId,
    required this.label,
    this.verb,
    this.priority,
    this.ownerPersona,
  } );

  @override
  List<Object?> get props => [ taskId, label, verb?.name, priority, ownerPersona ];
}

/// True when [error] means the request got no answer, so a restored link could fix it.
///
/// A 202 is not a failed write: it filed a ticket, and a retry would file a second.
/// The exception for it is its own type, [TaskAwaitingApprovalException], so it is never
/// caught as a failure.
///
/// Requires:
///   - error is what [TaskWriteRepository] threw
///   - error is not a [TaskAwaitingApprovalException]
///
/// Ensures:
///   - a [TaskWriteException] caused by a Dio failure with a response returns false
///   - a connection error or any timeout returns true
///   - a cancelled request returns false, so an abandoned write is never re-sent
///   - anything unrecognised returns false, so the operator sees a message instead of a
///     retry of an unclassified failure
bool isTransportFailure( Object error ) {
  if ( error is! TaskWriteException ) return false;
  final cause = error.cause;
  if ( cause is! DioException ) return false;

  switch ( cause.type ) {
    case DioExceptionType.connectionError:
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return true;
    // badResponse is the 4xx case: the server answered and refused. cancel means the
    // request was abandoned on purpose. Both are named so the decision is visible.
    case DioExceptionType.badResponse:
    case DioExceptionType.cancel:
      return false;

    // Everything else returns false, including badCertificate, unknown and any member a
    // future dio adds, so a dio upgrade cannot break compilation on this startup-path
    // file. A new type read as transport would retry a failure nobody understands;
    // read as a refusal it only shows a message.
    //
    // The compiler no longer forces each new member to be classified. Two tests in
    // `test/unit/fleet/unsent_write_test.dart` cover that: one guards
    // `DioExceptionType.values.length` and one lists every member with its answer.
    // When dio grows a member, classify it here before bumping the number.
    default:
      return false;
  }
}

/// What one retry pass produced.
class RetryOutcome {
  /// The writes still unsent after this pass.
  final Map<String, UnsentWrite> remaining;

  /// Server refusals met during the pass, in the server's own words.
  ///
  /// A retry that meets a 4xx leaves [remaining], because the connection is fine and the
  /// mark would never clear. Its message comes back here so the pane can show the
  /// server's sentence instead of implying the action landed.
  final List<String> refusals;

  /// Creates the outcome of one retry pass.
  const RetryOutcome( { required this.remaining, required this.refusals } );
}

/// Retries every unsent write once.
///
/// Each write gets one attempt per restored connection: never a loop within one
/// connection, and never one attempt ever. A later restored connection tries again,
/// because "once ever" would lose the operator's action over one bad moment.
///
/// Requires:
///   - writes are the currently unsent records, keyed by task id
///   - send performs one write and throws as the repository does
///
/// Ensures:
///   - every write is attempted at most once per call
///   - a write that succeeds is dropped
///   - a write that fails on transport again is kept
///   - a write refused by the server is dropped and its message returned in
///     [RetryOutcome.refusals]
///   - a [TaskAwaitingApprovalException] drops the record, because the server holds the
///     request and a retry would file a second ticket
///   - never throws
Future<RetryOutcome> retryUnsentWrites(
  Map<String, UnsentWrite> writes,
  Future<void> Function( UnsentWrite write ) send,
) async {
  final remaining = <String, UnsentWrite>{};
  final refusals  = <String>[];

  for ( final entry in writes.entries ) {
    try {
      await send( entry.value );
      // Landed; the mark clears.
    } on TaskAwaitingApprovalException {
      // The server has it and filed a ticket; retrying would file a second.
    } on Object catch ( e ) {
      if ( isTransportFailure( e ) ) {
        remaining[ entry.key ] = entry.value;
      } else {
        refusals.add( e is TaskWriteException ? e.message : '$e' );
      }
    }
  }

  return RetryOutcome( remaining: remaining, refusals: refusals );
}
