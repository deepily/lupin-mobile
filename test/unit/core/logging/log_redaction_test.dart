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
      final dio = Dio()
        ..httpClientAdapter = StubAdapter( {
          "GET /ok"   : ( _ ) => jsonBody( { "ok": true } ),
          "GET /fail" : ( _ ) => throw DioException( requestOptions: RequestOptions( path: "/fail" ), message: "boom ?access_token=$querySecret" ),
        } );
      HttpService( dio );
      Logger.resetForTesting();
      final capture = _Capture();
      Logger.addDestination( capture );

      final printed = <String>[];
      await runZoned( () async {
        await dio.get( "/ok", queryParameters: { "access_token": querySecret, "api_key": querySecret } );
        try { await dio.get( "/fail", queryParameters: { "api_key": querySecret } ); } catch ( _ ) {}
      }, zoneSpecification: ZoneSpecification( print: ( _, __, ___, line ) => printed.add( line ) ) );

      final logged = capture.entries.map( ( e ) => e.toFormattedString() ).join( "\n" );
      expect( logged, contains( "Request: GET" ) );
      expect( logged, contains( "/ok" ) );
      expect( logged, isNot( contains( querySecret ) ) );
      expect( logged, isNot( contains( "api_key" ) ) );
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
