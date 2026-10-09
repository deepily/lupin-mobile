// Row a7de7d69: the HTTP logger printed live bearer tokens and both auth tokens
// to logcat, in release builds too. These tests pin the scrubber AND the real
// interceptor wiring — the pure function passing proves nothing on its own if
// HttpService stops calling it.
//
// Every token below is SYNTHETIC. Rick's real leaked token is deliberately not
// in this file: committing it would turn a fixed leak into a permanent one.

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/logging/log_redaction.dart';
import 'package:lupin_mobile/core/logging/logger.dart';
import 'package:lupin_mobile/services/network/http_service.dart';

import '../../_helpers/stub_dio.dart';

/// Structurally a real JWT — `eyJ` header, three base64url segments — and
/// entirely made up.
const String _jwt =
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
    ".eyJzdWIiOiJ0ZXN0LXVzZXItaWQiLCJlbWFpbCI6InRlc3RAZXhhbXBsZS5jb20ifQ"
    ".ZmFrZXNpZ25hdHVyZUZPUlRFU1RTT05MWQ";

class _Capture implements LogDestination {
  final List<LogEntry> entries = [];

  @override
  void write( LogEntry entry ) => entries.add( entry );

  @override
  Future<void> flush() async {}
}

void main() {
  group( "redactSecrets masks credentials", () {
    test( "an Authorization header keeps its name and loses its value", () {
      final out = redactSecrets( " Authorization: Bearer $_jwt" );
      expect( out, contains( "Authorization" ) );
      expect( out, isNot( contains( _jwt ) ) );
      expect( out, isNot( contains( "eyJ" ) ) );
    } );

    test( "an opaque (non-JWT) Authorization value is masked too", () {
      // The JWT pattern cannot see this one, so only the header rule catches it.
      final out = redactSecrets( "Authorization: Token abc123-not-a-jwt" );
      expect( out, isNot( contains( "abc123-not-a-jwt" ) ) );
    } );

    test( "access_token and refresh_token are masked in a JSON body", () {
      final body = jsonEncode( {
        "access_token"  : _jwt,
        "refresh_token" : "opaque-refresh-value",
        "token_type"    : "bearer",
      } );
      final out = redactSecrets( body );
      expect( out, isNot( contains( _jwt ) ) );
      expect( out, isNot( contains( "opaque-refresh-value" ) ) );
      // The field NAMES survive — a reader must still see the shape of the body.
      expect( out, contains( "access_token" ) );
      expect( out, contains( "refresh_token" ) );
      // A non-secret field is untouched.
      expect( out, contains( "bearer" ) );
    } );

    test( "a token in a Dart map's toString is masked (Dio's request-body shape)", () {
      // Dio prints request bodies as a map toString, not as JSON, so the JSON
      // rule alone would miss this — the defect this case exists for.
      final out = redactSecrets( "{refresh_token: opaque-refresh-value}" );
      expect( out, isNot( contains( "opaque-refresh-value" ) ) );
      expect( out, contains( "refresh_token" ) );
    } );

    test( "a form-encoded token field name=value is masked and its neighbours are kept", () {
      final out = redactSecrets( "refresh_token=opaque-RT&x=1" );
      expect( out, isNot( contains( "opaque-RT" ) ) );
      expect( out, contains( "refresh_token=" ) );
      expect( out, contains( "&x=1" ) );
    } );

    test( "name = value with spaces and each token name is masked", () {
      for ( final name in [ "access_token", "refresh_token", "id_token" ] ) {
        final out = redactSecrets( "$name = secret-value-1, next" );
        expect( out, isNot( contains( "secret-value-1" ) ), reason: name );
        expect( out, contains( ", next" ), reason: name );
      }
    } );

    test( "an error code that merely ends in id_token keeps its reason", () {
      const line = "invalid_token: the token expired";
      expect( redactSecrets( line ), line );
      expect( redactSecrets( "error=invalid_token&x=1" ), "error=invalid_token&x=1" );
    } );

    test( "bare password and token fields are masked, neighbours kept", () {
      expect( redactSecrets( "password=hunter2&x=1" ), "password=<redacted>&x=1" );
      expect( redactSecrets( "{token: abc123, a: 1}" ), "{token: <redacted>, a: 1}" );
      expect( redactSecrets( "login token=abc123" ), "login token=<redacted>" );
      expect( redactSecrets( "{\"password\":\"hunter2\"}" ), "{\"password\":\"<redacted>\"}" );
    } );

    test( "prefixed names ending in _token or _password are masked", () {
      for ( final name in [ "api_token", "auth_token", "user_password", "db_password", "x-access_token", "access-token", "accessToken" ] ) {
        expect( redactSecrets( "$name=SECRET&x=1" ), "$name=<redacted>&x=1", reason: name );
        expect( redactSecrets( "{$name: SECRET, a: 1}" ), "{$name: <redacted>, a: 1}", reason: name );
        expect( redactSecrets( "{\"$name\":\"SECRET\"}" ), "{\"$name\":\"<redacted>\"}", reason: name );
      }
    } );

    test( "an invalid_token error code is still left alone beside its neighbours", () {
      expect( redactSecrets( "error=invalid_token&access_token=SECRET" ), "error=invalid_token&access_token=<redacted>" );
      expect( redactSecrets( "invalid_token: the token expired" ), "invalid_token: the token expired" );
      expect( redactSecrets( "tokenizer=x passwordless: true" ), "tokenizer=x passwordless: true" );
    } );

    test( "JSON values that are not strings, or hold escaped quotes, are masked whole", () {
      expect( redactSecrets( "{\"password\":12345,\"a\":1}" ), "{\"password\":\"<redacted>\",\"a\":1}" );
      expect( redactSecrets( "{\"password\": \"a\\\"b\", \"a\": 1}" ), "{\"password\":\"<redacted>\", \"a\": 1}" );
      expect( redactSecrets( "{\"api_token\":null}" ), "{\"api_token\":\"<redacted>\"}" );
    } );

    test( "the name: value form keeps its separator after the change", () {
      expect( redactSecrets( "{refresh_token: opaque}" ), "{refresh_token: <redacted>}" );
    } );

    // Row 8398bfe8: three gaps found by John's review of 63996b9, each pinned here.
    test( "quoted key names are masked: a Python repr, a single-quoted key, a quoted key with =", () {
      expect( redactSecrets( "{'api_token': SECRET}" ), "{'api_token': <redacted>}" );
      expect( redactSecrets( "{'password': SECRET}" ), "{'password': <redacted>}" );
      expect( redactSecrets( "{'password': 'hunter2', 'a': 1}" ), "{'password': <redacted>, 'a': 1}" );
      expect( redactSecrets( "'token'=SECRET" ), "'token'=<redacted>" );
      expect( redactSecrets( "\"token\"=SECRET&x=1" ), "\"token\"=<redacted>&x=1" );
      expect( redactSecrets( "{'Authorization': 'Bearer opaque-abc'}" ), isNot( contains( "opaque-abc" ) ) );
    } );

    test( "an array value is masked whole, not up to its first comma", () {
      expect( redactSecrets( "{\"token\": [\"SECRET\",\"S2\"]}" ), "{\"token\":\"<redacted>\"}" );
      expect( redactSecrets( "{\"token\": [\"SECRET\", \"S2\"], \"a\": 1}" ), "{\"token\":\"<redacted>\", \"a\": 1}" );
      expect( redactSecrets( "{token: [SECRET, S2], a: 1}" ), "{token: <redacted>, a: 1}" );
      expect( redactSecrets( "{'token': ['SECRET', 'S2'], 'a': 1}" ), "{'token': <redacted>, 'a': 1}" );
    } );

    test( "a nested-object value is masked whole, brackets inside strings do not end it early", () {
      expect( redactSecrets( "{\"token\": {\"a\":\"SECRET\",\"b\":\"S2\"}}" ), "{\"token\":\"<redacted>\"}" );
      expect( redactSecrets( "{\"token\": {\"a\":\"SE}CRET\",\"b\":[\"S2\"]}, \"z\": 1}" ), "{\"token\":\"<redacted>\", \"z\": 1}" );
      expect( redactSecrets( "{\"password\": {\"a\":\"SE\\\"}CRET\"}, \"z\": 1}" ), "{\"password\":\"<redacted>\", \"z\": 1}" );
    } );

    test( "an unterminated array or object is masked to the end of the text, an unterminated string to the end of its line", () {
      expect( redactSecrets( "{\"token\": [\"SECRET\",\"S2\"\nnext line" ), "{\"token\":\"<redacted>\"" );
      expect( redactSecrets( "{token: {a: SECRET" ), "{token: <redacted>" );
      expect( redactSecrets( "token: \"SECRET\nnext line" ), "token: <redacted>\nnext line" );
    } );

    test( "a pretty-printed array or object spread over several lines is masked whole", () {
      expect( redactSecrets( "{\"token\": [\n  \"SECRET\",\n  \"S2\"\n], \"a\": 1}" ), "{\"token\":\"<redacted>\", \"a\": 1}" );
      expect( redactSecrets( "{\n  \"token\": {\n    \"a\": \"SECRET\",\n    \"b\": [\"S2\"]\n  },\n  \"ok\": 1\n}" ), "{\n  \"token\":\"<redacted>\",\n  \"ok\": 1\n}" );
      expect( redactSecrets( "{'password': {\n 'a': 'SECRET'\n}}" ), "{'password': <redacted>}" );
    } );

    test( "cost grows linearly with the number of credential fields on one line", () {
      // Counted by scaling, not by a wall-clock limit: 4x the fields must cost about 4x, not 16x.
      // A scanner that copies or searches the rest of the line per field is quadratic and fails this.
      Duration timeFor( int fields ) {
        final line = List.generate( fields, ( i ) => "token=abc$i," ).join();
        var best   = const Duration( days: 1 );
        for ( var run = 0; run < 3; run++ ) {
          final watch = Stopwatch()..start();
          final out   = redactSecrets( line );
          watch.stop();
          expect( out, isNot( contains( "abc" ) ) );
          if ( watch.elapsed < best ) best = watch.elapsed;
        }
        return best;
      }

      final small = timeFor( 5000 ).inMicroseconds + 1;
      final large = timeFor( 20000 ).inMicroseconds + 1;
      expect( large / small, lessThan( 9 ), reason: "5000 fields took ${small}us, 20000 took ${large}us" );
    } );

    test( "passwd, secret and api_key style names are masked in every spelling", () {
      for ( final name in [ "passwd", "secret", "client_secret", "api_key", "api-key", "apikey", "apiKey", "x-api-key", "db_passwd" ] ) {
        expect( redactSecrets( "$name=SECRET&x=1" ), "$name=<redacted>&x=1", reason: name );
        expect( redactSecrets( "{$name: SECRET, a: 1}" ), "{$name: <redacted>, a: 1}", reason: name );
        expect( redactSecrets( "{\"$name\":\"SECRET\"}" ), "{\"$name\":\"<redacted>\"}", reason: name );
        expect( redactSecrets( "{'$name': 'SECRET'}" ), "{'$name': <redacted>}", reason: name );
      }
    } );

    test( "secret_key, private_key, access_key and their camelCase and prefixed spellings are masked", () {
      for ( final name in [ "secret_key", "private_key", "access_key", "secret-key", "secretKey", "privateKey", "accessKey", "aws_secret_access_key", "SECRET_KEY" ] ) {
        expect( redactSecrets( "$name=SECRET&x=1" ), "$name=<redacted>&x=1", reason: name );
        expect( redactSecrets( "{$name: SECRET, a: 1}" ), "{$name: <redacted>, a: 1}", reason: name );
        expect( redactSecrets( "{\"$name\":\"SECRET\"}" ), "{\"$name\":\"<redacted>\"}", reason: name );
        expect( redactSecrets( "{'$name': 'SECRET'}" ), "{'$name': <redacted>}", reason: name );
      }
    } );

    test( "plural credential names are masked, arrays included", () {
      for ( final name in [ "tokens", "passwords", "secrets", "api_keys", "access_tokens", "refresh_tokens" ] ) {
        expect( redactSecrets( "$name=SECRET&x=1" ), "$name=<redacted>&x=1", reason: name );
        expect( redactSecrets( "{\"$name\":[\"SECRET\",\"S2\"]}" ), "{\"$name\":\"<redacted>\"}", reason: name );
        expect( redactSecrets( "{'$name': ['SECRET', 'S2'], 'a': 1}" ), "{'$name': <redacted>, 'a': 1}", reason: name );
      }
    } );

    test( "a plural name holding a bare number is a usage count and stays readable", () {
      expect( redactSecrets( "tokens: 123" ), "tokens: 123" );
      expect( redactSecrets( "{\"tokens\": 4096, \"a\": 1}" ), "{\"tokens\": 4096, \"a\": 1}" );
      expect( redactSecrets( "max_tokens=512&x=1" ), "max_tokens=512&x=1" );
      expect( redactSecrets( "{'tokens': 7.5}" ), "{'tokens': 7.5}" );
      // Controls: strings, arrays and objects under a plural name, and a singular name holding a number, are still masked.
      expect( redactSecrets( "{\"tokens\": [\"abc\"]}" ), "{\"tokens\":\"<redacted>\"}" );
      expect( redactSecrets( "{\"tokens\": \"abc\"}" ), "{\"tokens\":\"<redacted>\"}" );
      expect( redactSecrets( "tokens: {a: 1}" ), "tokens: <redacted>" );
      expect( redactSecrets( "max_tokens=abc123" ), "max_tokens=<redacted>" );
      expect( redactSecrets( "{\"password\":12345}" ), "{\"password\":\"<redacted>\"}" );
      expect( redactSecrets( "token=12345" ), "token=<redacted>" );
    } );

    test( "only the token-count names may hold a bare number; every other secret name is masked whatever the value", () {
      expect( redactSecrets( "passwords=12345678" ), "passwords=<redacted>" );
      expect( redactSecrets( "{\"passwords\": 12345678}" ), "{\"passwords\":\"<redacted>\"}" );
      expect( redactSecrets( "secrets: 424242" ), "secrets: <redacted>" );
      expect( redactSecrets( "api_keys=123456789012" ), "api_keys=<redacted>" );
      expect( redactSecrets( "access_tokens: 8675309" ), "access_tokens: <redacted>" );
      expect( redactSecrets( "{'private_keys': 99999}" ), "{'private_keys': <redacted>}" );
      expect( redactSecrets( "secret_keys=1" ), "secret_keys=<redacted>" );
      expect( redactSecrets( "refresh_tokens=123456" ), "refresh_tokens=<redacted>" );
      expect( redactSecrets( "x_max_tokens=512" ), "x_max_tokens=<redacted>" );
    } );

    test( "each count name keeps its number, in snake_case and camelCase", () {
      for ( final name in [
        "tokens", "max_tokens", "prompt_tokens", "completion_tokens", "total_tokens", "input_tokens", "output_tokens",
        "maxTokens", "promptTokens", "completionTokens", "totalTokens", "inputTokens", "outputTokens",
      ] ) {
        expect( redactSecrets( "$name=512&x=1" ), "$name=512&x=1", reason: name );
        expect( redactSecrets( "{$name: 512, a: 1}" ), "{$name: 512, a: 1}", reason: name );
        expect( redactSecrets( "{\"$name\":512}" ), "{\"$name\":512}", reason: name );
      }
    } );

    test( "a count number is bare when it ends at a space, ampersand, comma or bracket", () {
      expect( redactSecrets( "max_tokens=512 (limit)" ), "max_tokens=512 (limit)" );
      expect( redactSecrets( "GET /v1/chat?max_tokens=512 HTTP/1.1" ), "GET /v1/chat?max_tokens=512 HTTP/1.1" );
      expect( redactSecrets( "[tokens=512]" ), "[tokens=512]" );
      expect( redactSecrets( "max_tokens=512\nnext" ), "max_tokens=512\nnext" );
      expect( redactSecrets( "max_tokens=512" ), "max_tokens=512" );
      // Not bare: letters follow the digits, so it could be a credential.
      expect( redactSecrets( "max_tokens=512abc" ), "max_tokens=<redacted>" );
      expect( redactSecrets( "tokens: 1e5" ), "tokens: <redacted>" );
    } );

    test( "names that look close to the new ones are left alone", () {
      const line = "hockey=1 monkey: 2 keyboard=3 publickey=4 secretary=5 passworded=6 tokenizers=7 accesskeyboard=8";
      expect( redactSecrets( line ), line );
    } );

    test( "names that merely contain secret, key or passwd are left alone", () {
      const line = "secretary=Jo keyboard: us monkey=1 passwdless: true api_keyring=x";
      expect( redactSecrets( line ), line );
    } );

    test( "the new rules keep redaction stable under repeated application", () {
      for ( final line in [ "{'password': 'hunter2'}", "{\"token\": [\"A\",\"B\"]}", "api_key=ABC&x=1", "{secret: {a: 1}}" ] ) {
        final once = redactSecrets( line );
        expect( redactSecrets( once ), once, reason: line );
      }
    } );

    test( "a bare JWT under an unanticipated field name is still masked", () {
      final out = redactSecrets( "{some_future_field: $_jwt}" );
      expect( out, isNot( contains( "eyJ" ) ) );
    } );

    test( "a line with no credential is returned character for character", () {
      // This runs on EVERY logged line, so it must not reformat innocent text.
      const clean = "Response: 200 http://10.0.2.2:7999/api/v2/transcribe"
          " {\"transcription\":\"What's the sum of 2 plus 2?\"}";
      expect( redactSecrets( clean ), clean );
    } );

    test( "redaction is stable under repeated application", () {
      final once  = redactSecrets( "Authorization: Bearer $_jwt" );
      final twice = redactSecrets( once );
      expect( twice, once );
    } );

    test( "the exact logcat shape from 2026-09-19 is scrubbed", () {
      // The real leak, reproduced with a synthetic token.
      const line = "[HTTP]  Authorization: Bearer $_jwt";
      final out  = redactSecrets( line );
      expect( out, isNot( contains( "eyJ" ) ) );
      expect( out, contains( "<redacted>" ) );
    } );
  } );

  group( "HttpService's logger cannot leak a bearer token", () {
    // ⚠️ WHAT EACH TEST HERE ACTUALLY PROVES, measured by mutation on 2026-09-19
    // rather than assumed. Removing `redactSecrets` from HttpService's logPrint
    // kills EXACTLY ONE test in this file: "a sign-in response body logs neither
    // token". So:
    //   - control 3 (redaction is wired into HttpService) — pinned by that test.
    //   - control 2 (`requestHeader: false`) — pinned by "no request header block
    //     reaches the sink" below, which fails if anyone flips it back on.
    //   - control 1 (`kDebugMode`) — NOT pinned, and cannot be from inside a debug
    //     test run, since the constant is baked at compile time. Stated plainly
    //     rather than papered over with a test that would pass either way.
    // The test immediately below passes under the redaction mutant, because
    // control 2 alone is enough to keep the token out. That is the layers working,
    // but it is not evidence about the scrubber.
    test( "a request carrying an Authorization header logs no token", () async {
      // Tests run in debug, so the interceptor IS registered here — which is
      // what makes this assertion meaningful rather than vacuous.
      expect( kDebugMode, isTrue,
          reason: "this test only proves something while the logger is installed" );

      final dio = Dio()
        ..httpClientAdapter = StubAdapter( {
          "GET /api/thing": ( _ ) => jsonBody( { "ok": true } ),
        } );
      HttpService( dio );

      final printed = <String>[];
      await runZoned(
        () => dio.get(
          "/api/thing",
          options: Options( headers: { "Authorization": "Bearer $_jwt" } ),
        ),
        zoneSpecification: ZoneSpecification(
          print: ( _, __, ___, line ) => printed.add( line ),
        ),
      );

      expect( printed, isNotEmpty,
          reason: "the debug logger should have printed something to scrub" );
      final all = printed.join( "\n" );
      expect( all, isNot( contains( _jwt ) ) );
      expect( all, isNot( contains( "eyJ" ) ) );
    } );

    test( "a sign-in response body logs neither token", () async {
      final dio = Dio()
        ..httpClientAdapter = StubAdapter( {
          "POST /auth/login": ( _ ) => jsonBody( {
                "access_token"  : _jwt,
                "refresh_token" : "opaque-refresh-value",
              } ),
        } );
      HttpService( dio );

      final printed = <String>[];
      await runZoned(
        () => dio.post( "/auth/login", data: { "email": "u@x.y", "password": "pw" } ),
        zoneSpecification: ZoneSpecification(
          print: ( _, __, ___, line ) => printed.add( line ),
        ),
      );

      final all = printed.join( "\n" );
      expect( all, isNot( contains( _jwt ) ) );
      expect( all, isNot( contains( "opaque-refresh-value" ) ) );
    } );

    test( "no request header block reaches the sink at all", () async {
      // Control 2's own dying test. Under `requestHeader: false` the header
      // section is never offered to the logger, so the WORD "Authorization"
      // does not appear — not even masked. Flip requestHeader back to true and
      // this fails, because redaction keeps the field NAME and masks only the
      // value. That is what makes it a test of the second layer and not the third.
      final dio = Dio()
        ..httpClientAdapter = StubAdapter( {
          "GET /api/thing": ( _ ) => jsonBody( { "ok": true } ),
        } );
      HttpService( dio );

      final printed = <String>[];
      await runZoned(
        () => dio.get(
          "/api/thing",
          options: Options( headers: { "Authorization": "Bearer $_jwt" } ),
        ),
        zoneSpecification: ZoneSpecification(
          print: ( _, __, ___, line ) => printed.add( line ),
        ),
      );

      expect( printed, isNotEmpty, reason: "the logger must have run for this to mean anything" );
      expect( printed.join( "\n" ), isNot( contains( "Authorization" ) ) );
    } );

    test( "redaction covers headers on its own, with requestHeader left ON", () async {
      // The independent proof of control 3. If someone ever re-enables
      // requestHeader on the real interceptor, this is the test that says the
      // scrubber is still holding the line. It fails the moment redaction goes.
      final dio = Dio()
        ..httpClientAdapter = StubAdapter( {
          "GET /api/thing": ( _ ) => jsonBody( { "ok": true } ),
        } )
        ..interceptors.add( LogInterceptor(
          requestHeader : true,
          logPrint      : ( obj ) => print( "[HTTP] ${redactSecrets( obj.toString() )}" ),
        ) );

      final printed = <String>[];
      await runZoned(
        () => dio.get(
          "/api/thing",
          options: Options( headers: { "Authorization": "Bearer $_jwt" } ),
        ),
        zoneSpecification: ZoneSpecification(
          print: ( _, __, ___, line ) => printed.add( line ),
        ),
      );

      final all = printed.join( "\n" );
      expect( all, contains( "Authorization" ),
          reason: "the header line must actually have been logged, or this proves nothing" );
      expect( all, isNot( contains( _jwt ) ) );
      expect( all, isNot( contains( "eyJ" ) ) );
    } );

    test( "the interceptor's method and path reach the Logger and no query string reaches any sink", () async {
      const querySecret = "QSECRET-9f3a";
      // The URLs carry userinfo, and the failing stub throws with the request's own options, so the query is on the error line's URI.
      const base = "http://alice:PWSECRET@host.example:7999";
      final dio = Dio()
        ..httpClientAdapter = StubAdapter( {
          "GET $base/ok"   : ( _ ) => jsonBody( { "ok": true } ),
          "GET $base/fail" : ( o ) => throw DioException( requestOptions: o, message: "boom" ),
        } );
      HttpService( dio );
      Logger.resetForTesting();
      final capture = _Capture();
      Logger.addDestination( capture );

      final printed = <String>[];
      await runZoned( () async {
        await dio.get( "$base/ok", queryParameters: { "access_token": querySecret, "api_key": querySecret } );
        try { await dio.get( "$base/fail", queryParameters: { "api_key": querySecret } ); } catch ( _ ) {}
      }, zoneSpecification: ZoneSpecification( print: ( _, __, ___, line ) => printed.add( line ) ) );

      final logged = capture.entries.map( ( e ) => e.toFormattedString() ).join( "\n" );
      expect( logged, contains( "Request: GET" ) );
      expect( logged, contains( "/ok" ) );
      expect( logged, isNot( contains( querySecret ) ) );
      expect( logged, isNot( contains( "api_key" ) ) );
      expect( logged, isNot( contains( "PWSECRET" ) ) );
      expect( logged, isNot( contains( "alice" ) ) );
      expect( logged, contains( "Response: 200 http://host.example:7999/ok" ) );
      expect( logged, contains( "Error: unknown http://host.example:7999/fail" ) );
      // The debug-only LogInterceptor also prints in tests; the always-on wrapper must not use plain print at all.
      expect( printed.where( ( l ) => l.startsWith( "[HTTP] Request:" ) || l.startsWith( "[HTTP] Response:" ) || l.startsWith( "[HTTP] Error:" ) ), isEmpty );
      Logger.resetForTesting();
    } );

    test( "the narrow method/URI diagnostic still prints — device checks depend on it", () async {
      // c3fc62bf was closed on a `[HTTP] Request: POST …/api/v2/transcribe` line
      // from the SECOND interceptor. Scrubbing must not have silenced it.
      final dio = Dio()
        ..httpClientAdapter = StubAdapter( {
          "POST /api/v2/transcribe": ( _ ) => jsonBody( { "transcription": "hi" } ),
        } );
      HttpService( dio );

      Logger.resetForTesting();
      final capture = _Capture();
      Logger.addDestination( capture );

      await dio.post( "/api/v2/transcribe" );

      final logged = capture.entries.map( ( e ) => e.toFormattedString() ).join( "\n" );
      expect( logged, contains( "Request: POST" ) );
      expect( logged, contains( "/api/v2/transcribe" ) );
      Logger.resetForTesting();
    } );
  } );
}
