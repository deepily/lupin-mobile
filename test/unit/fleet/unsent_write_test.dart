import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/fleet/data/task_write_repository.dart';
import 'package:lupin_mobile/features/fleet/domain/unsent_write.dart';

/// The unsent-write rule — gap G6's pure half.
///
/// 🔴 THE WHOLE ROW TURNS ON ONE CLASSIFICATION: did the server ANSWER? A write that died
/// with no response is one a restored connection can fix. A write the server answered and
/// refused is not, and retrying it on every connectivity edge would re-send the same
/// refused request for the life of the process while the mark never cleared however good
/// the signal got — invisibly. Tiffany ruled it on 2026-09-23: *"A 4xx is a refusal: roll
/// it back and show the server's words, because retrying it just fails again."*
///
/// ─────────────────────────────────────────────────────────────────────────────────
/// 🔴 MUTATION MATRIX — MEASURED, NOT ASSERTED.
///
/// | Test                                   | A | B | C | E |
/// |----------------------------------------|---|---|---|---|
/// | a 4xx is not a transport failure        |🔴 | . | . | . |
/// | a dropped connection is                 |🔴 | . | . | . |
/// | a refusal on retry drops the record     | . |🔴 | . | . |
/// | a 202 on retry drops the record         | . | . |🔴 | . |
/// | a transport failure is KEPT, not retried| . | . | . |🔴 |
/// | one write failing strands no others     | . | . | . |🔴 |
///
///   A — `isTransportFailure` returning true for everything (retry the unretryable)
///   B — a refusal kept in `remaining` instead of reported (a mark that never clears)
///   C — `TaskAwaitingApprovalException` caught as an ordinary failure and kept
///   E — the pass retrying each write in a LOOP until it lands
///
/// ⚠️ AN EARLIER DRAFT OF THIS TABLE CLAIMED THE LOOP DEFECT WAS INVISIBLE HERE and that
/// only the bloc test could catch it. Measured: false — "a transport failure is KEPT, not
/// retried" counts attempts inside one pass and goes red on its own. The claim is
/// corrected rather than deleted, because a matrix written from a guess is a second thing
/// to trust and a first thing to be wrong.

TaskWriteException _transport( DioExceptionType type ) => TaskWriteException(
      'park failed for row-1',
      cause : DioException( requestOptions: RequestOptions( path: '/x' ), type: type ),
    );

TaskWriteException _answered( int status ) => TaskWriteException(
      'park failed for row-1',
      cause : DioException(
        requestOptions : RequestOptions( path: '/x' ),
        type           : DioExceptionType.badResponse,
        response       : Response<dynamic>(
          requestOptions : RequestOptions( path: '/x' ),
          statusCode     : status,
        ),
      ),
    );

UnsentWrite _write( { String id = 'row-1' } ) =>
    UnsentWrite( taskId: id, label: 'Park', verb: TaskVerb.approve() );

void main() {
  group( 'what counts as unsent', () {
    // 🔴 THE ONLY FAILURES A RESTORED CONNECTION CAN FIX.
    test( 'a dropped connection and every timeout are transport failures', () {
      for ( final type in [
        DioExceptionType.connectionError,
        DioExceptionType.connectionTimeout,
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      ] ) {
        expect( isTransportFailure( _transport( type ) ), isTrue,
            reason: '$type is nobody answering — exactly what coming back online fixes' );
      }
    } );

    // 🔴 TIFFANY'S RULING IN ONE ASSERTION. A 4xx is a refusal, not a lost write.
    test( 'a server that answered is NOT a transport failure, whatever it said', () {
      for ( final status in [ 400, 404, 409, 422, 500 ] ) {
        expect( isTransportFailure( _answered( status ) ), isFalse,
            reason: 'a $status would retry forever and the mark would never clear' );
      }
    } );

    // Nothing cancels a write today — the write doors take no token — but if one ever
    // does, silently re-sending a request somebody deliberately abandoned is the
    // opposite of what cancelling means.
    test( 'a cancelled write is not resent behind the operator\'s back', () {
      expect( isTransportFailure( _transport( DioExceptionType.cancel ) ), isFalse );
    } );

    // ⚠️ THE CONSERVATIVE DIRECTION IS "NOT TRANSPORT". Guessing transport on an error
    // nobody has classified retries a request whose failure we do not understand;
    // guessing refusal merely shows the operator a message, which is what the pane did
    // before this row existed.
    test( 'an unrecognised error is not treated as transport', () {
      expect( isTransportFailure( _transport( DioExceptionType.unknown ) ), isFalse );
      expect( isTransportFailure( _transport( DioExceptionType.badCertificate ) ), isFalse );
      expect( isTransportFailure( Exception( 'something else' ) ), isFalse );
      expect( isTransportFailure( const TaskWriteException( 'no cause' ) ), isFalse );
    } );

    // 🔴 A 202 IS NOT A FAILED WRITE AT ALL. The request succeeded and the change did
    // not happen; retrying files a SECOND ticket.
    test( 'a 202 is not a transport failure', () {
      expect(
        isTransportFailure( const TaskAwaitingApprovalException(
          taskId : 'row-1',
          verb   : 'approve',
        ) ),
        isFalse,
      );
    } );
  } );

  group( 'one retry pass', () {
    test( 'every write is attempted exactly once, and a success clears it', () async {
      final attempts = <String>[];
      final outcome  = await retryUnsentWrites(
        { 'a' : _write( id: 'a' ), 'b' : _write( id: 'b' ) },
        ( w ) async => attempts.add( w.taskId ),
      );

      expect( attempts, [ 'a', 'b' ] );
      expect( outcome.remaining, isEmpty, reason: 'both landed; both marks clear' );
      expect( outcome.refusals, isEmpty );
    } );

    test( 'a write that fails on transport again is KEPT, not retried twice', () async {
      var attempts = 0;
      final outcome = await retryUnsentWrites(
        { 'a' : _write( id: 'a' ) },
        ( _ ) async {
          attempts++;
          throw _transport( DioExceptionType.connectionError );
        },
      );

      expect( attempts, 1,
          reason: 'one attempt per write per edge — a loop inside one pass is a guess '
                  'that the second try will go better' );
      expect( outcome.remaining.keys, [ 'a' ], reason: 'the act is still not lost' );
      expect( outcome.refusals, isEmpty );
    } );

    // 🔴 A REFUSAL MET ON RETRY STOPS BEING UNSENT. The connection is plainly fine, so
    // the mark would never clear — and the operator needs the server's own words,
    // because only they can decide whether to change the request.
    test( 'a refusal on retry drops the record and reports the server\'s words', () async {
      final outcome = await retryUnsentWrites(
        { 'a' : _write( id: 'a' ) },
        ( _ ) async => throw _answered( 422 ),
      );

      expect( outcome.remaining, isEmpty,
          reason: 'keeping it would put a mark on the row that no signal could clear' );
      expect( outcome.refusals.single, contains( 'park failed' ) );
    } );

    // 🔴 THE SERVER HAS IT AND HAS FILED A TICKET. Keeping the record would retry it on
    // the next edge and file a SECOND ticket for one press.
    test( 'a 202 on retry drops the record without reporting a failure', () async {
      final outcome = await retryUnsentWrites(
        { 'a' : _write( id: 'a' ) },
        ( _ ) async => throw const TaskAwaitingApprovalException(
          taskId : 'a',
          verb   : 'approve',
        ),
      );

      expect( outcome.remaining, isEmpty );
      expect( outcome.refusals, isEmpty,
          reason: 'a 202 is not a refusal; it is a pending decision and already reported' );
    } );

    test( 'one write failing does not abandon the others', () async {
      final attempts = <String>[];
      final outcome  = await retryUnsentWrites(
        { 'a' : _write( id: 'a' ), 'b' : _write( id: 'b' ), 'c' : _write( id: 'c' ) },
        ( w ) async {
          attempts.add( w.taskId );
          if ( w.taskId == 'b' ) throw _transport( DioExceptionType.connectionError );
        },
      );

      expect( attempts, [ 'a', 'b', 'c' ],
          reason: 'stopping at the first failure would strand every later write' );
      expect( outcome.remaining.keys, [ 'b' ] );
    } );

    test( 'an empty set is a no-op that does not throw', () async {
      final outcome = await retryUnsentWrites( const {}, ( _ ) async => throw 'never' );
      expect( outcome.remaining, isEmpty );
      expect( outcome.refusals, isEmpty );
    } );
  } );
}
