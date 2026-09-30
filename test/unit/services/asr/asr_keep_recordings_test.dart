/// Row 9b1f7701 — debug "Keep voice recordings": when ON, every recording is
/// copied to the kept-recordings folder before `discardPendingUpload` deletes
/// it; when OFF nothing is copied; a failed copy never stops the delete.
library;

import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:record/record.dart';

import 'package:lupin_mobile/features/queue/data/queue_models.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_bloc.dart';
import 'package:lupin_mobile/features/quick_ask/domain/quick_ask_event.dart';
import 'package:lupin_mobile/services/asr/asr_service.dart';

import '../../quick_ask/_quick_ask_harness.dart';

class _MockDio      extends Mock implements Dio {}
class _MockRecorder extends Mock implements AudioRecorder {}

const _wavBytes = [ 0x52, 0x49, 0x46, 0x46, 0x24, 0x00, 0x00, 0x00, 0x57, 0x41, 0x56, 0x45 ];

void main() {
  late _MockRecorder recorder;
  late Directory     tempDir;
  late Directory     keptDir;
  late bool          keepOn;
  late int           copies;
  late bool          copyThrows;

  setUpAll( () {
    registerFallbackValue( const RecordConfig() );
    registerFallbackValue( AudioEncoder.wav );
    registerFallbackValue( const AskRequest( question: '_fallback' ) );
  } );

  setUp( () async {
    recorder   = _MockRecorder();
    tempDir    = await Directory.systemTemp.createTemp( 'asr-keep-tmp-' );
    final root = await Directory.systemTemp.createTemp( 'asr-keep-ext-' );
    keptDir    = Directory( '${root.path}/recordings' );
    keepOn     = false;
    copies     = 0;
    copyThrows = false;

    when( () => recorder.hasPermission() ).thenAnswer( ( _ ) async => true );
    when( () => recorder.isEncoderSupported( any() ) ).thenAnswer( ( _ ) async => true );
    when( () => recorder.start( any(), path: any( named: 'path' ) ) ).thenAnswer( ( _ ) async {} );
    when( () => recorder.cancel() ).thenAnswer( ( _ ) async {} );
  } );

  tearDown( () async {
    if ( tempDir.existsSync() ) await tempDir.delete( recursive: true );
    if ( keptDir.parent.existsSync() ) await keptDir.parent.delete( recursive: true );
  } );

  /// UTC clock on purpose: the kept-file name is stamped in UTC, so a local
  /// `DateTime` here would make the expected names depend on the machine's
  /// timezone.
  AsrService build( { DateTime Function()? clock } ) => AsrService(
    dio             : _MockDio(),
    recorder        : recorder,
    tempDirProvider : () async => tempDir,
    keepRecordings  : () => keepOn,
    keptDirProvider : () async => keptDir,
    clock           : clock ?? () => DateTime.utc( 2026, 9, 15, 7, 8, 9, 123 ),
    copyFile        : ( src, dest ) async {
      copies++;
      if ( copyThrows ) throw const FileSystemException( 'disk full' );
      await src.copy( dest );
    },
  );

  /// Record, have the mock recorder "write" the WAV, stop to file.
  Future<String> recordToFile( AsrService asr ) async {
    await asr.startRecording();
    final path = verify( () => recorder.start( any(), path: captureAny( named: 'path' ) ) )
        .captured.single as String;
    File( path ).writeAsBytesSync( _wavBytes );
    when( () => recorder.stop() ).thenAnswer( ( _ ) async => path );
    return asr.stopToFile();
  }

  group( 'AsrService keep voice recordings', () {
    test( 'OFF → no copy, the file is deleted synchronously', () async {
      final asr  = build();
      final path = await recordToFile( asr );

      asr.discardPendingUpload( path );

      expect( File( path ).existsSync(), isFalse, reason: 'OFF deletes before returning, as before' );
      expect( copies, 0 );
      expect( asr.lastKeep, isNull );
      expect( keptDir.existsSync(), isFalse, reason: 'OFF touches no folder' );
    } );

    test( 'ON → copy with the same bytes, named rec-<stamp>-<n>.ogg, then the original is deleted', () async {
      keepOn     = true;
      final asr  = build();
      final path = await recordToFile( asr );

      asr.discardPendingUpload( path );
      await asr.lastKeep;

      expect( File( path ).existsSync(), isFalse );
      final kept = File( '${keptDir.path}/rec-20260915-070809123Z-1.ogg' );
      expect( kept.existsSync(), isTrue );
      expect( kept.readAsBytesSync(), _wavBytes );

      // A second recording gets the next number.
      final second = await recordToFile( asr );
      asr.discardPendingUpload( second );
      await asr.lastKeep;
      expect( File( '${keptDir.path}/rec-20260915-070809123Z-2.ogg' ).existsSync(), isTrue );
      expect( File( second ).existsSync(), isFalse );
    } );

    test( 'ON + copy throws → the original is still deleted and nothing escapes', () async {
      keepOn     = true;
      copyThrows = true;
      final asr  = build();
      final path = await recordToFile( asr );

      expect( () => asr.discardPendingUpload( path ), returnsNormally );
      await expectLater( asr.lastKeep, completes );

      expect( copies, 1 );
      expect( File( path ).existsSync(), isFalse );
    } );

    test( 'ON + folder cannot be resolved → the original is still deleted', () async {
      keepOn    = true;
      final asr = AsrService(
        dio             : _MockDio(),
        recorder        : recorder,
        tempDirProvider : () async => tempDir,
        keepRecordings  : () => true,
        keptDirProvider : () async => throw StateError( 'no external storage' ),
      );
      final path = await recordToFile( asr );

      asr.discardPendingUpload( path );
      await expectLater( asr.lastKeep, completes );
      expect( File( path ).existsSync(), isFalse );
    } );

    test( 'a path the service never handed out is neither copied nor deleted', () async {
      keepOn       = true;
      final asr    = build();
      final stray  = File( '${tempDir.path}/stranger.wav' )..writeAsBytesSync( _wavBytes );

      asr.discardPendingUpload( stray.path );

      expect( asr.lastKeep, isNull );
      expect( copies, 0 );
      expect( stray.existsSync(), isTrue );
    } );
  } );

  group( 'Quick Ask send-immediately also keeps when ON', () {
    test( "the bloc's spoken-ask ending keeps the recording, then deletes it", () async {
      keepOn   = true;
      final asr = build();

      final repo          = MockQueueRepository();
      final ws            = MockWebSocketService();
      final notifications = MockNotificationRepository();
      final ctrl          = StreamController<SpokenAskEvent>();
      String? askedPath;

      when( () => ws.sessionId ).thenReturn( ourSession );
      when( () => ws.connectionStream ).thenAnswer( ( _ ) async* { yield true; } );
      String? startedPath;
      when( () => recorder.start( any(), path: any( named: 'path' ) ) ).thenAnswer( ( inv ) async {
        startedPath = inv.namedArguments[ #path ] as String;
        File( startedPath! ).writeAsBytesSync( _wavBytes );
      } );
      when( () => recorder.stop() ).thenAnswer( ( _ ) async => startedPath );
      when( () => repo.askSpoken( any(), any() ) ).thenAnswer( ( inv ) {
        askedPath = inv.positionalArguments.first as String;
        return ctrl.stream;
      } );

      final bloc = QuickAskBloc(
        repo,
        asr                  : asr,
        ws                   : ws,
        notifications        : notifications,
        prefs                : FakeQuickAskPreferences( stored: true ),
        userEmail            : ourEmail,
        requestMicPermission : () async => true,
      );

      await settle();   // let the CONNECTED replay land first
      bloc.add( const QuickAskRecordPressed() );
      await settle();
      bloc.add( const QuickAskRecordReleased() );
      await settle();
      expect( askedPath, isNotNull, reason: 'send-immediately posted the recording; state: ${bloc.state}' );
      expect( File( askedPath! ).existsSync(), isTrue );

      ctrl.add( const SpokenAskFailed( 'No speech was recognised, so nothing was asked.', statusCode: 422 ) );
      await settle();
      await asr.lastKeep;

      expect( File( askedPath! ).existsSync(), isFalse );
      final kept = File( '${keptDir.path}/rec-20260915-070809123Z-1.ogg' );
      expect( kept.existsSync(), isTrue );
      expect( kept.readAsBytesSync(), _wavBytes );

      await bloc.close();
      await ctrl.close();
    } );
  } );

  /// Fold-later from the 3a1626f review (row 8d9b2a0c): `<n>` restarts at 1 on
  /// every app launch, so it cannot make the name unique across runs. Two runs
  /// recording in the same second produced the same name and the second copy
  /// overwrote the first — exactly the case the debug switch exists for,
  /// since Rick pulls the folder off the phone AFTER several sessions.
  group( 'kept-recording names survive an app restart', () {
    test( 'two runs a millisecond apart keep both files, though both counters say 1', () async {
      keepOn = true;

      // Run 1 — a fresh AsrService, so its kept-counter starts at zero.
      final first     = build( clock: () => DateTime.utc( 2026, 9, 15, 7, 8, 9, 400 ) );
      final firstPath = await recordToFile( first );
      first.discardPendingUpload( firstPath );
      await first.lastKeep;

      // Run 2 — the app was restarted: another AsrService, counter back to zero,
      // same wall-clock second.
      final second     = build( clock: () => DateTime.utc( 2026, 9, 15, 7, 8, 9, 401 ) );
      final secondPath = await recordToFile( second );
      second.discardPendingUpload( secondPath );
      await second.lastKeep;

      final kept = keptDir.listSync().whereType<File>().map( ( f ) => f.uri.pathSegments.last ).toList()..sort();
      expect( kept, [ 'rec-20260915-070809400Z-1.ogg', 'rec-20260915-070809401Z-1.ogg' ],
        reason: 'the second run must not overwrite the first' );
      expect( copies, 2 );
    } );

    test( 'the same instant and the same counter still collide — the stamp is what separates runs', () {
      final t = DateTime.utc( 2026, 9, 15, 7, 8, 9, 400 );
      expect( AsrService.keptFileNameFor( t, 1 ), AsrService.keptFileNameFor( t, 1 ) );
      expect(
        AsrService.keptFileNameFor( t, 1 ),
        isNot( AsrService.keptFileNameFor( t.add( const Duration( milliseconds: 1 ) ), 1 ) ),
      );
    } );
  } );

  test( 'keptFileNameFor pads every field, down to the milliseconds', () {
    expect(
      AsrService.keptFileNameFor( DateTime.utc( 2026, 1, 2, 3, 4, 5, 6 ), 7 ),
      'rec-20260102-030405006Z-7.wav',
    );
  } );

  test( 'keptFileNameFor stamps UTC, whatever timezone the device is in', () {
    final instant = DateTime.utc( 2026, 1, 2, 3, 4, 5, 6 );
    // Same instant, expressed in the machine's local zone: the name must not move.
    expect( AsrService.keptFileNameFor( instant.toLocal(), 7 ), 'rec-20260102-030405006Z-7.wav' );
  } );

  // Row 4be8fe63: kept recordings moved from the external app folder, which
  // Android 11+ will not let adb or run-as read, to internal storage.
  group( 'kept recordings live where a debug build can hand them over', () {
    test( 'the folder is <base>/recordings under the injected base', () async {
      final base = await Directory.systemTemp.createTemp( 'asr-kept-base-' );
      addTearDown( () => base.delete( recursive: true ) );

      final dir = await AsrService.keptRecordingsDirectory( baseDir: () async => base );

      expect( dir.path, '${base.path}/recordings' );
      expect( dir.existsSync(), isFalse, reason: 'resolving the folder must not create it' );
    } );

    test( 'the documented pull command targets internal storage via run-as', () {
      // The default base (getApplicationSupportDirectory) needs the platform
      // channel, so the device pull is its real test. This pins the command
      // people will copy, so it cannot drift back to the unreadable folder.
      expect( AsrService.keptRecordingPullHint, contains( 'run-as ai.deepily.lupin_mobile' ) );
      expect( AsrService.keptRecordingPullHint, contains( 'files/recordings/' ),
          reason: 'run-as starts in the app data dir; getApplicationSupportDirectory is <data>/files' );
      expect( AsrService.keptRecordingPullHint, isNot( contains( '/sdcard' ) ) );
      expect( AsrService.keptRecordingPullHint, isNot( contains( 'Android/data' ) ) );
    } );
  } );
}
