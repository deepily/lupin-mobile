// Logger core: redaction at the choke point, the no-destination fallback,
// release console output, and the file destination's flush behaviour.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/logging/log_file_store.dart';
import 'package:lupin_mobile/core/logging/logger.dart';

// Synthetic JWT, structurally valid and made up.
const String _jwt =
    "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9"
    ".eyJzdWIiOiJ0ZXN0LXVzZXItaWQiLCJlbWFpbCI6InRlc3RAZXhhbXBsZS5jb20ifQ"
    ".ZmFrZXNpZ25hdHVyZUZPUlRFU1RTT05MWQ";

class _CaptureDestination implements LogDestination {
  final List<LogEntry> entries = [];

  @override
  void write( LogEntry entry ) => entries.add( entry );

  @override
  Future<void> flush() async {}
}

class _FakeStore implements LogFileStore {
  final List<String> appended = [];
  Completer<void>? gate;
  bool failAppend = false;

  @override
  Future<void> appendToFile( String fileName, String data ) async {
    if ( gate != null ) await gate!.future;
    if ( failAppend ) throw Exception( "disk full" );
    appended.add( data );
  }

  @override
  Future<int?> getFileSize( String fileName ) async => 0;

  @override
  Future<bool> fileExists( String fileName ) async => false;

  @override
  Future<void> deleteFile( String fileName ) async {}

  @override
  Future<void> renameFile( String oldFileName, String newFileName ) async {}
}

LogEntry _entry( LogLevel level, String message ) =>
    LogEntry( timestamp: DateTime.now(), level: level, message: message, tag: "T" );

List<String> _jsonLines( List<String> appended ) =>
    appended.expand( ( s ) => s.trim().split( "\n" ) ).toList();

void main() {
  late DebugPrintCallback originalDebugPrint;
  late List<String> debugLines;

  setUp( () {
    Logger.resetForTesting();
    originalDebugPrint = debugPrint;
    debugLines         = [];
    debugPrint         = ( String? message, { int? wrapWidth } ) => debugLines.add( message ?? "" );
  } );

  tearDown( () {
    debugPrint = originalDebugPrint;
    Logger.resetForTesting();
  } );

  group( "Logger.log", () {
    test( "an entry reaches an attached destination with its level and tag", () {
      final cap = _CaptureDestination();
      Logger.addDestination( cap );

      Logger.error( "boom", tag: "HTTP" );

      expect( cap.entries, hasLength( 1 ) );
      expect( cap.entries.single.level, LogLevel.error );
      expect( cap.entries.single.tag, "HTTP" );
      expect( cap.entries.single.message, "boom" );
    } );

    test( "credentials in the message and in the error text are masked", () {
      final cap = _CaptureDestination();
      Logger.addDestination( cap );

      Logger.error(
        "request failed Authorization: Bearer $_jwt",
        tag  : "HTTP",
        error: Exception( "body {refresh_token: opaque-refresh-value} $_jwt" ),
      );

      final entry = cap.entries.single;
      expect( entry.message, isNot( contains( _jwt ) ) );
      expect( "${entry.error}", isNot( contains( _jwt ) ) );
      expect( "${entry.error}", isNot( contains( "opaque-refresh-value" ) ) );
      expect( jsonEncode( entry.toJson() ), isNot( contains( _jwt ) ) );
    } );

    test( "with no destination, a warning goes to debugPrint and an info does not", () {
      Logger.warning( "early failure", tag: "WebSocket" );
      Logger.info( "early chatter", tag: "WebSocket" );

      expect( debugLines, hasLength( 1 ) );
      expect( debugLines.single, contains( "[WebSocket] early failure" ) );
    } );

    test( "the no-destination fallback is masked too", () {
      Logger.error( "Authorization: Bearer $_jwt" );

      expect( debugLines.join(), isNot( contains( _jwt ) ) );
    } );

    test( "initialize refuses file logging without a file store", () {
      expect(
        () => Logger.initialize( enableConsole: false, enableFile: true ),
        throwsArgumentError,
      );
    } );
  } );

  group( "ConsoleLogDestination", () {
    test( "release mode prints warnings and above through debugPrint, not info", () {
      final console = ConsoleLogDestination( debugMode: false );

      console.write( _entry( LogLevel.info, "chatter" ) );
      console.write( _entry( LogLevel.warning, "careful" ) );
      console.write( _entry( LogLevel.error, "broken" ) );

      expect( debugLines, hasLength( 2 ) );
      expect( debugLines[ 0 ], contains( "careful" ) );
      expect( debugLines[ 1 ], contains( "broken" ) );
    } );

    test( "debug mode prints every level to the zone print", () {
      final printed = <String>[];
      runZoned(
        () {
          final console = ConsoleLogDestination( debugMode: true );
          console.write( _entry( LogLevel.debug, "detail" ) );
          console.write( _entry( LogLevel.error, "broken" ) );
        },
        zoneSpecification: ZoneSpecification( print: ( _, __, ___, line ) => printed.add( line ) ),
      );

      expect( printed, hasLength( 2 ) );
      expect( debugLines, isEmpty );
    } );
  } );

  group( "FileLogDestination", () {
    test( "an error entry is written at once; an info entry waits for the buffer", () async {
      final store = _FakeStore();
      final file  = FileLogDestination( store );

      file.write( _entry( LogLevel.info, "quiet" ) );
      await Future<void>.delayed( Duration.zero );
      expect( store.appended, isEmpty );

      file.write( _entry( LogLevel.error, "loud" ) );
      await Future<void>.delayed( Duration.zero );

      expect( _jsonLines( store.appended ), hasLength( 2 ), reason: "no flush() call was made" );
    } );

    test( "a burst of errors during a slow write is written once each, never twice", () async {
      final store = _FakeStore()..gate = Completer<void>();
      final file  = FileLogDestination( store );

      for ( var i = 0; i < 5; i++ ) {
        file.write( _entry( LogLevel.error, "e$i" ) );
      }
      store.gate!.complete();
      await file.flush();

      final lines = _jsonLines( store.appended );
      expect( lines, hasLength( 5 ) );
      expect( lines.toSet(), hasLength( 5 ) );
      expect( store.appended.length, lessThanOrEqualTo( 2 ), reason: "coalesced into at most two writes" );
    } );

    test( "a failed write keeps the entries and the next flush writes them", () async {
      final store = _FakeStore()..failAppend = true;
      final file  = FileLogDestination( store );

      file.write( _entry( LogLevel.error, "kept" ) );
      await file.flush();
      expect( store.appended, isEmpty );

      store.failAppend = false;
      await file.flush();

      expect( _jsonLines( store.appended ), hasLength( 1 ) );
      expect( store.appended.single, contains( "kept" ) );
    } );

    test( "memory stays bounded while the file cannot be written", () async {
      final store = _FakeStore()..failAppend = true;
      final file  = FileLogDestination( store, bufferSize: 100000 );

      for ( var i = 0; i < FileLogDestination.maxBufferedEntries + 50; i++ ) {
        file.write( _entry( LogLevel.info, "m$i" ) );
      }
      await file.flush();
      store.failAppend = false;
      await file.flush();

      final lines = _jsonLines( store.appended );
      expect( lines, hasLength( FileLogDestination.maxBufferedEntries ) );
      expect( lines.first, contains( "m50" ), reason: "the oldest entries were dropped" );
    } );
  } );
}
