// HttpService failure paths log through the app Logger at error level with the
// HTTP tag, and no credential reaches the entry.

import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/logging/logger.dart';
import 'package:lupin_mobile/services/network/http_service.dart';

import '../../_helpers/stub_dio.dart';

// Synthetic JWT, structurally valid and made up.
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
  late _Capture capture;
  late HttpService service;

  setUp( () {
    Logger.resetForTesting();
    capture = _Capture();
    Logger.addDestination( capture );

    final adapter = StubAdapter( {
      for ( final key in [
        "GET /api/get-session-id", "POST /api/get-speech", "POST /api/upload-and-transcribe-mp3",
        "GET /health", "GET /x", "POST /x", "PUT /x", "DELETE /x",
      ] )
        key: ( _ ) => throw Exception( "backend said Authorization: Bearer $_jwt" ),
    } );
    service = HttpService( makeDio( adapter ) );
  } );

  tearDown( Logger.resetForTesting );

  // The HTTP interceptors print to the zone; keep that out of the test output.
  Future<T> quiet<T>( Future<T> Function() body ) =>
      runZoned( body, zoneSpecification: ZoneSpecification( print: ( _, __, ___, ____ ) {} ) );

  final failures = <String, Future<Object?> Function( HttpService )>{
    "Session ID request failed"      : ( s ) => s.getSessionId(),
    "ElevenLabs TTS request failed"  : ( s ) => s.requestElevenLabsTTS( sessionId: "s", text: "t" ),
    "OpenAI TTS request failed"      : ( s ) => s.requestOpenAITTS( sessionId: "s", text: "t" ),
    // ignore: deprecated_member_use_from_same_package - the deprecated method still logs its failure
    "Audio upload failed"            : ( s ) => s.uploadAndTranscribe( filePath: "/nonexistent/a.wav", sessionId: "s" ),
    "GET request failed"             : ( s ) => s.get<dynamic>( "/x" ),
    "POST request failed"            : ( s ) => s.post<dynamic>( "/x" ),
    "PUT request failed"             : ( s ) => s.put<dynamic>( "/x" ),
    "DELETE request failed"          : ( s ) => s.delete<dynamic>( "/x" ),
  };

  for ( final failure in failures.entries ) {
    test( "${failure.key}: one error entry, tag HTTP, no token", () async {
      await quiet( () async {
        try {
          await failure.value( service );
        } catch ( _ ) {
          // the method rethrows; the log entry is what this test reads
        }
      } );

      final httpErrors = capture.entries.where( ( e ) => e.tag == "HTTP" && e.level == LogLevel.error );
      expect( httpErrors, hasLength( 1 ) );
      expect( httpErrors.single.message, failure.key );
      expect( httpErrors.single.error, isNotNull );
      expect( jsonEncode( httpErrors.single.toJson() ), isNot( contains( _jwt ) ) );
    } );
  }

  test( "Health check failed: error entry, tag HTTP, returns false, no token", () async {
    final ok = await quiet( () => service.checkHealth() );

    expect( ok, isFalse );
    final entry = capture.entries.singleWhere( ( e ) => e.tag == "HTTP" && e.level == LogLevel.error );
    expect( entry.message, "Health check failed" );
    expect( jsonEncode( entry.toJson() ), isNot( contains( _jwt ) ) );
  } );
}
