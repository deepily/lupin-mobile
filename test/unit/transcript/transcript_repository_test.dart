import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/features/transcript/data/transcript_repository.dart';

import '../_helpers/stub_dio.dart';

/// `TranscriptRepository` — the four REST reads AS THE WIRE SEES THEM, and the three answers
/// that are not a body.
///
/// 🔴 THIS FILE EXISTS BECAUSE EVERY OTHER TRANSCRIPT TEST TALKS TO A FAKE THAT OVERRIDES
/// THESE METHODS, so nothing was checking the one thing they do. `FakeTranscriptRepository`
/// records what the BLOC asked for — "a tail read, not a since read" — and that is the right
/// seam for the bloc's rows. But it subclasses this class and replaces the bodies, so the
/// query string this class actually builds, and the status mapping it applies, were covered
/// at 45% with the parts below untouched. C5.16 is stated as "the fake REST layer records a
/// `tail_bytes` request, **not** `since_offset=0`"; this file is the half of that claim the
/// fake cannot make — whether `tail_bytes` reaches the server as a parameter by that name.
///
/// ⚠️ A STUB ADAPTER, NOT A STUB REPOSITORY. The Dio instance is real, so the query
/// serialisation, the `validateStatus` override and the `DioException` types are the real
/// ones; only the socket is replaced.
void main() {
  const id   = "stable-session-id-1234";
  const path = "${ TranscriptRepository.pathPrefix }/$id";

  late StubAdapter          adapter;
  late TranscriptRepository repo;

  setUp( () {
    adapter = StubAdapter();
    repo    = TranscriptRepository( makeDio( adapter ) );
  } );

  /// The one read the stub answered, as Dio built it.
  RequestOptions onlyCall() {
    expect( adapter.captured, hasLength( 1 ),
        reason: "exactly one HTTP call is expected here" );
    return adapter.captured.single;
  }

  Map<String, dynamic> query() => onlyCall().queryParameters;

  void serve( Object body, { int status = 200 } ) {
    adapter.handlers[ "GET $path" ] = ( _ ) => jsonBody( body, status: status );
  }

  const bodyOk = {
    "file_epoch"  : "epoch-7",
    "offset"      : 4096,
    "next_offset" : 8192,
    "blocks"      : [ { "kind": "text", "text": "hello" } ],
  };

  group( "the query each read builds", () {
    test( "fetchTail asks for tail_bytes and NEVER since_offset (C5.16, at the wire)",
        () async {
      serve( bodyOk );
      await repo.fetchTail( ccSessionId: id, cancelToken: CancelToken() );

      expect( query()[ "tail_bytes" ], TranscriptRepository.openTailBytes );
      // 🔴 THE NAMED FAILURE OF C5.16 IS A READ THAT LOOKS RIGHT AND OPENS AT THE TOP.
      // `since_offset=0` returns the FIRST 64 KB; ruling Q6 wants the LAST. Both are
      // "a 64 KB read" in a log, which is why the absence is asserted rather than assumed.
      expect( query().containsKey( "since_offset" ), isFalse );
      expect( onlyCall().path, path );
      expect( onlyCall().method, "GET" );
    } );

    test( "fetchTail honours a caller's tailBytes", () async {
      serve( bodyOk );
      await repo.fetchTail( ccSessionId: id, cancelToken: CancelToken(), tailBytes: 1024 );

      expect( query()[ "tail_bytes" ], 1024 );
    } );

    test( "fetchSince asks for since_offset, and omits max_bytes unless given", () async {
      serve( bodyOk );
      await repo.fetchSince( ccSessionId: id, sinceOffset: 8192, cancelToken: CancelToken() );

      expect( query()[ "since_offset" ], 8192 );
      expect( query().containsKey( "max_bytes" ), isFalse,
          reason: "an absent max_bytes lets the server pick; sending null would be a "
                  "different request" );
      expect( query().containsKey( "tail_bytes" ), isFalse );
    } );

    test( "fetchSince passes max_bytes when the caller sets it", () async {
      serve( bodyOk );
      await repo.fetchSince(
        ccSessionId : id,
        sinceOffset : 8192,
        cancelToken : CancelToken(),
        maxBytes    : 4096,
      );

      expect( query()[ "max_bytes" ], 4096 );
    } );

    test( "fetchBefore asks BACKWARDS, with a page size", () async {
      serve( bodyOk );
      await repo.fetchBefore( ccSessionId: id, beforeOffset: 4096, cancelToken: CancelToken() );

      expect( query()[ "before_offset" ], 4096 );
      expect( query()[ "max_bytes" ], TranscriptRepository.pageBytes );
      expect( query().containsKey( "since_offset" ), isFalse,
          reason: "§3 added a backward read precisely because a forward-only contract "
                  "cannot express 'load earlier'" );
    } );

    test( "fetchFullBlock asks for one block UNBOUNDED, via max_bytes 0", () async {
      serve( bodyOk );
      await repo.fetchFullBlock(
        ccSessionId : id,
        blockOffset : 4096,
        cancelToken : CancelToken(),
      );

      expect( query()[ "since_offset" ], 4096 );
      // §2 item 7's sentinel, adopted from `tasks.py`: 0 means UNBOUNDED, not "no bytes".
      // A repository that read it the other way would answer C5.19's expansion with nothing.
      expect( query()[ "max_bytes" ], 0 );
    } );
  } );

  group( "what a body becomes", () {
    test( "a 2xx body is parsed into a backlog", () async {
      serve( bodyOk );
      final out = await repo.fetchTail( ccSessionId: id, cancelToken: CancelToken() );

      expect( out.fileEpoch, "epoch-7" );
      expect( out.offset, 4096 );
      expect( out.nextOffset, 8192 );
      expect( out.blocks, hasLength( 1 ) );
      expect( out.blocks.single.text, "hello" );
    } );

    test( "a 403 is a REFUSAL carrying the server's detail, not a retryable failure",
        () async {
      serve( { "detail": "admin only" }, status: 403 );

      // 🔴 THE TYPE IS THE POINT, NOT THE MESSAGE. The screen treats `TranscriptRefused` as
      // FINAL — no retry, no further watch (C5.21). A generic exception here would be
      // retried by a caller that cannot tell a refusal from a flaky network, which is the
      // build C5.21's negative control fails.
      await expectLater(
        repo.fetchTail( ccSessionId: id, cancelToken: CancelToken() ),
        throwsA( isA<TranscriptRefused>()
            .having( ( e ) => e.reason, "reason", "admin only" ) ),
      );
    } );

    test( "a 403 with no detail still refuses, with a null reason", () async {
      serve( { "error": "nope" }, status: 403 );

      await expectLater(
        repo.fetchTail( ccSessionId: id, cancelToken: CancelToken() ),
        throwsA( isA<TranscriptRefused>()
            .having( ( e ) => e.reason, "reason", isNull ) ),
      );
    } );

    test( "any other non-2xx is a RETRYABLE api exception carrying the status", () async {
      serve( { "detail": "boom" }, status: 500 );

      await expectLater(
        repo.fetchTail( ccSessionId: id, cancelToken: CancelToken() ),
        throwsA( isA<TranscriptApiException>()
            .having( ( e ) => e.message, "message", "boom" )
            .having( ( e ) => e.statusCode, "statusCode", 500 ) ),
      );
    } );

    test( "a non-2xx with no detail falls back to the status line", () async {
      serve( "not json at all", status: 503 );

      await expectLater(
        repo.fetchTail( ccSessionId: id, cancelToken: CancelToken() ),
        throwsA( isA<TranscriptApiException>()
            .having( ( e ) => e.message, "message", "HTTP 503" ) ),
      );
    } );
  } );

  group( "a cancelled read", () {
    test( "rethrows the DioException UNFLATTENED, so the bloc can tell why", () async {
      final token = CancelToken();
      adapter.handlers[ "GET $path" ] = ( _ ) {
        token.cancel( "the route went away" );
        throw DioException.requestCancelled(
          requestOptions : RequestOptions( path: path ),
          reason         : token.cancelError,
        );
      };

      // 🔴 CANCEL IS NOT A FAILURE AND MUST NOT ARRIVE AS ONE. `_catchUpThenWatch` swallows
      // `DioExceptionType.cancel` and rethrows everything else; if this class flattened a
      // cancel into `TranscriptApiException`, a popped route would surface as an error banner
      // on a screen that no longer exists — and, worse, as a retry.
      await expectLater(
        repo.fetchTail( ccSessionId: id, cancelToken: token ),
        throwsA( isA<DioException>()
            .having( ( e ) => e.type, "type", DioExceptionType.cancel ) ),
      );
    } );

    test( "a transport failure that is NOT a cancel becomes an api exception", () async {
      adapter.handlers[ "GET $path" ] = ( _ ) => throw DioException.connectionError(
        requestOptions  : RequestOptions( path: path ),
        reason          : "no route to host",
      );

      await expectLater(
        repo.fetchTail( ccSessionId: id, cancelToken: CancelToken() ),
        throwsA( isA<TranscriptApiException>() ),
      );
    } );
  } );

  group( "the two exceptions say which they are, in a log", () {
    // These `toString()`s are what a crash report and a `debugPrint` carry, and the whole
    // distinction this feature rests on — refusal vs failure — is invisible in a log that
    // prints `Instance of 'TranscriptRefused'`. One line each, and they were the last
    // uncovered lines in the file.
    test( "a refusal names its reason, or says it had none", () {
      expect( const TranscriptRefused( "admin only" ).toString(),
          "TranscriptRefused: admin only" );
      expect( const TranscriptRefused().toString(), "TranscriptRefused" );
    } );

    test( "a failure names its status when it has one", () {
      expect( const TranscriptApiException( "boom", statusCode: 500 ).toString(),
          "TranscriptApiException(500): boom" );
      expect( const TranscriptApiException( "no status" ).toString(),
          "TranscriptApiException: no status" );
    } );
  } );

  test( "the path is one constant, and OSQ-6 moves it in one edit", () {
    expect( TranscriptRepository.pathPrefix, "/api/cc-transcript",
        reason: "§3 proposes this path and OSQ-6 is open on it. The row is here so that when "
                "María's question is answered, the failing test names the constant to edit "
                "rather than leaving a grep across four call sites" );
  } );
}
