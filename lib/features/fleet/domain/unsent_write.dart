import 'package:dio/dio.dart';
import 'package:equatable/equatable.dart';

import '../data/task_write_repository.dart';

/// One write the operator made that never reached the server.
///
/// 🔴 THE POINT IS THAT THE OPERATOR'S ACTION SURVIVES THE FAILURE. Gap G6: a failed
/// write was rolled back and shown as an error, so the row snapped back and the act was
/// gone — on a phone, where a write dying because the signal dropped in a lift is the
/// ORDINARY case and not the exotic one. Rolling back is right; FORGETTING is not. The
/// row returns to its old state AND wears a mark saying what has not been sent, so the
/// operator can tell "I never pressed that" from "I pressed it and it has not landed".
///
/// 🔴 ONLY A TRANSPORT FAILURE BECOMES ONE OF THESE. Tiffany's ruling, 2026-09-23: *"Only
/// transport failures (no response or timeout) are marked unsent and retried. A 4xx is a
/// refusal: roll it back and show the server's words, because retrying it just fails
/// again."* So a server that ANSWERED and said no is not an unsent write at all — it is
/// an error, handled exactly as it was before this row, with the server's own sentence in
/// front of the operator. Recording it would put a mark on the row that no amount of
/// signal could ever clear, and would re-send the same refused request on every
/// connectivity edge for the life of the process, invisibly.
///
/// ⚠️ THIS IS NOT AN OFFLINE QUEUE, AND THE DISTINCTION IS WORTH HOLDING. No durable
/// store, no replay across a restart, no ordering guarantee between two writes on one
/// row. It is a per-session record of what the network ate, retried on the one signal
/// that can plausibly fix it. Anything more is its own row with its own ruling; anything
/// less loses the act.
class UnsentWrite extends Equatable {
  /// The row this write was made against.
  final String taskId;

  /// What the operator did, in their words — the mark the row wears.
  final String label;

  /// The status verb, when this went through the TRANSITION door. Null for a field edit.
  final TaskVerb? verb;

  /// The priority, when this went through the FIELD door.
  final String? priority;

  /// The owner, when this went through the FIELD door.
  final String? ownerPersona;

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

/// True when [error] means the request never got an answer, so a restored connection
/// could plausibly fix it.
///
/// Requires:
///   - error is what [TaskWriteRepository] threw. A [TaskAwaitingApprovalException] must
///     never reach here — see the note below
///
/// Ensures:
///   - a [TaskWriteException] caused by a Dio failure WITH a response → false (the server
///     answered and refused; show its words)
///   - a connection error or any timeout → true (nobody answered)
///   - a CANCELLED request → false. Nothing cancels a write today — the write doors take
///     no token — but if one ever does, a cancellation is somebody DELIBERATELY
///     abandoning the request, and silently re-sending an abandoned write behind the
///     operator's back is the opposite of what cancelling means
///   - anything unrecognised → false. Guessing "transport" on an error nobody has
///     classified would retry a request whose failure we do not understand; guessing
///     "refusal" merely shows the operator a message, which is what the pane did before
///     this row existed
///
/// ⚠️ A 202 IS NOT A FAILED WRITE. The request SUCCEEDED and the change did not happen;
/// retrying it files a SECOND TICKET. `TaskAwaitingApprovalException` is a distinct type
/// precisely so it cannot be caught as an ordinary failure, and nothing here widens that.
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
    case DioExceptionType.cancel:
    case DioExceptionType.badResponse:
    case DioExceptionType.badCertificate:
    case DioExceptionType.unknown:
      // `badResponse` IS the 4xx case — the server answered and refused, which is
      // Tiffany's ruling in one line. `badCertificate` and `unknown` are not ours to
      // guess about, and the cost of guessing wrong here is a message the operator reads
      // rather than a request nobody watched.
      return false;
  }
}

/// What one retry pass produced.
class RetryOutcome {
  /// The writes still unsent after this pass.
  final Map<String, UnsentWrite> remaining;

  /// Server refusals met during the pass, in the server's own words.
  ///
  /// 🔴 A RETRY THAT MEETS A 4xx STOPS BEING AN UNSENT WRITE AND BECOMES AN ERROR. It
  /// leaves [remaining] — the connection is fine, so the mark would never clear — and its
  /// message comes back here so the pane can put the server's sentence in front of the
  /// operator. Dropping the record silently would tell them their action landed.
  final List<String> refusals;

  const RetryOutcome( { required this.remaining, required this.refusals } );
}

/// Retry every unsent write, once.
///
/// 🔴 ONE ATTEMPT PER WRITE PER RESTORED EDGE — never a loop inside one edge, and never
/// one attempt ever. A later restored edge tries again, because the edge is a genuine new
/// signal and "once ever" would lose an operator's action permanently over a single bad
/// moment, which is the failure G6 exists to prevent. Tiffany approved both halves of
/// that on 2026-09-23 and asked for the pair of tests that pin them: two restores produce
/// two attempts, and one restore produces exactly one.
///
/// Requires:
///   - writes are the currently-unsent records, keyed by task id
///   - send performs one write and throws exactly as the repository does
///
/// Ensures:
///   - every write is attempted AT MOST ONCE per call
///   - a write that succeeds is dropped
///   - a write that fails on TRANSPORT again is kept, and not retried again this call
///   - a write REFUSED by the server is dropped and its message returned in
///     [RetryOutcome.refusals]
///   - a [TaskAwaitingApprovalException] drops the record: the server has the request and
///     has filed a ticket, so it is no longer unsent, and retrying it would file a second
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
      // Landed. The mark clears.
    } on TaskAwaitingApprovalException {
      // The server HAS it and has filed a ticket. Not unsent, and retrying files a second.
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
