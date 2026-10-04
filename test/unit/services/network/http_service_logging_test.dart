// HttpService failure paths log through the app Logger at error level with the
// HTTP tag, and no credential reaches the entry.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

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

  final failures = <String, ( String, Future<Object?> Function( HttpService ), Matcher )>{
    "Session ID request failed"      : ( "/api/get-session-id", ( s ) => s.getSessionId(), isA<DioException>() ),
    "ElevenLabs TTS request failed"  : ( "/api/get-speech-elevenlabs", ( s ) => s.requestElevenLabsTTS( sessionId: "s", text: "t" ), isA<DioException>() ),
    "OpenAI TTS request failed"      : ( "/api/get-speech", ( s ) => s.requestOpenAITTS( sessionId: "s", text: "t" ), isA<DioException>() ),
    // ignore: deprecated_member_use_from_same_package - the deprecated method still logs its failure
    "Audio upload failed"            : ( "/api/upload-and-transcribe-mp3", ( s ) => s.uploadAndTranscribe( filePath: "/nonexistent/a.wav", sessionId: "s" ), isA<FileSystemException>() ),
    "GET request failed"             : ( "/x", ( s ) => s.get<dynamic>( "/x" ), isA<DioException>() ),
    "POST request failed"            : ( "/x", ( s ) => s.post<dynamic>( "/x" ), isA<DioException>() ),
    "PUT request failed"             : ( "/x", ( s ) => s.put<dynamic>( "/x" ), isA<DioException>() ),
    "DELETE request failed"          : ( "/x", ( s ) => s.delete<dynamic>( "/x" ), isA<DioException>() ),
  };

  for ( final failure in failures.entries ) {
    final ( path, call, thrown ) = failure.value;

    test( "${failure.key}: one error entry with tag, path, stack, no token; the original exception reaches the caller", () async {
      await quiet( () async {
        await expectLater( call( service ), throwsA( thrown ) );
      } );

      final httpErrors = capture.entries.where( ( e ) => e.tag == "HTTP" && e.level == LogLevel.error );
      expect( httpErrors, hasLength( 1 ) );
      final entry = httpErrors.single;
      expect( entry.message, failure.key );
      expect( entry.error, isNotNull );
      expect( entry.stackTrace, isNotNull );
      expect( entry.context!.metadata![ "path" ], path );
      expect( jsonEncode( entry.toJson() ), isNot( contains( _jwt ) ) );
    } );
  }

  test( "the path in the entry has no query string", () async {
    await quiet( () async {
      await expectLater( service.get<dynamic>( "/x?token=query-secret&a=1" ), throwsA( isA<DioException>() ) );
    } );

    final entry = capture.entries.singleWhere( ( e ) => e.tag == "HTTP" && e.level == LogLevel.error );
    expect( entry.context!.metadata![ "path" ], "/x" );
    expect( jsonEncode( entry.context!.toJson() ), isNot( contains( "query-secret" ) ) );
  } );

  test( "Health check failed: error entry, tag HTTP, returns false, no token", () async {
    final ok = await quiet( () => service.checkHealth() );

    expect( ok, isFalse );
    final entry = capture.entries.singleWhere( ( e ) => e.tag == "HTTP" && e.level == LogLevel.error );
    expect( entry.message, "Health check failed" );
    expect( entry.context!.metadata![ "path" ], "/health" );
    expect( entry.stackTrace, isNotNull );
    expect( jsonEncode( entry.toJson() ), isNot( contains( _jwt ) ) );
  } );
}
