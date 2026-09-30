import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/fleet/data/task_write_repository.dart';

/// Adversarial tests for the SHARED write base, from its first consumer.
///
/// ⚠️ THESE TESTS BELONG TO THE SHARED BASE, NOT TO THE HOLDING AREA. I wrote a
/// second copy of this repository in the Holding Area before Phase 0 was in my tree,
/// and deleted it on the merge — one copy of the four invisible verb rules is the
/// whole point, and a second copy is how they diverge. What survived is the tests,
/// retargeted: Sam's implementation, checked hard.
///
/// 🔴 EVERY TEST HERE ASSERTS THE REQUEST, NOT A MOCK'S RETURN VALUE. A mock that
/// returns what you told it to proves nothing about what went on the wire, and the
/// one defect found in this base — a missing `actor` key — is invisible to any test
/// that only inspects the response.

/// Records what actually went out, and answers with a canned response.
class _Recorder extends Interceptor {
  final List<RequestOptions> calls = [];
  final int     status;
  final dynamic body;

  _Recorder( { this.status = 200, this.body = const <String, dynamic>{} } );

  @override
  void onRequest( RequestOptions options, RequestInterceptorHandler handler ) {
    calls.add( options );
    handler.resolve( Response(
      requestOptions : options,
      statusCode     : status,
      data           : body,
    ) );
  }

  RequestOptions get last => calls.last;
  Map<String, dynamic> get lastBody => ( last.data as Map ).cast<String, dynamic>();
}

( TaskWriteRepository, _Recorder ) _repo( {
  int status = 200,
  dynamic body = const <String, dynamic>{},
} ) {
  final rec = _Recorder( status: status, body: body );
  final dio = Dio( BaseOptions( baseUrl: "http://test" ) )..interceptors.add( rec );
  return ( TaskWriteRepository( dio ), rec );
}

void main() {
  group( "the STATUS door", () {
    test( "approve goes to POST /transition, NOT to the field door", () async {
      // A builder implementing approve as PATCH {status:"queued"} gets a field door
      // silently ignoring an unknown key — a pane that looks wired and changes
      // nothing.
      final ( repo, rec ) = _repo();
      await repo.transition( id: "abc", verb: TaskVerb.approve() );

      expect( rec.last.method, "POST" );
      expect( rec.last.path, endsWith( "/transition" ) );
      expect( rec.lastBody[ "to_status" ], "queued" );
    } );

    test( "the id is URL-ENCODED — driven with a/b?c#d", () async {
      // A raw and an encoded id are byte-identical until the id carries / ? or #,
      // at which point the request silently lands on a DIFFERENT ROUTE.
      final ( repo, rec ) = _repo();
      await repo.transition( id: "a/b?c#d", verb: TaskVerb.approve() );

      expect( rec.last.path, contains( "a%2Fb%3Fc%23d" ) );
      expect( rec.last.path, isNot( contains( "a/b?c#d" ) ) );
    } );

    test( "every write carries authority user_direct", () async {
      // The audit trail keys provenance off it; anything weaker makes an operator's
      // decision read as automation.
      final ( repo, rec ) = _repo();
      await repo.transition( id: "abc", verb: TaskVerb.approve() );
      expect( rec.lastBody[ "authority" ], "user_direct" );
    } );
  } );

  group( "the seven verbs send what the server demands", () {
    test( "park sends park_reason, NOT reason", () async {
      // One verb out of five uses a different key for the same box. Sending
      // `reason` here is accepted-and-ignored.
      final ( repo, rec ) = _repo();
      await repo.transition(
        id: "x", verb: TaskVerb.park( parkReason: "waiting on Rick" ),
      );
      expect( rec.lastBody[ "park_reason" ], "waiting on Rick" );
      expect( rec.lastBody.containsKey( "reason" ), isFalse );
    } );

    test( "unpark sends next_chase_ts as an EXPLICIT null, not an omission", () async {
      // "Send nothing" and "send null" are different requests and only one of them
      // clears. A surviving chase date re-chases Rick about a row already back on
      // his board (his ruling, row 03d3bf78).
      final ( repo, rec ) = _repo();
      await repo.transition( id: "x", verb: TaskVerb.unpark() );

      expect( rec.lastBody.containsKey( "next_chase_ts" ), isTrue,
          reason: "the KEY must be present, not omitted" );
      expect( rec.lastBody[ "next_chase_ts" ], isNull );
    } );

    test( "fixed sends receipt_refs.operator_attestation and NO reason", () async {
      // The multiplexer shipped this bug once — picked the verb up without the
      // receipt and every Fixed press was refused by the server.
      final ( repo, rec ) = _repo();
      await repo.transition(
        id: "x", verb: TaskVerb.fixed( operatorAttestation: "I checked it myself" ),
      );
      final receipts = rec.lastBody[ "receipt_refs" ] as Map;
      expect( receipts[ "operator_attestation" ], "I checked it myself" );
      expect( rec.lastBody.containsKey( "reason" ), isFalse );
    } );

    test( "wont_fix is terminal and carries a reason", () async {
      final ( repo, rec ) = _repo();
      final verb = TaskVerb.wontFix( reason: "superseded" );
      await repo.transition( id: "x", verb: verb );

      expect( verb.terminal, isTrue );
      expect( rec.lastBody[ "to_status" ], "wont_fix" );
      expect( rec.lastBody[ "reason" ], "superseded" );
    } );

    test( "demote and drop each carry their own reason", () async {
      final ( repo, rec ) = _repo();
      await repo.transition( id: "x", verb: TaskVerb.demote( reason: "sent back" ) );
      expect( rec.lastBody[ "to_status" ], "not_approved" );
      expect( rec.lastBody[ "reason" ], "sent back" );

      await repo.transition( id: "x", verb: TaskVerb.drop( reason: "not doing it" ) );
      expect( rec.lastBody[ "to_status" ], "dropped" );
      expect( rec.lastBody[ "reason" ], "not doing it" );
    } );
  } );

  group( "the FIELD door", () {
    test( "PATCHes priority and owner, and never carries a status", () async {
      final ( repo, rec ) = _repo();
      await repo.patchFields( id: "abc", priority: "P1", ownerPersona: "rachel" );

      expect( rec.last.method, "PATCH" );
      expect( rec.last.path, isNot( contains( "transition" ) ) );
      expect( rec.lastBody[ "priority" ], "P1" );
      expect( rec.lastBody[ "owner_persona" ], "rachel" );
      expect( rec.lastBody.containsKey( "status" ), isFalse );
    } );

    test( "an omitted field is not sent, so it cannot clobber", () async {
      final ( repo, rec ) = _repo();
      await repo.patchFields( id: "abc", priority: "P2" );
      expect( rec.lastBody.containsKey( "owner_persona" ), isFalse );
    } );

    test( "its id is encoded too", () async {
      final ( repo, rec ) = _repo();
      await repo.patchFields( id: "a/b", priority: "P2" );
      expect( rec.last.path, contains( "a%2Fb" ) );
    } );

    test( "a patch with nothing to change is refused before the wire", () async {
      final ( repo, rec ) = _repo();
      await expectLater( repo.patchFields( id: "x" ), throwsArgumentError );
      expect( rec.calls, isEmpty, reason: "a no-op should not burn a round trip" );
    } );
  } );

  group( "🔴 the 202 trap", () {
    test( "a 202 awaiting_human_approval THROWS rather than reading as success", () async {
      // A 2xx that Dio does not throw on. Without this branch the answer arrives
      // indistinguishable from a real approval and the pane paints the row
      // approved — a false FACT, not a false red. Throwing is also what routes it
      // into the optimistic-write rollback.
      final ( repo, _ ) = _repo( status: 202, body: {
        "status"    : "awaiting_human_approval",
        "ticket_id" : "tkt-99",
      } );

      await expectLater(
        repo.transition( id: "x", verb: TaskVerb.approve() ),
        throwsA( isA<TaskAwaitingApprovalException>()
            .having( ( e ) => e.ticketId, "ticketId", "tkt-99" ) ),
      );
    } );

    test( "the marker is matched on the STATUS FIELD, never as a substring", () async {
      // A row whose own reason text mentions the marker is an ordinary success; a
      // payload-wide match would call it pending.
      final ( repo, _ ) = _repo( status: 200, body: {
        "status" : "ok",
        "reason" : "not awaiting_human_approval any more",
      } );

      await repo.transition( id: "x", verb: TaskVerb.approve() );  // must not throw
    } );

    test( "an ordinary 200 completes", () async {
      final ( repo, _ ) = _repo( status: 200, body: { "status": "ok" } );
      await repo.transition( id: "x", verb: TaskVerb.approve() );
    } );
  } );

  group( "provenance", () {
    test(
      "every write carries ACTOR as well as authority",
      () async {
        final ( repo, rec ) = _repo();
        await repo.transition( id: "abc", verb: TaskVerb.approve() );
        expect( rec.lastBody[ "actor" ], isNotNull );

        await repo.patchFields( id: "abc", priority: "P1" );
        expect( rec.lastBody[ "actor" ], isNotNull );
      },
      // §4.4: "Both doors carry `actor` and `authority`." This ran SKIPPED from
      // 2026-09-19, when this file found the shared base sending `authority` alone
      // and the defect was reported rather than patched in a peer's file. Sam added
      // the key at 6092096 — both doors, identity resolved per call — and the skip
      // came off here.
    );
  } );
}
