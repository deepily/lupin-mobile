// Row f262281c: a buffered warning must reach the log file when the app is
// paused or detached, because a low-memory kill or a swipe-away gives no later chance.
// Rule 1: pause and detach flush. Rule 2: one flush in flight, a pause during it runs one follow-up.
// Rule 3: a flush never throws. Rule 4: a hung flush is abandoned after a timeout.

import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:lupin_mobile/core/logging/log_file_store.dart';
import 'package:lupin_mobile/core/logging/logger.dart';
import 'package:lupin_mobile/services/lifecycle/app_lifecycle_service.dart';

class _FakeStore implements LogFileStore {
  final List<String> appended = [];

  @override
  Future<void> appendToFile( String fileName, String data ) async => appended.add( data );

  @override
  Future<int?> getFileSize( String fileName ) async => 0;

  @override
  Future<bool> fileExists( String fileName ) async => false;

  @override
  Future<void> deleteFile( String fileName ) async {}

  @override
  Future<void> renameFile( String oldFileName, String newFileName ) async {}
}

class _CountingDestination implements LogDestination {
  int flushCalls = 0;
  Completer<void>? gate;

  @override
  void write( LogEntry entry ) {}

  @override
  Future<void> flush() async {
    flushCalls++;
    if ( gate != null ) await gate!.future;
  }
}

class _ThrowingFlushDestination implements LogDestination {
  final bool throwSynchronously;
  _ThrowingFlushDestination( { this.throwSynchronously = false } );

  @override
  void write( LogEntry entry ) {}

  @override
  Future<void> flush() {
    if ( throwSynchronously ) throw StateError( "flush exploded" );
    return Future.error( StateError( "flush exploded" ) );
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  // The service is a process-wide singleton and cannot be disposed and re-initialized.
  setUpAll( () => AppLifecycleService().initialize() );

  setUp( () {
    Logger.resetForTesting();
    binding.handleAppLifecycleStateChanged( AppLifecycleState.resumed );
  } );

  tearDown( Logger.resetForTesting );

  Future<void> settle() => Future<void>.delayed( Duration.zero );

  group( "flush on pause", () {
    test( "a warning logged before pause is in the file store afterwards", () async {
      final store = _FakeStore();
      await Logger.initialize( enableConsole: false, fileStore: store );

      Logger.warning( "low-memory kill follows", tag: "T" );
      expect( store.appended, isEmpty, reason: "a warning waits for the buffer" );

      binding.handleAppLifecycleStateChanged( AppLifecycleState.paused );
      await settle();

      expect( store.appended.join(), contains( "low-memory kill follows" ) );
    } );

    test( "detached flushes too", () async {
      final store = _FakeStore();
      await Logger.initialize( enableConsole: false, fileStore: store );

      Logger.warning( "swipe-away follows", tag: "T" );
      binding.handleAppLifecycleStateChanged( AppLifecycleState.detached );
      await settle();

      expect( store.appended.join(), contains( "swipe-away follows" ) );
    } );

    test( "going inactive does not flush", () async {
      final counting = _CountingDestination();
      Logger.addDestination( counting );

      binding.handleAppLifecycleStateChanged( AppLifecycleState.inactive );
      await settle();

      expect( counting.flushCalls, 0 );
    } );
  } );

  test( "one flush stays in flight; a pause during it is remembered and runs once more", () async {
    final counting = _CountingDestination()..gate = Completer<void>();
    Logger.addDestination( counting );

    binding.handleAppLifecycleStateChanged( AppLifecycleState.paused );
    binding.handleAppLifecycleStateChanged( AppLifecycleState.resumed );
    binding.handleAppLifecycleStateChanged( AppLifecycleState.paused );
    binding.handleAppLifecycleStateChanged( AppLifecycleState.resumed );
    binding.handleAppLifecycleStateChanged( AppLifecycleState.paused );
    await settle();
    expect( counting.flushCalls, 1, reason: "later pauses arrive while the first flush is running" );

    counting.gate!.complete();
    await settle();
    await settle();
    expect( counting.flushCalls, 2, reason: "the pauses during the flush are covered by exactly one follow-up" );

    binding.handleAppLifecycleStateChanged( AppLifecycleState.resumed );
    binding.handleAppLifecycleStateChanged( AppLifecycleState.paused );
    await settle();
    expect( counting.flushCalls, 3, reason: "a pause after the flush ended starts a new one" );
  } );

  test( "a flush that never ends is abandoned, and a later pause flushes again", () async {
    final original = AppLifecycleService.logFlushTimeout;
    AppLifecycleService.logFlushTimeout = const Duration( milliseconds: 50 );
    addTearDown( () => AppLifecycleService.logFlushTimeout = original );

    final hung = _CountingDestination()..gate = Completer<void>();
    Logger.addDestination( hung );

    binding.handleAppLifecycleStateChanged( AppLifecycleState.paused );
    await Future<void>.delayed( const Duration( milliseconds: 150 ) );
    expect( hung.flushCalls, 1 );

    final store = _FakeStore();
    await Logger.initialize( enableConsole: false, fileStore: store );
    Logger.warning( "after the hung flush", tag: "T" );
    binding.handleAppLifecycleStateChanged( AppLifecycleState.resumed );
    binding.handleAppLifecycleStateChanged( AppLifecycleState.paused );
    await Future<void>.delayed( const Duration( milliseconds: 150 ) );

    expect( hung.flushCalls, 2, reason: "the latch was released by the timeout" );
    expect( store.appended.join(), contains( "after the hung flush" ) );
  } );

  group( "a failing flush never throws", () {
    for ( final sync in [ false, true ] ) {
      test( sync ? "a destination that throws synchronously" : "a destination whose future fails", () async {
        Logger.addDestination( _ThrowingFlushDestination( throwSynchronously: sync ) );
        final store = _FakeStore();
        await Logger.initialize( enableConsole: false, fileStore: store );

        Logger.warning( "after the failing destination", tag: "T" );
        binding.handleAppLifecycleStateChanged( AppLifecycleState.paused );
        await settle();
        await settle();

        // The lifecycle callback survived: the state moved and the next transition still works.
        expect( AppLifecycleService().currentLifecycleState, AppLifecycleState.paused );
        binding.handleAppLifecycleStateChanged( AppLifecycleState.resumed );
        expect( AppLifecycleService().currentLifecycleState, AppLifecycleState.resumed );
      } );
    }
  } );
}
