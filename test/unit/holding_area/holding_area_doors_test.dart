import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/holding_area/data/holding_area_repository.dart';
import 'package:lupin_mobile/features/holding_area/data/task_verbs.dart';

/// The two write doors, the seven verbs, and the 202 trap.
///
/// Every test here pins something that has already cost someone a shipped bug, in
/// this fleet, with a receipt in the plan.

/// Records what actually went on the wire, so a test can assert the REQUEST rather
/// than a mock's return value.
class _Recorder extends Interceptor {
  final List<RequestOptions> calls = [];
  final int      status;
  final dynamic  body;

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
}

( Dio, _Recorder ) _dio( { int status = 200, dynamic body = const <String, dynamic>{} } ) {
  final rec = _Recorder( status: status, body: body );
  final dio = Dio( BaseOptions( baseUrl: "http://test" ) )..interceptors.add( rec );
  return ( dio, rec );
}

HoldingAreaRepository _repo( Dio dio ) =>
    HoldingAreaRepository( dio, () => "rachel a81c72c4" );

void main() {
  group( "the STATUS door", () {
    test( "approve goes to /transition, NOT to PATCH", () async {
      // A builder implementing approve as PATCH {status:"queued"} gets a field door
      // silently ignoring an unknown key — a pane that looks wired and changes
      // nothing.
      final ( dio, rec ) = _dio();
      await _repo( dio ).transition( id: "abc", verb: verbById( "approve" ) );

      expect( rec.last.method, "POST" );
      expect( rec.last.path, endsWith( "/transition" ) );
      expect( ( rec.last.data as Map )[ "to_status" ], "queued" );
    } );

    test( "the id is URL-ENCODED — drive it with a/b?c#d", () async {
      // A raw and an encoded id are byte-identical until the id carries / ? or #,
      // at which point the request silently lands on a DIFFERENT ROUTE.
      final ( dio, rec ) = _dio();
      await _repo( dio ).transition( id: "a/b?c#d", verb: verbById( "approve" ) );

      expect( rec.last.path, contains( "a%2Fb%3Fc%23d" ) );
      expect( rec.last.path, isNot( contains( "a/b?c#d" ) ) );
    } );

    test( "every write carries actor and authority user_direct", () async {
      // The audit trail keys provenance off authority; anything weaker makes an
      // operator's decision read as automation.
      final ( dio, rec ) = _dio();
      await _repo( dio ).transition( id: "abc", verb: verbById( "approve" ) );

      final body = rec.last.data as Map;
      expect( body[ "actor" ], "rachel a81c72c4" );
      expect( body[ "authority" ], "user_direct" );
    } );
  } );

  group( "the seven verbs send what the server demands", () {
    test( "park sends park_reason, NOT reason", () async {
      // One verb out of five uses a different key for the same box. Sending
      // `reason` here is accepted-and-ignored.
      final ( dio, rec ) = _dio();
      await _repo( dio ).transition(
        id: "x", verb: verbById( "park" ), input: "waiting on Rick",
      );
      final body = rec.last.data as Map;
      expect( body[ "park_reason" ], "waiting on Rick" );
      expect( body.containsKey( "reason" ), isFalse );
    } );

    test( "unpark sends next_chase_ts as an EXPLICIT null, not an omission", () async {
      // "Send nothing" and "send null" are different requests and only one of them
      // clears. A surviving chase date re-chases Rick about a row already back on
      // his board (his ruling, row 03d3bf78).
      final ( dio, rec ) = _dio();
      await _repo( dio ).transition( id: "x", verb: verbById( "unpark" ) );

      final body = rec.last.data as Map;
      expect( body.containsKey( "next_chase_ts" ), isTrue, reason: "the KEY must be present" );
      expect( body[ "next_chase_ts" ], isNull );
    } );

    test( "fixed sends receipt_refs.operator_attestation and NO reason", () async {
      // The multiplexer shipped this bug once — picked the verb up without the
      // receipt and every Fixed press was refused by the server.
      final ( dio, rec ) = _dio();
      await _repo( dio ).transition(
        id: "x", verb: verbById( "fixed" ), input: "I checked it myself",
      );
      final body = rec.last.data as Map;
      expect( ( body[ "receipt_refs" ] as Map )[ "operator_attestation" ], "I checked it myself" );
      expect( body.containsKey( "reason" ), isFalse );
    } );

    test( "wont_fix is terminal and carries a reason", () {
      final v = verbById( "wont_fix" );
      expect( v.terminal, isTrue );
      expect( v.toStatus, "wont_fix" );
      expect( buildTransitionBody( verb: v, input: "superseded" )[ "reason" ], "superseded" );
    } );

    test( "a blank required input is refused BEFORE the wire", () async {
      // Otherwise it comes back as a 422 the operator has to interpret.
      final ( dio, rec ) = _dio();
      await expectLater(
        _repo( dio ).transition( id: "x", verb: verbById( "drop" ), input: "   " ),
        throwsArgumentError,
      );
      expect( rec.calls, isEmpty, reason: "nothing should have been sent" );
    } );

    test( "each verb's complaint names ITS OWN verb", () {
      // Five verbs share one reason box: "A reason is required" is true of four of
      // them and teaches none of them which.
      final messages = kTaskVerbs
          .where( ( v ) => v.input != VerbInput.none )
          .map( ( v ) => v.missingInputMessage )
          .toList();
      expect( messages.toSet().length, messages.length, reason: "two verbs share a complaint" );
      for ( final v in kTaskVerbs.where( ( v ) => v.input != VerbInput.none ) ) {
        expect( v.missingInputMessage.toLowerCase(), contains( v.label.split( " " ).first.toLowerCase() ) );
      }
    } );
  } );

  group( "the FIELD door", () {
    test( "PATCHes priority and owner, and refuses to be given a status", () async {
      final ( dio, rec ) = _dio();
      await _repo( dio ).patchFields( id: "abc", priority: "P1", ownerPersona: "rachel" );

      expect( rec.last.method, "PATCH" );
      expect( rec.last.path, isNot( contains( "transition" ) ) );
      final body = rec.last.data as Map;
      expect( body[ "priority" ], "P1" );
      expect( body[ "owner_persona" ], "rachel" );
      expect( body.containsKey( "status" ), isFalse );
    } );

    test( "its id is encoded too", () async {
      final ( dio, rec ) = _dio();
      await _repo( dio ).patchFields( id: "a/b", priority: "P2" );
      expect( rec.last.path, contains( "a%2Fb" ) );
    } );

    test( "a patch with nothing to change is refused", () async {
      final ( dio, _ ) = _dio();
      expect(
        () => _repo( dio ).patchFields( id: "x" ),
        throwsArgumentError,
      );
    } );
  } );

  group( "🔴 the 202 trap", () {
    test( "a 202 awaiting_human_approval is PENDING, never success", () async {
      // A 2xx that Dio does not throw on. Without this branch the pane paints the
      // row approved — a false FACT, not a false red.
      final ( dio, _ ) = _dio( status: 202, body: {
        "status"    : "awaiting_human_approval",
        "ticket_id" : "tkt-99",
      } );
      final out = await _repo( dio ).transition( id: "x", verb: verbById( "approve" ) );

      expect( out.ok, isFalse );
      expect( out.pending, isTrue );
      expect( out.ticketId, "tkt-99" );
    } );

    test( "the marker is matched on the STATUS FIELD, never as a substring", () async {
      // A row whose own reason text mentions the marker is an ordinary success.
      final ( dio, _ ) = _dio( status: 200, body: {
        "status" : "ok",
        "reason" : "not awaiting_human_approval any more",
      } );
      final out = await _repo( dio ).transition( id: "x", verb: verbById( "approve" ) );

      expect( out.ok, isTrue );
      expect( out.pending, isFalse );
    } );

    test( "an ordinary 200 is success", () async {
      final ( dio, _ ) = _dio( status: 200, body: { "status": "ok" } );
      final out = await _repo( dio ).transition( id: "x", verb: verbById( "approve" ) );
      expect( out.ok, isTrue );
    } );
  } );

  group( "the read", () {
    test( "status=not_approved is in the query — it IS the pane", () async {
      // The store excludes those rows by default. Dropping the parameter gives a
      // pane that renders an empty list and looks like it works.
      final ( dio, rec ) = _dio( body: { "tasks": [], "total": 0 } );
      await _repo( dio ).fetchHeld();

      expect( rec.last.queryParameters[ "status" ], "not_approved" );
      expect( rec.last.queryParameters[ "unscoped_audit" ], true );
    } );

    test( "terse=true, and NOT char_budget=0", () async {
      // terse shortens ROWS; the pre-cascade char_budget=0 recommendation returned
      // ~24 of 500 silently, contradicting the pane's own lazy list.
      final ( dio, rec ) = _dio( body: { "tasks": [] } );
      await _repo( dio ).fetchHeld();

      expect( rec.last.queryParameters[ "terse" ], true );
      expect( rec.last.queryParameters.containsKey( "char_budget" ), isFalse );
    } );

    test( "truncation signals are surfaced, not swallowed", () async {
      final ( dio, _ ) = _dio( body: {
        "tasks": [ { "id": "1" } ], "total": 900, "truncated": true, "has_more": true,
      } );
      final page = await _repo( dio ).fetchHeld();

      expect( page.total, 900 );
      expect( page.truncated, isTrue );
      expect( page.hasMore, isTrue );
    } );
  } );
}
